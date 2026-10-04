import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Dropdown of the billing counters of one branch (Add / Edit user: the counter a person normally works at). '' = none.
/// It follows [branchId]: choose another branch and the list changes. Only live (switched-on) counters are offered.
class CounterDropdown extends StatefulWidget {
  const CounterDropdown({super.key, required this.branchId, required this.value, required this.onChanged});

  final String branchId;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<CounterDropdown> createState() => _CounterDropdownState();
}

class _CounterDropdownState extends State<CounterDropdown> {
  Map<String, List<Map<String, dynamic>>> _byBranch = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getBranches();
      if (!mounted || res['success'] != true) return;
      final out = <String, List<Map<String, dynamic>>>{};
      for (final b in (res['data']?['branches'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(b as Map);
        out[m['id'].toString()] = (m['counters'] as List? ?? const []).map((c) => Map<String, dynamic>.from(c as Map)).where((c) => c['isActive'] != false).toList();
      }
      setState(() => _byBranch = out);
    } catch (_) {/* no counters offered: the form still works */}
  }

  @override
  Widget build(BuildContext context) {
    final counters = _byBranch[widget.branchId] ?? const <Map<String, dynamic>>[];
    final ids = counters.map((c) => c['id'].toString()).toList();
    final value = ids.contains(widget.value) ? widget.value : '';
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Billing counter',
        helperText: counters.isEmpty ? 'This branch has no counters yet (Settings > Branches & counters)' : null,
        prefixIcon: const Icon(Icons.point_of_sale_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('No counter')),
        for (final c in counters) DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString(), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: counters.isEmpty ? null : (v) => widget.onChanged(v ?? ''),
    );
  }
}
