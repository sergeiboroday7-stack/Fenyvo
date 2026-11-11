part of '../screens/chat_screen.dart';

/// Message search UI and navigation.
extension _PrivateMessageSearch on _ChatScreenState {
  void _recalculateSearchMatches() {
    final previousId =
        _searchMatchIndex >= 0 && _searchMatchIndex < _searchMatchIds.length
        ? _searchMatchIds[_searchMatchIndex]
        : '';

    _searchMatchIds = _messages
        .where((message) => MessageSearchService.matches(message, _searchQuery))
        .map(_getMessageId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (_searchMatchIds.isEmpty) {
      _searchMatchIndex = -1;
      return;
    }

    final previousIndex = previousId.isEmpty
        ? -1
        : _searchMatchIds.indexOf(previousId);
    _searchMatchIndex = previousIndex >= 0
        ? previousIndex
        : _searchMatchIds.length - 1;
  }

  void _openMessageSearch() {
    _updateMessageSearchState(() {
      _searchMode = true;
      _searchQuery = _searchController.text.trim();
      _recalculateSearchMatches();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeMessageSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _updateMessageSearchState(() {
      _searchMode = false;
      _searchQuery = '';
      _searchMatchIds = <String>[];
      _searchMatchIndex = -1;
    });
  }

  void _onMessageSearchChanged(String value) {
    _updateMessageSearchState(() {
      _searchQuery = value.trim();
      _recalculateSearchMatches();
    });

    if (_searchMatchIndex >= 0) {
      unawaited(_jumpToCurrentSearchMatch());
    }
  }

  Future<void> _jumpToCurrentSearchMatch() async {
    if (_searchMatchIndex < 0 || _searchMatchIndex >= _searchMatchIds.length) {
      return;
    }

    final id = _searchMatchIds[_searchMatchIndex];
    final index = _messages.indexWhere(
      (message) => _getMessageId(message) == id,
    );
    if (index >= 0) await _jumpToPinnedMessage(_messages[index]);
  }

  Future<void> _nextMessageSearchMatch({required bool newer}) async {
    if (_searchMatchIds.isEmpty) return;

    _updateMessageSearchState(() {
      if (_searchMatchIndex < 0) {
        _searchMatchIndex = _searchMatchIds.length - 1;
      } else if (newer) {
        _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatchIds.length;
      } else {
        _searchMatchIndex =
            (_searchMatchIndex - 1 + _searchMatchIds.length) %
            _searchMatchIds.length;
      }
    });

    await _jumpToCurrentSearchMatch();
  }

  Widget _buildMessageSearchBar() {
    final matchCount = _searchMatchIds.length;
    final current = _searchMatchIndex >= 0 ? _searchMatchIndex + 1 : 0;

    return Container(
      color: FenyvoPalette.surface,
      padding: EdgeInsets.fromLTRB(
        Platform.isWindows ? 16 : 10,
        7,
        Platform.isWindows ? 16 : 10,
        7,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onMessageSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: FenyvoPalette.ink),
              decoration: InputDecoration(
                hintText: _chatText('searchConversationHint'),
                hintStyle: const TextStyle(color: FenyvoPalette.muted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _ChatScreenState._gold,
                ),
                suffixText: _searchQuery.isEmpty
                    ? null
                    : '$current/$matchCount',
                suffixStyle: const TextStyle(
                  color: _ChatScreenState._gold,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: FenyvoPalette.canvasDeep,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _chatText('previousMatch'),
            onPressed: matchCount == 0
                ? null
                : () => unawaited(_nextMessageSearchMatch(newer: false)),
            icon: const Icon(
              Icons.keyboard_arrow_up_rounded,
              color: _ChatScreenState._gold,
            ),
          ),
          IconButton(
            tooltip: _chatText('nextMatch'),
            onPressed: matchCount == 0
                ? null
                : () => unawaited(_nextMessageSearchMatch(newer: true)),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _ChatScreenState._gold,
            ),
          ),
          IconButton(
            tooltip: _chatText('closeSearch'),
            onPressed: _closeMessageSearch,
            icon: const Icon(
              Icons.close_rounded,
              color: FenyvoPalette.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
