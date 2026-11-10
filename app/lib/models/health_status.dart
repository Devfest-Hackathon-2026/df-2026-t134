/// Response of `GET /v1/health`.
class HealthStatus {
  const HealthStatus({required this.version, required this.env});

  final String version;
  final String env;

  factory HealthStatus.fromJson(Object? json) {
    if (json case {
      'status': 'ok',
      'version': final String version,
      'env': final String env,
    }) {
      return HealthStatus(version: version, env: env);
    }
    throw FormatException('Unexpected health response', json);
  }
}
