import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

/// Admin-only screen: lets an admin edit the default permission grid for
/// Manager, Staff, and Viewer roles. Admin/Owner aren't shown here — they
/// always have full access and can't be restricted.
class RolePermissionManagerScreen extends StatefulWidget {
  const RolePermissionManagerScreen({super.key});

  @override
  State<RolePermissionManagerScreen> createState() =>
      _RolePermissionManagerScreenState();
}

class _RolePermissionManagerScreenState
    extends State<RolePermissionManagerScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  List<Map<String, dynamic>> _groups = [];
  List<String> _configurableRoles = [];
  String _selectedRole = 'manager';

  // role -> {permissionKey -> bool}
  final Map<String, Map<String, bool>> _grids = {};

  static const _roleLabels = {
    'manager': 'Manager',
    'staff': 'Staff',
    'viewer': 'Viewer',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final defsResponse = await _apiService.getPermissionDefinitions();
      final gridsResponse = await _apiService.getRolePermissionGrids();

      if (defsResponse['success'] == true && gridsResponse['success'] == true) {
        _groups = List<Map<String, dynamic>>.from(
            defsResponse['data']['groups'] ?? []);
        _configurableRoles =
            List<String>.from(defsResponse['data']['configurableRoles'] ?? []);

        final rawGrids =
            Map<String, dynamic>.from(gridsResponse['data']['grids'] ?? {});
        _grids.clear();
        for (final role in _configurableRoles) {
          final rawGrid = Map<String, dynamic>.from(rawGrids[role] ?? {});
          _grids[role] = rawGrid.map((k, v) => MapEntry(k, v == true));
        }

        if (_configurableRoles.isNotEmpty &&
            !_configurableRoles.contains(_selectedRole)) {
          _selectedRole = _configurableRoles.first;
        }
      } else {
        _loadError = defsResponse['message'] ??
            gridsResponse['message'] ??
            'Failed to load';
      }
    } catch (e) {
      _loadError = 'Error: $e';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final grid = _grids[_selectedRole];
    if (grid == null) return;

    setState(() => _isSaving = true);
    try {
      final response =
          await _apiService.updateRolePermissionGrid(_selectedRole, grid);
      if (!mounted) return;
      if (response['success'] == true) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(
                'Permissions saved for ${_roleLabels[_selectedRole] ?? _selectedRole}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(response['message'] ?? 'Failed to save'),
            backgroundColor: Colors.red,
          ),
        );
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
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Roles & Permissions',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: _configurableRoles.map((role) {
                          final isSelected = role == _selectedRole;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_roleLabels[role] ?? role),
                              selected: isSelected,
                              onSelected: (_) =>
                                  setState(() => _selectedRole = role),
                              selectedColor:
                                  AppColors.primary.withOpacity(0.15),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.grey[700],
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _groups.length,
                        itemBuilder: (context, index) =>
                            _buildGroupCard(_groups[index]),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: SizedBox(
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
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Save ${_roleLabels[_selectedRole] ?? _selectedRole} Permissions'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final groupName = group['group'] as String? ?? '';
    final keys = List<Map<String, dynamic>>.from(group['keys'] ?? []);
    final grid = _grids[_selectedRole] ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              groupName,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A)),
            ),
          ),
          ...keys.map((k) {
            final key = k['key'] as String;
            final label = k['label'] as String? ?? key;
            final value = grid[key] ?? false;
            return CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(label, style: const TextStyle(fontSize: 13)),
              value: value,
              activeColor: AppColors.primary,
              onChanged: (v) {
                setState(() {
                  _grids[_selectedRole] = {...grid, key: v ?? false};
                });
              },
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
