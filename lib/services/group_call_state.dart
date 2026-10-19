class GroupCallMember {
  const GroupCallMember({
    required this.user,
    required this.sessionId,
    this.muted = false,
    this.videoEnabled = true,
    this.away = false,
    this.disconnected = false,
    this.moderator = false,
    this.role = 'guest',
  });
  final String user;
  final String sessionId;
  final bool muted;
  final bool videoEnabled;
  final bool away;
  final bool disconnected;
  final bool moderator;
  final String role;
  bool get isHost => role == 'host';
  bool get isModerator => moderator || role == 'moderator';
  bool get isViewer => role == 'viewer';
}

class GroupCallState {
  const GroupCallState({
    required this.id,
    required this.groupId,
    required this.name,
    required this.startedBy,
    required this.members,
    this.owner = '',
    this.featuredUser = '',
    this.awaitingHost = false,
    this.pinnedMessage,
    this.hostGraceUntil,
    this.limit = 4,
  });
  final String id;
  final String groupId;
  final String name;
  final String startedBy;
  final List<GroupCallMember> members;
  final String owner;
  final String featuredUser;
  final bool awaitingHost;
  final Map<String, dynamic>? pinnedMessage;
  final int? hostGraceUntil;
  final int limit;

  bool get isWaitingForHost => awaitingHost || hostGraceUntil != null;

  static GroupCallState? parse(dynamic value) {
    if (value is! Map || value['participants'] is! List) return null;
    final id = value['id']?.toString() ?? '';
    final groupId = value['groupId']?.toString() ?? '';
    if (id.isEmpty || groupId.isEmpty) return null;
    final startedBy = value['startedBy']?.toString() ?? '';
    final rawOwner = value['owner']?.toString() ?? '';
    final owner = rawOwner.isEmpty ? startedBy : rawOwner;
    final rawGrace = value['hostGraceUntil'];
    final hostGraceUntil = rawGrace is num
        ? rawGrace.toInt()
        : int.tryParse(rawGrace?.toString() ?? '');
    final members = <GroupCallMember>[];
    final users = <String>{};
    for (final item in value['participants'] as List) {
      if (item is! Map) return null;
      final user = item['user']?.toString() ?? '';
      final session = item['sessionId']?.toString() ?? '';
      if (user.isEmpty || session.isEmpty || !users.add(user)) return null;
      members.add(
        GroupCallMember(
          user: user,
          sessionId: session,
          muted: item['muted'] == true,
          videoEnabled: item['videoEnabled'] != false,
          away: item['away'] == true,
          disconnected: item['disconnected'] == true,
          moderator: item['moderator'] == true,
          role: item['role']?.toString() ?? 'guest',
        ),
      );
    }
    if (members.where((member) => !member.isViewer).length > 4) return null;
    return GroupCallState(
      id: id,
      groupId: groupId,
      name: value['name']?.toString() ?? 'Группа',
      startedBy: startedBy,
      owner: owner,
      featuredUser: value['featuredUser']?.toString() ?? '',
      awaitingHost: value['awaitingHost'] == true,
      pinnedMessage: value['pinnedMessage'] is Map
          ? Map<String, dynamic>.from(value['pinnedMessage'] as Map)
          : null,
      hostGraceUntil: hostGraceUntil,
      members: List.unmodifiable(members),
    );
  }

  GroupCallMember? member(String user) {
    for (final member in members) {
      if (member.user == user) return member;
    }
    return null;
  }

  static bool makesOffer(String localSession, String remoteSession) =>
      localSession.compareTo(remoteSession) < 0;
}
