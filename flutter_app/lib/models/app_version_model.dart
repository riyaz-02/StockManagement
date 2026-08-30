class AppVersionConfig {
  final String latestVersion;
  final int latestVersionCode;
  final bool forceUpdate;
  final String downloadUrl;
  final String updateMessage;

  AppVersionConfig({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.updateMessage,
  });

  factory AppVersionConfig.fromJson(Map<String, dynamic> json) {
    return AppVersionConfig(
      latestVersion: json['latestVersion']?.toString() ?? '1.0.0',
      latestVersionCode: (json['latestVersionCode'] is int)
          ? json['latestVersionCode']
          : int.tryParse(json['latestVersionCode']?.toString() ?? '') ?? 1,
      forceUpdate: json['forceUpdate'] ?? false,
      downloadUrl:
          json['downloadUrl']?.toString() ?? 'https://lgp.skriyaz.com/app',
      updateMessage: json['updateMessage']?.toString() ??
          'A new version of the app is available.',
    );
  }
}
