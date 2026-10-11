(function () {
  'use strict';

  const platforms = ['android', 'windows', 'ios'];
  const endpoint = '/assets/download-counts.json';
  const eventPixel = '/assets/fenyvo-logo.png';

  function safeCount(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : 0;
  }

  function render(payload) {
    const locale = document.documentElement.lang || navigator.language || 'en';
    const formatter = new Intl.NumberFormat(locale);
    platforms.forEach(function (platform) {
      const element = document.getElementById('download-count-' + platform);
      if (element) element.textContent = formatter.format(safeCount(payload && payload[platform]));
    });
  }

  async function refresh() {
    try {
      const response = await fetch(endpoint + '?v=' + Date.now(), {
        cache: 'no-store',
        credentials: 'omit'
      });
      if (!response.ok) throw new Error('Counter unavailable');
      render(await response.json());
    } catch (_) {
      platforms.forEach(function (platform) {
        const element = document.getElementById('download-count-' + platform);
        if (element && element.textContent.trim() === '—') element.textContent = '0';
      });
    }
  }

  async function register(platform) {
    if (!platforms.includes(platform) || platform === 'ios') return;
    const eventId = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : Date.now().toString(36) + Math.random().toString(36).slice(2);
    const url = eventPixel + '?download_event=1&platform=' + encodeURIComponent(platform) + '&event=' + encodeURIComponent(eventId);
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timeout = controller ? setTimeout(function () { controller.abort(); }, 900) : null;
    try {
      await fetch(url, {
        cache: 'no-store',
        credentials: 'omit',
        keepalive: true,
        signal: controller ? controller.signal : undefined
      });
    } catch (_) {
      // A failed statistics request must never block the actual download.
    } finally {
      if (timeout) clearTimeout(timeout);
    }
  }

  window.fenyvoDownloads = { refresh: refresh, register: register };
  refresh();
  setInterval(refresh, 60000);
})();
