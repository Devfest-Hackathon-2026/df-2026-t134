/// Strict readers for contract JSON (camelCase keys, see docs/CONTRACTS.md).
///
/// Every reader throws [FormatException] instead of falling back to a default,
/// so malformed documents are noticed at the boundary.
library;

/// Same pattern and length as `Id` in api/app/schemas/common.py.
final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
const _idMaxLength = 64;

/// Checks that [json] is an object whose keys are all in [allowed]
/// (the contract rejects unknown fields).
Map<String, Object?> readObject(
  Object? json,
  String what, {
  required Set<String> allowed,
}) {
  if (json is! Map) {
    throw FormatException('$what must be a JSON object', json);
  }
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('$what has unknown fields: $unknown', json);
  }
  return json.cast<String, Object?>();
}

String readString(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$what.$key must be a non-empty string', json);
}

/// Missing and null both mean "not set" (the API omits `None` fields).
String? readOptionalString(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('$what.$key must be a string', json);
}

int readInt(
  Map<String, Object?> json,
  String key,
  String what, {
  required int min,
  int? max,
}) {
  final value = json[key];
  if (value is int && value >= min && (max == null || value <= max)) {
    return value;
  }
  final range = max == null ? '>= $min' : 'in $min..$max';
  throw FormatException('$what.$key must be an integer $range', json);
}

String readId(Map<String, Object?> json, String key, String what) {
  return _checkId(json[key], '$what.$key', json);
}

List<String> readIdList(
  Map<String, Object?> json,
  String key,
  String what, {
  required int minItems,
  int? maxItems,
}) {
  final value = json[key];
  if (value is! List ||
      value.length < minItems ||
      (maxItems != null && value.length > maxItems)) {
    throw FormatException(
      '$what.$key must be a list of $minItems..${maxItems ?? 'n'} ids',
      json,
    );
  }
  return List.unmodifiable([
    for (final (index, item) in value.indexed)
      _checkId(item, '$what.$key[$index]', json),
  ]);
}

DateTime readDateTime(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    throw FormatException('$what.$key must be an ISO 8601 date-time', json);
  }
  return parsed;
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A calendar date (`YYYY-MM-DD`) as a UTC midnight [DateTime].
DateTime? readOptionalDate(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  final parsed = value is String && _datePattern.hasMatch(value)
      ? DateTime.tryParse('${value}T00:00:00Z')
      : null;
  if (parsed == null) {
    throw FormatException('$what.$key must be a YYYY-MM-DD date', json);
  }
  return parsed;
}

/// Like [readString] but an empty string is allowed (e.g. `explanation`).
String readText(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('$what.$key must be a string', json);
}

bool readBool(Map<String, Object?> json, String key, String what) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$what.$key must be a boolean', json);
}

/// A list with [minItems]..[maxItems] entries; the caller parses each entry.
List<Object?> readList(
  Map<String, Object?> json,
  String key,
  String what, {
  required int minItems,
  int? maxItems,
}) {
  final value = json[key];
  if (value is! List ||
      value.length < minItems ||
      (maxItems != null && value.length > maxItems)) {
    throw FormatException(
      '$what.$key must be a list of $minItems..${maxItems ?? 'n'} items',
      json,
    );
  }
  return value;
}

List<int> readIntList(
  Map<String, Object?> json,
  String key,
  String what, {
  required int min,
  int? maxItems,
}) {
  final value = readList(json, key, what, minItems: 0, maxItems: maxItems);
  return List.unmodifiable([
    for (final item in value)
      if (item is int && item >= min)
        item
      else
        throw FormatException('$what.$key must hold integers >= $min', json),
  ]);
}

/// An object mapping ids to ids, such as `{"<blankId>": "<optionId>"}`.
Map<String, String> readIdMap(
  Map<String, Object?> json,
  String key,
  String what,
) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('$what.$key must be an object of ids', json);
  }
  return Map.unmodifiable({
    for (final MapEntry(key: entryKey, value: entryValue) in value.entries)
      _checkId(entryKey, '$what.$key key', json): _checkId(
        entryValue,
        '$what.$key[$entryKey]',
        json,
      ),
  });
}

/// Whether [value] is a contract id (kebab-case, at most 64 characters).
bool isContractId(String value) =>
    value.length <= _idMaxLength && _idPattern.hasMatch(value);

String _checkId(Object? value, String where, Object? source) {
  if (value is String && isContractId(value)) {
    return value;
  }
  throw FormatException('$where must be a kebab-case id', source);
}
