import 'dart:convert';

/// Developer payloads may contain chat facts, but never credentials or headers.
class DeveloperLogSanitizer {
  DeveloperLogSanitizer([Iterable<String> secrets = const []]) {
    for (final value in secrets) {
      protect(value);
    }
  }

  final _secrets = <String>{};
  static const _blocked = {
    'headers',
    'requestheaders',
    'responseheaders',
    'authorization',
    'proxyauthorization',
    'apikey',
    'xappkey',
    'xapikey',
    'xdeviceid',
    'cookie',
    'setcookie',
    'accesstoken',
    'refreshtoken',
    'token',
    'appkey',
    'password',
    'secret',
    'clientsecret',
  };
  static final _keyPunctuation = RegExp(r'[^a-z0-9]');
  static final _bearer = RegExp(
    r'''\bBearer\s+[^\s"'\\,;]+''',
    caseSensitive: false,
  );
  static final _labelledKey = RegExp(
    r'''\b(?:api[ _-]?key|x-app-key|x-api-key)\s*[:=]\s*["']?[^\s"'\\,;}]+''',
    caseSensitive: false,
  );
  static final _authorizationHeader = RegExp(
    r'''\b(?:proxy-)?authorization\s*[:=]\s*["']?(?:(?:Basic|Bearer)\s+)?[^\s"'\\,;}]+''',
    caseSensitive: false,
  );

  void protect(String value) {
    if (value.isEmpty) return;
    _secrets.add(value);
    for (final text in [value, 'SMARTFIT_AI_TOKEN=$value']) {
      _secrets.add(base64Encode(utf8.encode(text)));
      _secrets.add(base64Url.encode(utf8.encode(text)));
    }
  }

  Object? sanitize(Object? value) => _clean(value, 0, Set<Object>.identity());

  Object? _clean(Object? value, int depth, Set<Object> parents) {
    if (depth > 64) return '[depth_limit]';
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : null;
    if (value is String) return _text(value, depth, parents);
    if (parents.contains(value)) return '[cycle]';
    parents.add(value);
    try {
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            if (entry.key is String &&
                !_blocked.contains(
                  (entry.key as String).toLowerCase().replaceAll(
                    _keyPunctuation,
                    '',
                  ),
                ))
              _redact(entry.key as String): _clean(
                entry.value,
                depth + 1,
                parents,
              ),
        };
      }
      if (value is Iterable) {
        return [for (final item in value) _clean(item, depth + 1, parents)];
      }
      return '[unsupported]';
    } finally {
      parents.remove(value);
    }
  }

  String _text(String text, int depth, Set<Object> parents) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        final clean = _clean(decoded, depth + 1, parents);
        final encoded = jsonEncode(clean);
        try {
          if (encoded != jsonEncode(decoded)) return encoded;
        } on JsonUnsupportedObjectError {
          // JSON can decode an overflowing exponent to a non-finite double.
          return encoded;
        }
      } on FormatException {
        // Preserve non-JSON user text and still remove recognizable secrets.
      }
    }
    return _redact(text);
  }

  String _redact(String text) {
    final values = _secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in values) {
      text = text.replaceAll(secret, '[REDACTED]');
    }
    return text
        .replaceAll(_authorizationHeader, '[REDACTED_CREDENTIAL]')
        .replaceAll(_bearer, 'Bearer [REDACTED]')
        .replaceAll(_labelledKey, '[REDACTED_CREDENTIAL]');
  }
}
