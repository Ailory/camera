class GoogleAccountProfile {
  const GoogleAccountProfile({
    required this.name,
    required this.email,
    this.pictureUrl,
  });

  final String name;
  final String email;
  final String? pictureUrl;

  String get initials {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return 'G';
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    String firstCharacter(String value) =>
        String.fromCharCode(value.runes.first);
    if (parts.length == 1) return firstCharacter(parts.first).toUpperCase();
    return '${firstCharacter(parts.first)}${firstCharacter(parts.last)}'
        .toUpperCase();
  }
}
