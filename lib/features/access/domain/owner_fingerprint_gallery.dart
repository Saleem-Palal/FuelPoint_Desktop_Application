import 'dart:convert';

/// Owner fingers stored in one app setting. A legacy row is a single
/// protected template. Newer rows are a JSON list of those templates.
class OwnerFingerprintGallery {
  OwnerFingerprintGallery._();

  static const int maxFingers = 10;

  static List<String> parse(String? stored) {
    final String raw = (stored ?? '').trim();
    if (raw.isEmpty) {
      return <String>[];
    }
    if (raw.startsWith('[')) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((Object? item) => '$item'.trim())
              .where((String item) => item.isNotEmpty)
              .take(maxFingers)
              .toList();
        }
      } catch (_) {
        return <String>[raw];
      }
    }
    return <String>[raw];
  }

  static String encode(List<String> protectedFmds) {
    final List<String> kept = protectedFmds
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .take(maxFingers)
        .toList();
    return jsonEncode(kept);
  }
}
