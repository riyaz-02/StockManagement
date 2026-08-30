import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_version_model.dart';
import '../utils/app_colors.dart';

/// Shows the "update available" popup. When [config.forceUpdate] is true,
/// the dialog cannot be dismissed and only offers "Update Now".
Future<void> showUpdateDialog(BuildContext context, AppVersionConfig config) {
  return showDialog(
    context: context,
    barrierDismissible: !config.forceUpdate,
    builder: (context) => PopScope(
      canPop: !config.forceUpdate,
      child: AlertDialog(
        icon:
            const Icon(Icons.system_update, color: AppColors.primary, size: 36),
        title:
            Text(config.forceUpdate ? 'Update Required' : 'Update Available'),
        content: Text(
          config.updateMessage.isNotEmpty
              ? config.updateMessage
              : 'A new version (${config.latestVersion}) is available.',
        ),
        actions: [
          if (!config.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final uri = Uri.parse(config.downloadUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              // Non-forced updates let the user continue using the app while
              // the download happens in the browser; forced ones stay blocked
              // until they relaunch with an updated build.
              if (!config.forceUpdate && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    ),
  );
}
