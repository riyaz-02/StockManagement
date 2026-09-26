import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Dropdown of the shop branches. Used where an admin assigns a user to a
/// branch (Add / Edit user). Falls back to the built-in "Main branch" if the
/// list cannot be loaded, so the form always stays usable.
class BranchDropdown extends StatefulWidget {
  const BranchDropdown({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<BranchDropdown> createState() => _BranchDropdownState();
}

class _BranchDropdownState extends State<BranchDropdown> {
  List<Map<String, dynamic>> _branches = [
    {'_id': 'main', 'name': 'Main branch'}
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getDirectoryBranches();
      if (!mounted || res['success'] != true) return;
      setState(() => _branches = List<Map<String, dynamic>>.from(
          (res['data'] as List).map((e) => Map<String, dynamic>.from(e))));
    } catch (_) {/* keep the built-in Main branch */}
  }

  @override
  Widget build(BuildContext context) {
    final ids = _branches.map((b) => b['_id'].toString()).toList();
    final value = ids.contains(widget.value) ? widget.value : 'main';
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Branch / shop',
        prefixIcon: const Icon(Icons.storefront_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: [
        for (final b in _branches)
          DropdownMenuItem(
              value: b['_id'].toString(),
              child: Text(b['name'].toString(), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) widget.onChanged(v);
      },
    );
  }
}
