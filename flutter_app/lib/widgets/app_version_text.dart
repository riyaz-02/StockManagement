import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// "Version 1.4.0": always the installed build's own version (pubspec), never a number typed into a screen.
class AppVersionText extends StatelessWidget {
  final TextStyle? style;
  const AppVersionText({super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snap) => Text(
        snap.hasData ? 'Version ${snap.data!.version}' : '',
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}
