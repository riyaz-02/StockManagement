class AppVersionConfig {
  final String latestVersion;
  final int latestVersionCode;
  final bool forceUpdate;
  final String downloadUrl;
  final String updateMessage;

  /// Set when the update file is hosted by the shop's own server: the phone downloads it itself, checks it against
  /// [apkSha256] and installs it. Otherwise [downloadUrl] is just a link opened in the browser.
  final bool apkFromServer;
  final String apkSha256;
  final int apkSize;

  AppVersionConfig({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.updateMessage,
    this.apkFromServer = false,
    this.apkSha256 = '',
    this.apkSize = 0,
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
      apkFromServer: json['apkFromServer'] == true,
      apkSha256: json['apkSha256']?.toString() ?? '',
      apkSize: (json['apkSize'] is num) ? (json['apkSize'] as num).toInt() : 0,
    );
  }
}
