'use strict';

// FENYVO media HTTP module, isolated pilot.
// The original media HTTP block is preserved verbatim.
// This module is not yet connected to the main server.

function createMediaHttpService(deps) {
  if (!deps || typeof deps !== 'object') {
    throw new TypeError('Media HTTP dependencies are required');
  }

  const {
    http,
    fs,
    path,
    crypto,
    MEDIA_DIR,
    AVATARS_DIR,
    mediaIndex,
    callSignaling,
    SERVER_CONFIG,
    MAX_MEDIA_BYTES,
    MEDIA_PORT,
    jsonResponse,
    tokenFromRequest,
    mediaTokens,
    getAvatarPath,
    activeMediaUploadsByUser,
    MAX_CONCURRENT_MEDIA_UPLOADS,
    MAX_CONCURRENT_MEDIA_UPLOADS_PER_USER,
    availableMediaBytes,
    MEDIA_FREE_SPACE_RESERVE_BYTES,
    safeMediaFileName,
    safeMediaExtension,
    saveMediaIndex,
    mediaRecord,
    canDownloadMedia,
    uploadState,
  } = deps;

const mediaServer = http.createServer((req, res) => {
  const callUrl = new URL(req.url || '/', 'http://localhost');
  const callRoute = /^\/calls\/([^/]+)(\/avatar)?$/.exec(callUrl.pathname);
  if (callRoute) {
    const id = callRoute[1];
    const capability = (req.headers.authorization || '').replace(/^Bearer /, '') || callUrl.searchParams.get('t');
    const pending = callSignaling.authorize(id, capability);
    if (!pending) { jsonResponse(res, 404, { ringing: false }); return; }
    if (req.method === 'POST' && !callRoute[2]) {
      callSignaling.decline(id, capability);
      jsonResponse(res, 200, { ended: true }); return;
    }
    if (req.method === 'GET' && callRoute[2]) {
      // Capability grants only the caller avatar for this ringing session.
      const avatarRoot = path.resolve(AVATARS_DIR);
      const avatarPath = path.resolve(getAvatarPath(pending.from));
      if (path.dirname(avatarPath) !== avatarRoot || !fs.existsSync(avatarPath)) {
        jsonResponse(res, 404, {}); return;
      }
      res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Cache-Control': 'no-store' });
      fs.createReadStream(avatarPath).on('error', () => res.destroy()).pipe(res); return;
    }
    if (req.method === 'GET') {
      jsonResponse(res, 200, { ringing: true, expiresAt: pending.expiresAt }); return;
    }
    jsonResponse(res, 405, {}); return;
  }
  const token = tokenFromRequest(req);
  const owner = mediaTokens.get(token);
  if (!owner) {
    jsonResponse(res, 401, { error: 'Требуется вход в Fenyvo' });
    return;
  }

  const requestUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'POST' && requestUrl.pathname === '/media/upload') {
    const contentLength = Number(req.headers['content-length'] || 0);
    if (!Number.isFinite(contentLength) || contentLength <= 0) {
      jsonResponse(res, 411, { error: 'Не указан размер файла' });
      return;
    }
    if (contentLength > MAX_MEDIA_BYTES) {
      jsonResponse(res, 413, { error: 'Файл слишком большой. Максимум 1 ГБ' });
      return;
    }
    const ownerUploads = activeMediaUploadsByUser.get(owner) || 0;
    if (
      uploadState.activeMediaUploads >= MAX_CONCURRENT_MEDIA_UPLOADS ||
      ownerUploads >= MAX_CONCURRENT_MEDIA_UPLOADS_PER_USER
    ) {
      jsonResponse(res, 429, { error: 'Слишком много одновременных загрузок' });
      return;
    }
    try {
      const availableBytes = availableMediaBytes() - uploadState.mediaUploadBytesInFlight;
      if (availableBytes < contentLength + MEDIA_FREE_SPACE_RESERVE_BYTES) {
        jsonResponse(res, 507, { error: 'Недостаточно свободного места на сервере' });
        return;
      }
    } catch (error) {
      console.error('Не удалось проверить свободное место:', error.message);
      jsonResponse(res, 503, { error: 'Хранилище временно недоступно' });
      return;
    }

    uploadState.activeMediaUploads += 1;
    uploadState.mediaUploadBytesInFlight += contentLength;
    activeMediaUploadsByUser.set(owner, ownerUploads + 1);
    let uploadReservationReleased = false;
    const releaseUploadReservation = () => {
      if (uploadReservationReleased) return;
      uploadReservationReleased = true;
      uploadState.activeMediaUploads = Math.max(0, uploadState.activeMediaUploads - 1);
      uploadState.mediaUploadBytesInFlight = Math.max(
        0,
        uploadState.mediaUploadBytesInFlight - contentLength,
      );
      const remaining = (activeMediaUploadsByUser.get(owner) || 1) - 1;
      if (remaining <= 0) activeMediaUploadsByUser.delete(owner);
      else activeMediaUploadsByUser.set(owner, remaining);
    };

    const fileName = safeMediaFileName(requestUrl.searchParams.get('fileName') || 'file.bin');
    const mimeType = (requestUrl.searchParams.get('mimeType') || req.headers['content-type'] || 'application/octet-stream')
      .toString().slice(0, 120);
    const messageType = (requestUrl.searchParams.get('messageType') || 'file')
      .toString().slice(0, 24);
    const mediaId = crypto.randomUUID();
    const storedName = `${mediaId}${safeMediaExtension(fileName)}`;
    const target = path.join(MEDIA_DIR, storedName);
    const output = fs.createWriteStream(target, { flags: 'wx' });
    let received = 0;
    let failed = false;

    const fail = (status, reason) => {
      if (failed) return;
      failed = true;
      releaseUploadReservation();
      try { output.destroy(); } catch (_) {}
      try { if (fs.existsSync(target)) fs.unlinkSync(target); } catch (_) {}
      if (!res.headersSent) jsonResponse(res, status, { error: reason });
    };

    req.on('data', (chunk) => {
      if (failed) return;
      received += chunk.length;
      if (received > MAX_MEDIA_BYTES) {
        fail(413, 'Файл слишком большой. Максимум 1 ГБ');
        req.destroy();
        return;
      }
      if (!output.write(chunk)) {
        req.pause();
        output.once('drain', () => req.resume());
      }
    });

    req.on('end', () => {
      if (failed) return;
      output.end(() => {
        if (failed) return;
        if (received <= 0 || received !== contentLength) {
          fail(400, 'Файл получен не полностью');
          return;
        }
        mediaIndex[mediaId] = {
          owner,
          storedName,
          fileName,
          fileSize: received,
          mimeType,
          messageType,
          createdAt: new Date().toISOString(),
        };
        saveMediaIndex();
        releaseUploadReservation();
        jsonResponse(res, 201, {
          mediaId,
          fileName,
          fileSize: received,
          mimeType,
        });
        console.log(`📦 Медиа загружено: ${owner} → ${fileName} (${(received / 1024 / 1024).toFixed(1)} МБ)`);
      });
    });

    req.on('error', () => fail(400, 'Соединение при загрузке оборвалось'));
    req.on('aborted', () => fail(400, 'Загрузка отменена'));
    output.on('error', () => fail(500, 'Не удалось сохранить файл'));
    return;
  }

  if (req.method === 'GET' && requestUrl.pathname.startsWith('/media/')) {
    const mediaId = decodeURIComponent(requestUrl.pathname.slice('/media/'.length)).trim();
    const item = mediaRecord(mediaId);
    if (!item) {
      jsonResponse(res, 404, { error: 'Файл не найден' });
      return;
    }

    // A valid media token does not grant access to every media ID.
    if (typeof canDownloadMedia !== 'function' || canDownloadMedia(mediaId, owner) !== true) {
      jsonResponse(res, 403, { error: 'Доступ к файлу запрещён' });
      return;
    }
    const stat = fs.statSync(item.filePath);
    const total = stat.size;
    const mimeType = item.record.mimeType || 'application/octet-stream';
    const range = req.headers.range?.toString() || '';
    let start = 0;
    let end = total - 1;
    let status = 200;

    if (range) {
      const match = range.match(/^bytes=(\d*)-(\d*)$/i);
      if (!match || (!match[1] && !match[2])) {
        res.writeHead(416, { 'Content-Range': `bytes */${total}` });
        res.end();
        return;
      }
      if (match[1]) start = Number(match[1]);
      if (match[2]) end = Number(match[2]);
      if (!match[1] && match[2]) {
        const suffix = Number(match[2]);
        start = Math.max(0, total - suffix);
        end = total - 1;
      }
      if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || start > end || start >= total) {
        res.writeHead(416, { 'Content-Range': `bytes */${total}` });
        res.end();
        return;
      }
      end = Math.min(end, total - 1);
      status = 206;
    }

    const headers = {
      'Content-Type': mimeType,
      'Content-Length': end - start + 1,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'private, max-age=86400',
      'Content-Disposition': `inline; filename*=UTF-8''${encodeURIComponent(item.record.fileName || 'media.bin')}`,
    };
    if (status === 206) headers['Content-Range'] = `bytes ${start}-${end}/${total}`;
    res.writeHead(status, headers);
    fs.createReadStream(item.filePath, { start, end }).pipe(res);
    return;
  }

  jsonResponse(res, 404, { error: 'Не найдено' });
});

mediaServer.listen(MEDIA_PORT, SERVER_CONFIG.mediaHost, () => {
  console.log(`📦 Медиа-сервер: ${SERVER_CONFIG.mediaHost}:${MEDIA_PORT}`);
});

  return mediaServer;
}

module.exports = {
  createMediaHttpService,
};