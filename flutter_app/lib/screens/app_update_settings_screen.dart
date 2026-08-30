import 'package:flutter/material.dart';
import '../models/app_version_model.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

class AppUpdateSettingsScreen extends StatefulWidget {
  const AppUpdateSettingsScreen({super.key});

  @override
  State<AppUpdateSettingsScreen> createState() =>
      _AppUpdateSettingsScreenState();
}

class _AppUpdateSettingsScreenState extends State<AppUpdateSettingsScreen> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _versionCtrl = TextEditingController();
  final _versionCodeCtrl = TextEditingController();
  final _downloadUrlCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _forceUpdate = false;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _versionCtrl.dispose();
    _versionCodeCtrl.dispose();
    _downloadUrlCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getAppVersion();
      if (response['success'] == true) {
        final config =
            AppVersionConfig.fromJson(response['data']['appVersion']);
        _versionCtrl.text = config.latestVersion;
        _versionCodeCtrl.text = config.latestVersionCode.toString();
        _downloadUrlCtrl.text = config.downloadUrl;
        _messageCtrl.text = config.updateMessage;
        _forceUpdate = config.forceUpdate;
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
            context,
            SnackBar(
                content: Text('Failed to load: $e'),
                backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final response = await _apiService.updateAppVersion({
        'latestVersion': _versionCtrl.text.trim(),
        'latestVersionCode': int.parse(_versionCodeCtrl.text.trim()),
        'forceUpdate': _forceUpdate,
        'downloadUrl': _downloadUrlCtrl.text.trim(),
        'updateMessage': _messageCtrl.text.trim(),
      });

      if (!mounted) return;
      if (response['success'] == true) {
        showAppSnackBar(
            context,
            const SnackBar(
                content: Text('App version updated'),
                backgroundColor: Colors.green));
      } else {
        showAppSnackBar(
            context,
            SnackBar(
                content: Text(response['message'] ?? 'Failed to update'),
                backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context,
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('App Update Settings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'When the latest version code is higher than what a user has installed, they see an "Update available" popup pointing to the download URL below.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _versionCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Latest Version (e.g. 1.3.0)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _versionCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Latest Version Code (build number)',
                      helperText:
                          'Matches the "+N" in pubspec.yaml\'s version line',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (int.tryParse(v.trim()) == null)
                        return 'Must be a whole number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _downloadUrlCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Download URL'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Message shown to users'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Force update',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'Blocks app use until updated — use only for critical releases'),
                    value: _forceUpdate,
                    activeColor: Colors.red,
                    onChanged: (v) => setState(() => _forceUpdate = v),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
