class GroupCallMember {
  const GroupCallMember({
    required this.user,
    required this.sessionId,
    this.muted = false,
    this.videoEnabled = true,
    this.role = 'guest',
  });
  final String user;
  final String sessionId;
  final bool muted;
  final bool videoEnabled;
  final String role;
  bool get isHost => role == 'host';
  bool get isModerator => role == 'moderator';
}

class GroupCallState {
  const GroupCallState({
    required this.id,
    required this.groupId,
    required this.name,
    required this.startedBy,
    required this.members,
    this.limit = 4,
  });
  final String id;
  final String groupId;
  final String name;
  final String startedBy;
  final List<GroupCallMember> members;
  final int limit;

  static GroupCallState? parse(dynamic value) {
    if (value is! Map || value['participants'] is! List) return null;
    final id = value['id']?.toString() ?? '';
    final groupId = value['groupId']?.toString() ?? '';
    if (id.isEmpty || groupId.isEmpty) return null;
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
          role: item['role']?.toString() ?? 'guest',
        ),
      );
    }
    if (members.length > 4) return null;
    return GroupCallState(
      id: id,
      groupId: groupId,
      name: value['name']?.toString() ?? 'Группа',
      startedBy: value['startedBy']?.toString() ?? '',
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
