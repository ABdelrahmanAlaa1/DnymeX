List<String> normalizeRepoList(Iterable<String> values) {
  final seen = <String>{};
  final sanitized = <String>[];

  for (final raw in values) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      sanitized.add(trimmed);
    }
  }

  return sanitized;
}

List<String> appendRepoEntry(List<String> current, String repo) {
  final sanitized = normalizeRepoList(current);
  final trimmed = repo.trim();
  if (trimmed.isEmpty) return sanitized;

  final key = trimmed.toLowerCase();
  final exists = sanitized.any((entry) => entry.toLowerCase() == key);
  if (!exists) {
    sanitized.add(trimmed);
  }

  return sanitized;
}
