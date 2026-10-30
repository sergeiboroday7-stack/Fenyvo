import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/download_service.dart';
import '../services/app_language_service.dart';
import '../services/saved_messages_service.dart';
import '../theme/fenyvo_theme.dart';
import '../widgets/emoji_picker.dart';

class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({super.key, required this.owner});
  final String owner;
  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  final _input = TextEditingController();
  bool _saving = false;
  bool _emojiVisible = false;
  final _inputFocus = FocusNode();
  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final text = _input.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await SavedMessagesService.save(widget.owner, {
        'text': text,
        'messageType': 'text',
      });
      if (mounted && _input.text.trim() == text) _input.clear();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.instance.text('savedNoteSaveFailed'),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLanguageService.instance.text('savedRemoveConfirm')),
        content: Text(AppLanguageService.instance.text('savedOriginalRemains')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLanguageService.instance.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLanguageService.instance.text('savedRemove')),
          ),
        ],
      ),
    );
    if (remove == true) {
      try {
        await SavedMessagesService.remove(widget.owner, item['id'].toString());
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLanguageService.instance.text('savedRemoveFailed'),
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLanguageService.instance.text('saved'),
            style: TextStyle(fontSize: 18),
          ),
          Text(
            AppLanguageService.instance.text('savedLocalOnly'),
            style: TextStyle(fontSize: 12, color: FenyvoPalette.secondary),
          ),
        ],
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: SavedMessagesService.changes,
            builder: (context, _, child) {
              final items = SavedMessagesService.items(widget.owner);
              if (items.isEmpty)
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_outline_rounded,
                          size: 56,
                          color: FenyvoPalette.gold,
                        ),
                        SizedBox(height: 16),
                        Text(
                          AppLanguageService.instance.text('savedEmptyTitle'),
                          style: TextStyle(fontSize: 20),
                        ),
                        SizedBox(height: 8),
                        Text(
                          AppLanguageService.instance.text('savedEmptyHint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: FenyvoPalette.secondary),
                        ),
                      ],
                    ),
                  ),
                );
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final origin = item['origin']?.toString() ?? '';
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      key: ValueKey(item['id']),
                      constraints: const BoxConstraints(maxWidth: 540),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: FenyvoPalette.blue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: Text(
                                  origin.isEmpty
                                      ? AppLanguageService.instance.text(
                                          'savedNoteLabel',
                                        )
                                      : AppLanguageService.instance
                                            .text('savedFromChat')
                                            .replaceAll(
                                              '{origin}',
                                              origin.toString(),
                                            ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: FenyvoPalette.secondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: AppLanguageService.instance.text(
                                  'savedActions',
                                ),
                                onSelected: (action) async {
                                  if (action == 'remove') {
                                    await _remove(item);
                                  } else {
                                    await Clipboard.setData(
                                      ClipboardData(
                                        text: item['text']?.toString() ?? '',
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text(
                                      AppLanguageService.instance.text(
                                        'savedCopyText',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      AppLanguageService.instance.text(
                                        'savedRemoveFromSaved',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (item['localMediaPath'] != null)
                            SavedAttachment(item: item)
                          else
                            SelectableText(
                              item['text']?.toString() ?? '',
                              style: const TextStyle(fontSize: 16),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    onTap: () {
                      if (_emojiVisible) setState(() => _emojiVisible = false);
                    },
                    minLines: 1,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: AppLanguageService.instance.text(
                        'savedNoteHint',
                      ),
                      suffixIcon: IconButton(
                        tooltip: AppLanguageService.instance.text('emoji'),
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onPressed: () {
                          _inputFocus.unfocus();
                          setState(() => _emojiVisible = !_emojiVisible);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: AppLanguageService.instance.text('savedSaveNote'),
                  onPressed: _saving || _input.text.trim().isEmpty
                      ? null
                      : _saveNote,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
        if (_emojiVisible)
          SafeArea(
            top: false,
            child: ComposerEmojiPanel(
              controller: _input,
              height: (MediaQuery.sizeOf(context).height * .30).clamp(
                120.0,
                280.0,
              ),
              onChanged: () => setState(() {}),
              onClose: () => setState(() => _emojiVisible = false),
            ),
          ),
      ],
    ),
  );
}

class SavedAttachment extends StatefulWidget {
  const SavedAttachment({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  State<SavedAttachment> createState() => _SavedAttachmentState();
}

class _SavedAttachmentState extends State<SavedAttachment> {
  AudioPlayer? _audio;
  VideoPlayerController? _video;
  StreamSubscription<void>? _completed;
  bool _playing = false;
  bool _busy = false;
  String get _path => widget.item['localMediaPath'].toString();
  String get _type => widget.item['messageType']?.toString() ?? 'file';
  String get _name {
    final name = widget.item['fileName']?.toString() ?? '';
    return name.isNotEmpty ? name : File(_path).uri.pathSegments.last;
  }

  @override
  void dispose() {
    _completed?.cancel();
    _audio?.dispose();
    _video?.removeListener(_videoChanged);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_type == 'voice') {
        if (_audio == null) {
          _audio = AudioPlayer();
          _completed = _audio!.onPlayerComplete.listen((_) {
            if (mounted) setState(() => _playing = false);
          });
        }
        if (_playing) {
          await _audio!.pause();
        } else {
          if (_audio!.state == PlayerState.paused) {
            await _audio!.resume();
          } else {
            await _audio!.play(DeviceFileSource(_path));
          }
        }
        if (mounted) setState(() => _playing = !_playing);
      } else {
        if (_video == null) {
          _video = VideoPlayerController.file(File(_path));
          await _video!.initialize();
          if (!mounted) return;
          _video!.addListener(_videoChanged);
        }
        if (!mounted) return;
        if (_video!.value.isPlaying) {
          await _video!.pause();
        } else {
          if (_video!.value.position >= _video!.value.duration) {
            await _video!.seekTo(Duration.zero);
          }
          await _video!.play();
        }
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.instance.text('savedAttachmentOpenFailed'),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _videoChanged() {
    if (mounted && _playing != (_video?.value.isPlaying ?? false)) {
      setState(() => _playing = _video?.value.isPlaying ?? false);
    }
  }

  Future<void> _download() async {
    try {
      final result = await FenyvoDownloadService.saveBytes(
        bytes: await File(_path).readAsBytes(),
        fileName: _name,
        mimeType: widget.item['mimeType']?.toString() ?? '',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.instance
                  .text('savedExportedPath')
                  .replaceAll('{path}', result.toString()),
            ),
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.instance.text('savedExportFailed'),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_type == 'image')
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: Stack(
                children: [
                  InteractiveViewer(child: Image.file(File(_path))),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filledTonal(
                      tooltip: AppLanguageService.instance.text(
                        'savedClosePhoto',
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_path),
              height: 240,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  Text(AppLanguageService.instance.text('photoUnavailable')),
            ),
          ),
        ),
      if (_video != null && _video!.value.isInitialized)
        AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        ),
      Row(
        children: [
          if (_type == 'voice' || _type == 'video')
            IconButton(
              tooltip: AppLanguageService.instance.text('savedPlayPause'),
              onPressed: _busy ? null : _play,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      (_playing || (_video?.value.isPlaying ?? false))
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
            )
          else
            const Icon(Icons.insert_drive_file_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _type == 'voice'
                  ? AppLanguageService.instance.text('savedVoiceMessage')
                  : _name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: AppLanguageService.instance.text('savedDownloadFile'),
            onPressed: _download,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
    ],
  );
}
