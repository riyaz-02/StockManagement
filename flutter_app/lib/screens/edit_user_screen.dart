import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

/// Admin-only screen to edit another user's name, mobile, role, and photo.
/// Password changes go through a separate reset-password flow (no current
/// password needed, since the admin isn't the account owner).
class EditUserScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditUserScreen({super.key, required this.user});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

const _configurableRoles = ['manager', 'staff', 'viewer'];

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  late String _selectedRole;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;
  bool _isSaving = false;

  // Custom per-user permission overrides (only relevant for
  // manager/staff/viewer targets). null = "use role default".
  bool _permissionsExpanded = false;
  bool _isLoadingPermissions = true;
  bool _isSavingPermissions = false;
  List<Map<String, dynamic>> _permissionGroups = [];
  final Map<String, bool?> _overrides = {};

  bool get _isConfigurableRole => _configurableRoles.contains(_selectedRole);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] ?? '');
    _mobileController =
        TextEditingController(text: widget.user['mobile'] ?? '');
    _selectedRole = widget.user['role'] ?? 'staff';
    _uploadedImageUrl = widget.user['profileImage'];

    final existingOverrides =
        widget.user['permissionOverrides'] as Map<String, dynamic>?;
    if (existingOverrides != null) {
      existingOverrides.forEach((k, v) => _overrides[k] = v == true);
    }
    _loadPermissionDefinitions();
  }

  Future<void> _loadPermissionDefinitions() async {
    try {
      final response = await _apiService.getPermissionDefinitions();
      if (response['success'] == true) {
        _permissionGroups =
            List<Map<String, dynamic>>.from(response['data']['groups'] ?? []);
      }
    } catch (_) {
      // Non-fatal — the section just won't render if this fails.
    }
    if (mounted) setState(() => _isLoadingPermissions = false);
  }

  Future<void> _saveOverrides() async {
    setState(() => _isSavingPermissions = true);
    try {
      final response = await _apiService.updateUserPermissionOverrides(
        widget.user['_id'],
        _overrides,
      );

      if (!mounted) return;
      if (response['success'] == true) {
        showAppSnackBar(
          context,
          const SnackBar(
              content: Text('Custom permissions saved'),
              backgroundColor: Colors.green),
        );
      } else {
        showAppSnackBar(
          context,
          SnackBar(
              content: Text(response['message'] ?? 'Failed to save'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context,
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isSavingPermissions = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Widget _buildCustomPermissionsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _permissionsExpanded = !_permissionsExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _permissionsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Custom Permissions (overrides this user\'s role defaults)',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_permissionsExpanded) ...[
            const Divider(height: 1),
            if (_isLoadingPermissions)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  'Tap a box to cycle: dash = use ${_selectedRole[0].toUpperCase()}${_selectedRole.substring(1)} default, check = explicitly allowed, empty = explicitly denied.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
              ..._permissionGroups.map((group) => _buildPermissionGroup(group)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _isSavingPermissions ? null : _saveOverrides,
                    child: _isSavingPermissions
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Custom Permissions'),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionGroup(Map<String, dynamic> group) {
    final groupName = group['group'] as String? ?? '';
    final keys = List<Map<String, dynamic>>.from(group['keys'] ?? []);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              groupName,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600]),
            ),
          ),
          ...keys.map((k) {
            final key = k['key'] as String;
            final label = k['label'] as String? ?? key;
            return CheckboxListTile(
              dense: true,
              tristate: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontSize: 12.5)),
              value: _overrides[key],
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _overrides[key] = v),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _uploadProfileImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      final result = await _apiService.uploadImage(image, folder: 'users');

      if (mounted) {
        if (result['success'] == true) {
          setState(() => _uploadedImageUrl = result['data']['url']);
          showAppSnackBar(
            context,
            const SnackBar(content: Text('Image uploaded successfully')),
          );
        } else {
          showAppSnackBar(
            context,
            SnackBar(
              content: Text(result['message'] ?? 'Failed to upload image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isUploadingImage = false);
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final result = await _apiService.updateUser(widget.user['_id'], {
        'name': _nameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'role': _selectedRole,
        if (_uploadedImageUrl != null) 'profileImage': _uploadedImageUrl,
      });

      if (!mounted) return;
      if (result['success'] == true) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text('${_nameController.text} updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(result['message'] ?? 'Failed to update user'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _resetPassword() async {
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Reset password for ${widget.user['name'] ?? 'user'}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) {
                      return 'At least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) {
                    if (v != newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _apiService.resetPassword(
        widget.user['_id'],
        newPasswordController.text,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        showAppSnackBar(
          context,
          const SnackBar(
            content: Text('Password reset successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(result['message'] ?? 'Failed to reset password'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Edit User',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: ClipOval(
                      child: _uploadedImageUrl != null &&
                              _uploadedImageUrl!.isNotEmpty
                          ? Image.network(
                              _uploadedImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: Icon(Icons.person,
                                    size: 50, color: Colors.grey[400]),
                              ),
                            )
                          : Container(
                              color: AppColors.primary.withOpacity(0.1),
                              child: Icon(Icons.person,
                                  size: 50, color: AppColors.primary),
                            ),
                    ),
                  ),
                  if (_isUploadingImage)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black54,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingImage ? null : _uploadProfileImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: const Icon(Icons.person_outline),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mobile Number *',
                prefixIcon: const Icon(Icons.phone_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return 'Mobile number is required';
                if (v.trim().length < 10) return 'Enter a valid mobile number';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: InputDecoration(
                labelText: 'Role *',
                prefixIcon: const Icon(Icons.badge_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedRole = value);
              },
            ),
            const SizedBox(height: 16),
            if (_isConfigurableRole) _buildCustomPermissionsSection(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _resetPassword,
              icon: const Icon(Icons.lock_reset, color: Colors.red),
              label: const Text('Reset Password',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'SAVE CHANGES',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
