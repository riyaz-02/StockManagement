import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// A customer name field that SEARCHES the customer directory as you type (name, mobile digits or customer code),
/// and lets the user simply keep the typed name when nobody matches ("use as new customer").
///
///  - choosing a match fills the name, the mobile (when a mobile controller is given) and reports the customer id;
///  - typing anything else leaves the id empty: a walk-in / new customer by name.
///
/// [onChanged] is called with (customerId or '', name, mobile) on every change or pick.
class CustomerField extends StatefulWidget {
  const CustomerField({
    super.key,
    required this.name,
    this.mobile,
    required this.decoration,
    this.mobileDecoration,
    this.onChanged,
    this.label = 'Customer name',
    this.initialId = '',
    this.address,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController name;
  final TextEditingController? mobile;
  final InputDecoration Function(String label) decoration;
  final InputDecoration Function(String label)? mobileDecoration;
  final void Function(String id, String name, String mobile)? onChanged;
  final String label;
  final String initialId;
  final TextEditingController? address; // filled from the saved customer when one is picked
  final String? Function(String?)? validator;
  final bool enabled;

  @override
  State<CustomerField> createState() => _CustomerFieldState();
}

class _CustomerFieldState extends State<CustomerField> {
  final _api = ApiService();
  final _focus = FocusNode();
  Timer? _timer;
  int _seq = 0;
  List<Map<String, dynamic>> _results = [];
  String _id = '';
  bool _searched = false; // a search finished (so "no match" can be shown)
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _id = widget.initialId;
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) setState(() => _results = []);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged?.call(_id, widget.name.text.trim(), widget.mobile?.text.trim() ?? '');

  void _search(String v) {
    _id = ''; // typing again makes it a new / by-name customer until a match is picked
    _notify();
    _timer?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _timer = Timer(const Duration(milliseconds: 320), () async {
      final seq = ++_seq;
      setState(() => _busy = true);
      try {
        final res = await _api.lookupCustomers(q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _searched = true;
          _busy = false;
        });
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  void _pick(Map<String, dynamic> c) {
    widget.name.text = '${c['name'] ?? ''}';
    final phones = (c['phones'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    if (widget.mobile != null && phones.isNotEmpty) widget.mobile!.text = phones.first;
    if (widget.address != null && '${c['address'] ?? ''}'.isNotEmpty) widget.address!.text = '${c['address']}';
    _id = '${c['id'] ?? ''}';
    _focus.unfocus();
    setState(() {
      _results = [];
      _searched = false;
    });
    _notify();
  }

  void _keepTyped() {
    _focus.unfocus();
    setState(() {
      _results = [];
      _searched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.name.text.trim();
    final showList = _focus.hasFocus && typed.length >= 2 && (_results.isNotEmpty || _searched);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: widget.name,
        focusNode: _focus,
        enabled: widget.enabled,
        validator: widget.validator,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 13.5),
        onChanged: _search,
        decoration: widget.decoration(widget.label).copyWith(
              suffixIcon: _busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : (_id.isNotEmpty ? const Icon(Icons.check_circle, color: Colors.green, size: 20) : const Icon(Icons.search, size: 20)),
            ),
      ),
      if (_id.isNotEmpty) const Padding(padding: EdgeInsets.only(left: 6, top: 3), child: Text('Saved customer', style: TextStyle(fontSize: 11, color: Colors.green))),
      if (showList)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))]),
          child: Column(children: [
            for (final c in _results)
              InkWell(
                onTap: () => _pick(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    const Icon(Icons.person_outline, size: 18, color: Colors.black45),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c['name']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        Text([if ('${c['code'] ?? ''}'.isNotEmpty && c['code'] != null) '${c['code']}', if ((c['phones'] as List?)?.isNotEmpty ?? false) '${(c['phones'] as List).first}', if ('${c['address'] ?? ''}'.isNotEmpty) '${c['address']}'].join('  ·  '), style: const TextStyle(fontSize: 11, color: Colors.black54), overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              ),
            InkWell(
              onTap: _keepTyped,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.person_add_alt_1_outlined, size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_results.isEmpty ? 'No customer found: use "$typed" as a new customer' : 'Not in the list: use "$typed"', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)))),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
