import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/socket_service.dart';
import '../theme/fenyvo_theme.dart';
import 'contact_link_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.contacts,
    required this.onlineUsers,
    required this.onOpenChat,
  });

  final List<String> contacts;
  final Set<String> onlineUsers;
  final ValueChanged<String> onOpenChat;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _contactsScroll = ScrollController();
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ#';

  String? _activeLetter;
  double _letterFingerY = 0;
  bool _letterVisible = false;

  int _filter = 0;
  List<String> _serverContacts = [];
  bool _loadingContacts = true;
  Timer? _contactsTimeout;
  bool _contactsUnavailable = false;

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleContactMessage);
    _loadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshContacts();
    });
  }

  void _refreshContacts() {
    if (!mounted) return;

    _contactsTimeout?.cancel();

    setState(() {
      _loadingContacts = true;
      _contactsUnavailable = false;
    });

    SocketService.instance.getContacts();

    _contactsTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_loadingContacts) return;
      setState(() {
        _loadingContacts = false;
        _contactsUnavailable = true;
      });
    });
  }

  void _handleContactMessage(Map<String, dynamic> message) {
    if (!mounted || message['type'] != 'contacts') return;

    final raw = message['data'];
    if (raw is! Map) return;

    _contactsTimeout?.cancel();

    final users = raw['contacts'];
    if (users is! List) return;

    final currentUser = SocketService.instance.currentUser?.toLowerCase() ?? '';

    setState(() {
      _serverContacts = users
          .map((value) => value.toString().trim())
          .where((user) => user.isNotEmpty && user.toLowerCase() != currentUser)
          .toSet()
          .toList();
      _loadingContacts = false;
    });
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleContactMessage);
    _contactsTimeout?.cancel();
    _search.dispose();
    _contactsScroll.dispose();
    super.dispose();
  }

  void _selectAlphabetLetter(
    String letter,
    double fingerY,
    List<String> contacts,
  ) {
    if (_activeLetter != letter || _letterFingerY != fingerY) {
      setState(() {
        _activeLetter = letter;
        _letterFingerY = fingerY;
        _letterVisible = true;
      });
    }

    if (!_contactsScroll.hasClients || contacts.isEmpty) return;

    final index = contacts.indexWhere((user) {
      final name = user.trim().toUpperCase();
      if (name.isEmpty) return false;
      if (letter == '#') {
        return !RegExp(r'^[A-ZА-ЯЁ]').hasMatch(name);
      }
      return name.startsWith(letter);
    });

    if (index < 0) return;

    final maxScroll = _contactsScroll.position.maxScrollExtent;
    final target = (12.0 + index * 80.0).clamp(0.0, maxScroll);

    _contactsScroll.jumpTo(target);
  }

  void _endAlphabetGesture() {
    if (_activeLetter == null) return;
    setState(() => _letterVisible = false);
  }

  Widget _alphabetSlider(List<String> contacts) {
    final letters = _alphabet.split('');

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemHeight = constraints.maxHeight / letters.length;

        void selectAt(double y) {
          final position = y.clamp(0.0, constraints.maxHeight - 0.01);
          final index = (position / itemHeight).floor().clamp(
            0,
            letters.length - 1,
          );

          _selectAlphabetLetter(letters[index], position, contacts);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) => selectAt(details.localPosition.dy),
          onVerticalDragUpdate: (details) => selectAt(details.localPosition.dy),
          onVerticalDragEnd: (_) => _endAlphabetGesture(),
          onVerticalDragCancel: _endAlphabetGesture,
          onTapDown: (details) => selectAt(details.localPosition.dy),
          onTapUp: (_) => _endAlphabetGesture(),
          child: Column(
            children: [
              for (final letter in letters)
                Expanded(
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: _activeLetter == letter
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _activeLetter == letter
                            ? const Color(0xFFFFD54F)
                            : FenyvoPalette.secondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _addContact() {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '@username',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final username = controller.text.trim().replaceFirst(
                RegExp(r'^@'),
                '',
              );
              if (username.isEmpty) return;
              Navigator.pop(dialogContext);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContactLinkScreen(username: username),
                ),
              );
            },
            child: const Text('Найти'),
          ),
        ],
      ),
    );
  }

  final Set<String> _favorites = <String>{};
  String get _favoritesKey {
    final user = SocketService.instance.currentUser?.trim().toLowerCase() ?? '';
    return 'fenyvo_favorites_$user';
  }

  Future<void> _loadFavorites() async {
    final user = SocketService.instance.currentUser?.trim() ?? '';
    if (user.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_favoritesKey) ?? <String>[];

    if (!mounted) return;

    setState(() {
      _favorites
        ..clear()
        ..addAll(saved.map((name) => name.toLowerCase()));
    });
  }

  Future<void> _toggleFavorite(String username) async {
    final user = SocketService.instance.currentUser?.trim() ?? '';
    if (user.isEmpty) return;

    final id = username.toLowerCase();

    setState(() {
      if (!_favorites.add(id)) {
        _favorites.remove(id);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  bool _isOnline(String username) {
    return widget.onlineUsers.any(
      (user) => user.toLowerCase() == username.toLowerCase(),
    );
  }

  Widget _contactAvatar(String username) {
    final online = _isOnline(username);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: FenyvoPalette.surfaceSoft,
          child: Text(
            username.isEmpty ? '?' : username[0].toUpperCase(),
            style: const TextStyle(
              color: FenyvoPalette.gold,
              fontWeight: FontWeight.bold,
              fontSize: 21,
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: online ? FenyvoPalette.online : FenyvoPalette.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: FenyvoPalette.canvasDeep, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _favoriteCard(String username) {
    return Container(
      width: 116,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FenyvoPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FenyvoPalette.gold.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: () => widget.onOpenChat(username),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _contactAvatar(username),
            const SizedBox(height: 10),
            Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _isOnline(username) ? 'В сети' : 'Не в сети',
              style: TextStyle(
                fontSize: 10,
                color: _isOnline(username)
                    ? FenyvoPalette.online
                    : FenyvoPalette.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();

    final contacts =
        _serverContacts
            .where((user) => user.toLowerCase().contains(query))
            .where((user) {
              if (_filter == 1) {
                return _favorites.contains(user.toLowerCase());
              }
              if (_filter == 2) {
                return _isOnline(user);
              }
              if (_filter == 3) {
                return false;
              }
              return true;
            })
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final favoriteUsers = _serverContacts
        .where((user) => _favorites.contains(user.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: FenyvoPalette.canvasDeep,
      appBar: AppBar(
        title: const Text('Контакты'),
        actions: [
          IconButton(
            tooltip: 'Обновить контакты',
            onPressed: _refreshContacts,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Добавить контакт',
            onPressed: _addContact,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Поиск по имени или @username',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        ['Все', 'Избранные', 'Онлайн', 'Недавние'][i],
                      ),
                      selected: _filter == i,
                      onSelected: (_) => setState(() => _filter = i),
                    ),
                  ),
              ],
            ),
          ),
          if (favoriteUsers.isNotEmpty && _filter == 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Text(
                    'ИЗБРАННЫЕ',
                    style: TextStyle(
                      color: FenyvoPalette.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                SizedBox(
                  height: 142,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: favoriteUsers.length,
                    itemBuilder: (context, index) {
                      return _favoriteCard(favoriteUsers[index]);
                    },
                  ),
                ),
              ],
            ),
          Expanded(
            child: _contactsUnavailable
                ? Center(
                    key: const ValueKey('contacts-load-error'),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 54,
                            color: FenyvoPalette.gold,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Не удалось загрузить контакты',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Проверьте соединение с сервером Fenyvo.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _refreshContacts,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loadingContacts
                ? const Center(child: CircularProgressIndicator())
                : contacts.isEmpty
                ? Center(
                    child: Text(
                      'Контактов пока нет',
                      style: TextStyle(color: FenyvoPalette.secondary),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _contactsScroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final user = contacts[index];
                          final online = widget.onlineUsers.contains(user);

                          return SizedBox(
                            height: 80,
                            child: Card(
                              child: ListTile(
                                leading: _contactAvatar(user),
                                title: Text(user),
                                subtitle: Text(online ? 'В сети' : 'Не в сети'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Избранное',
                                      icon: Icon(
                                        _favorites.contains(user.toLowerCase())
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: FenyvoPalette.gold,
                                      ),
                                      onPressed: () => _toggleFavorite(user),
                                    ),
                                    IconButton(
                                      tooltip: 'Открыть чат',
                                      icon: const Icon(
                                        Icons.chat_bubble_outline,
                                      ),
                                      onPressed: () => widget.onOpenChat(user),
                                    ),
                                  ],
                                ),
                                onTap: () => widget.onOpenChat(user),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_activeLetter != null)
                        Positioned(
                          right: 45,
                          top: (_letterFingerY - 30).clamp(
                            0.0,
                            _contactsScroll.hasClients
                                ? (_contactsScroll.position.viewportDimension -
                                          66)
                                      .clamp(0.0, double.infinity)
                                : 0.0,
                          ),
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _letterVisible ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: Container(
                                width: 66,
                                height: 66,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD54F)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _activeLetter!,
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFFFD54F)
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 2,
                        width: 28,
                        child: _alphabetSlider(contacts),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
