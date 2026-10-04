import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/bilingual.dart';
import '../utils/directory_validators.dart';
import 'user_directory_screen.dart';

// ── Shared helpers ───────────────────────────────────────────────────────────

void _toast(BuildContext context, String msg, {bool error = false}) {
  showAppSnackBar(
    context,
    SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Sends a create (POST) or an edit (PUT, when [editPath] is set).
///
///  * A "this number/record already exists" answer (409) asks whether to go
///    ahead anyway.
///  * A "changed by someone else" answer (409 + conflict) stops the save, so
///    another person's edit is never silently overwritten.
///
/// Returns true when the record was saved.
/// What the server answered to the last successful save (the new record), for a caller that wants to use it (billing).
Map<String, dynamic>? _lastSentData;

Future<bool> _send(BuildContext context,
    {required String kind, String? editPath, required Map<String, dynamic> body}) async {
  final api = ApiService();
  Future<Map<String, dynamic>> go(Map<String, dynamic> b) => editPath != null
      ? api.updateDirectoryRecord(editPath, b)
      : api.createDirectoryRecord(kind, b);

  var res = await go(body);

  if (res['statusCode'] == 409 && res['conflict'] == true) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Changed by someone else', style: TextStyle(fontSize: 16)),
          content: Text(res['message'].toString(), style: const TextStyle(fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    return false;
  }

  if (res['statusCode'] == 409) {
    if (!context.mounted) return false;
    final go2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already exists', style: TextStyle(fontSize: 16)),
        content: Text(
            '${res['message']}\n\nDo you still want to ${editPath != null ? 'save this change' : 'add this as a new record'}?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(editPath != null ? 'Save anyway' : 'Add anyway')),
        ],
      ),
    );
    if (go2 != true) return false;
    res = await go({...body, 'force': true});
  }

  if (res['success'] == true) {
    _lastSentData = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
    return true;
  }
  if (context.mounted) {
    _toast(context, (res['message'] ?? 'Could not save').toString(), error: true);
  }
  return false;
}

String? _required(String? v, String label) =>
    (v == null || v.trim().isEmpty) ? '$label is required' : null;

/// Entering a GST number fills in what it already contains: the PAN (chars
/// 3-12) and the state (first two digits), so staff never type them twice.
void _gstAutofill(TextEditingController gst, TextEditingController pan, TextEditingController state) {
  final g = gst.text.trim().toUpperCase();
  if (DV.gst(g) != null) return;
  final derivedPan = g.substring(2, 12);
  if (pan.text.trim().isEmpty) pan.text = derivedPan;
  final st = DV.gstState[g.substring(0, 2)];
  if (st != null && state.text.trim().isEmpty) state.text = st;
}

DateTime? _dateOf(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
String _str(dynamic v) => (v ?? '').toString();

// ── Sizing: compact on phones, roomier (not more columns) on tablets ─────────
//
// Forms are always two columns inside a centred container. On a tablet the
// fields simply get bigger and more comfortable to hit, instead of packing in
// extra columns that would make the screen busy and hard to scan.

const _kGap = 8.0;
const _kFormMaxWidth = 860.0;

bool _roomy(BuildContext context) => MediaQuery.of(context).size.width >= 600;

TextStyle _fieldStyle(BuildContext context) =>
    TextStyle(fontSize: _roomy(context) ? 15 : 13.5);

/// The colour of the section a field sits in. Fields read it so focus rings,
/// floating labels and icons match their section without threading a colour
/// through every widget.
class _SectionAccent extends InheritedWidget {
  const _SectionAccent({required this.color, required super.child});
  final Color color;

  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SectionAccent>()?.color;

  @override
  bool updateShouldNotify(_SectionAccent old) => old.color != color;
}

/// One colour per kind of section, so the same section looks the same on every
/// form (Address is always orange, Bank always indigo, ...).
Color _sectionColor(String title, Color fallback) {
  switch (title) {
    case 'Contact numbers':
      return const Color(0xFF16A34A); // green
    case 'Referral':
      return const Color(0xFF9333EA); // purple
    case 'Address':
      return const Color(0xFFEA580C); // orange
    case 'Business & tax':
      return const Color(0xFF0D9488); // teal
    case 'Bank details':
    case 'Bank & previous job':
      return const Color(0xFF4F46E5); // indigo
    case 'Opening balance':
      return const Color(0xFFD97706); // amber
    case 'Education':
      return const Color(0xFFDB2777); // pink
    case 'Personal':
      return const Color(0xFF0284C7); // sky
    case 'Other':
      return const Color(0xFF64748B); // slate
    default:
      return fallback; // the main section keeps the record type's colour
  }
}

InputDecoration _dec(BuildContext context, String label, Color accentIn,
    {String? suffixText, Widget? suffixIcon}) {
  final accent = _SectionAccent.maybeOf(context) ?? accentIn;
  final roomy = _roomy(context);
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(roomy ? 10 : 8),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: roomy ? 13.5 : 12.5),
    floatingLabelStyle: TextStyle(fontSize: roomy ? 13 : 12, color: accent),
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    // Default suffix constraints are 48px tall, which made date fields taller
    // than their neighbours in the compact grid.
    suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
    counterText: '',
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding:
        EdgeInsets.symmetric(horizontal: roomy ? 14 : 10, vertical: roomy ? 14 : 10),
    border: b(Colors.black26),
    enabledBorder: b(Colors.black26),
    focusedBorder: b(accent, 1.6),
    errorBorder: b(Colors.red.shade600),
    focusedErrorBorder: b(Colors.red.shade600, 1.6),
    errorStyle: const TextStyle(fontSize: 10.5, height: 1),
  );
}

/// One cell in a [_Grid]; [span] is how many columns it occupies (use 99 for
/// a full-width row).
class _F {
  const _F(this.child, {this.span = 1});
  final Widget child;
  final int span;
}

/// Two-column grid that wraps. Field width follows the screen, so phones get
/// compact fields and tablets get large, easy-to-tap ones.
class _Grid extends StatelessWidget {
  const _Grid(this.cells);
  final List<_F> cells;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const cols = 2;
        final gap = _roomy(context) ? 12.0 : _kGap;
        double width(int span) {
          final s = span.clamp(1, cols);
          final cell = (c.maxWidth - gap * (cols - 1)) / cols;
          return cell * s + gap * (s - 1);
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap + 2,
          children: [
            for (final f in cells) SizedBox(width: width(f.span), child: f.child),
          ],
        );
      });
}

class _Tf extends StatelessWidget {
  const _Tf(this.label, this.ctrl, this.accent,
      {this.keyboard,
      this.validator,
      this.digits = false,
      this.maxLength,
      this.caps = false,
      this.lines = 1,
      this.phone = false,
      this.titleCase = false,
      this.suffix,
      this.onChanged});
  final String label;
  final TextEditingController ctrl;
  final Color accent;
  final bool phone; // cleans +91 / spaces, caps at 10 digits
  final bool titleCase; // "rahul DAS" -> "Rahul Das" when the field loses focus
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final bool digits;
  final int? maxLength;
  final bool caps;
  final int lines;

  @override
  Widget build(BuildContext context) {
    Widget field = TextFormField(
      controller: ctrl,
      style: _fieldStyle(context),
      keyboardType:
          phone ? TextInputType.phone : (keyboard ?? (lines > 1 ? TextInputType.multiline : null)),
      minLines: 1,
      maxLines: lines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
      inputFormatters: [
        if (phone) PhoneInputFormatter() else if (digits) FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: _dec(context, label, accent, suffixIcon: suffix),
    );
    if (titleCase) {
      field = Focus(
        onFocusChange: (has) {
          if (!has) {
            final t = DV.titleCase(ctrl.text);
            if (t != ctrl.text) {
              ctrl.text = t;
              onChanged?.call(t);
            }
          }
        },
        child: field,
      );
    }
    return field;
  }
}

class _Drop extends StatelessWidget {
  const _Drop(this.label, this.value, this.items, this.onChanged, this.accent);
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        isDense: true,
        style: _fieldStyle(context).copyWith(color: Colors.black87),
        decoration: _dec(context, label, accent),
        items: [
          for (final i in items)
            DropdownMenuItem(value: i, child: Text(i[0].toUpperCase() + i.substring(1))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
}

class _DateField extends StatelessWidget {
  const _DateField(this.label, this.value, this.onPick, this.accent, {this.showAge = false});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final Color accent;
  final bool showAge; // append "· 36 yrs" to the label

  @override
  Widget build(BuildContext context) {
    final age = (showAge && value != null) ? DV.ageOn(value!) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1940),
          lastDate: DateTime(2100),
        );
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: _dec(context, age == null ? label : '$label  ·  $age yrs', accent,
            suffixIcon: const Icon(Icons.calendar_today, size: 16)),
        child: Text(value == null ? 'Select' : DateFormat('dd MMM yyyy').format(value!),
            style: _fieldStyle(context)
                .copyWith(color: value == null ? Colors.black45 : Colors.black87)),
      ),
    );
  }
}

class _GenderBox extends StatelessWidget {
  const _GenderBox(this.value, this.onChanged, this.accentIn);
  final String value;
  final ValueChanged<String> onChanged;
  final Color accentIn;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionAccent.maybeOf(context) ?? accentIn;
    Widget opt(String v, String text, IconData icon) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged(v),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(value == v ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16, color: value == v ? accent : Colors.black45),
              const SizedBox(width: 3),
              Icon(icon, size: 15, color: value == v ? accent : Colors.black45),
              Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: value == v ? accent : Colors.black54)),
            ]),
          ),
        );
    return InputDecorator(
      decoration: _dec(context, 'Gender', accentIn),
      child: SizedBox(
        height: 20,
        child: Row(children: [
          opt('M', 'M', Icons.male),
          opt('F', 'F', Icons.female),
        ]),
      ),
    );
  }
}

/// Branch / shop picker for users who may file records under any branch.
class _BranchPicker extends StatefulWidget {
  const _BranchPicker({required this.accent, required this.value, required this.onChanged});
  final Color accent;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BranchPicker> createState() => _BranchPickerState();
}

class _BranchPickerState extends State<_BranchPicker> {
  static const _newBranch = '__new__';
  final _api = ApiService();
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
      final res = await _api.getDirectoryBranches();
      if (!mounted || res['success'] != true) return;
      setState(() => _branches = List<Map<String, dynamic>>.from(
          (res['data'] as List).map((e) => Map<String, dynamic>.from(e))));
    } catch (_) {/* keep the built-in Main branch */}
  }

  Future<void> _addBranch() async {
    final name = TextEditingController();
    final city = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New branch', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Branch / shop name *')),
          const SizedBox(height: 8),
          TextField(
              controller: city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'City')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final res = await _api.createDirectoryRecord(
          'branches', {'name': name.text.trim(), 'city': city.text.trim()});
      if (res['success'] == true) {
        await _load();
        widget.onChanged(res['data']['_id'].toString());
      } else if (mounted) {
        _toast(context, (res['message'] ?? 'Could not add branch').toString(), error: true);
      }
    } catch (e) {
      if (mounted) _toast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.read<AuthProvider>().can('directory.manageBranches');
    final ids = _branches.map((b) => b['_id'].toString()).toList();
    final value = ids.contains(widget.value) ? widget.value : 'main';
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      isDense: true,
      style: _fieldStyle(context).copyWith(color: Colors.black87),
      decoration: _dec(context, 'Branch / shop', widget.accent),
      items: [
        for (final b in _branches)
          DropdownMenuItem(
              value: b['_id'].toString(),
              child: Text(b['name'].toString(), overflow: TextOverflow.ellipsis)),
        if (canManage)
          DropdownMenuItem(
              value: _newBranch,
              child: Text('+ New branch…',
                  style: TextStyle(color: widget.accent, fontWeight: FontWeight.w600))),
      ],
      onChanged: (v) {
        if (v == null) return;
        if (v == _newBranch) {
          _addBranch();
        } else {
          widget.onChanged(v);
        }
      },
    );
  }
}

/// A modern section card: white body, a soft tinted header band with the
/// section icon in a rounded chip, and a coloured edge. Each kind of section
/// has its own colour (see [_sectionColor]) so long forms are easy to scan.
class _Section extends StatelessWidget {
  const _Section(this.title, this.icon, this.color, this.cells);
  final String title;
  final IconData icon;
  final Color color; // fallback for the main section
  final List<_F> cells;

  @override
  Widget build(BuildContext context) {
    final roomy = _roomy(context);
    final c = _sectionColor(title, color);
    final radius = BorderRadius.circular(roomy ? 16 : 14);
    return _SectionAccent(
      color: c,
      child: Padding(
        padding: EdgeInsets.only(bottom: roomy ? 14 : 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            border: Border.all(color: c.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(color: c.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // header band
                Container(
                  color: c.withOpacity(0.09),
                  padding: EdgeInsets.symmetric(horizontal: roomy ? 14 : 12, vertical: roomy ? 10 : 8),
                  child: Row(children: [
                    Container(
                      width: roomy ? 30 : 26,
                      height: roomy ? 30 : 26,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: roomy ? 17 : 15, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(title,
                        style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w800,
                            fontSize: roomy ? 15 : 13.5,
                            letterSpacing: 0.2)),
                  ]),
                ),
                Container(height: 2.5, color: c),
                Padding(
                  padding: EdgeInsets.fromLTRB(roomy ? 14 : 10, roomy ? 14 : 12, roomy ? 14 : 10, roomy ? 16 : 12),
                  child: _Grid(cells),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Common page chrome: title beside the back arrow, centred scrolling form
/// (max width so tablets do not stretch fields), and a pinned Cancel / Save bar.
class _FormPage extends StatelessWidget {
  const _FormPage(
      {required this.title,
      required this.formKey,
      required this.children,
      required this.saving,
      required this.onSave,
      required this.color});
  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final roomy = _roomy(context);
    final btnHeight = roomy ? 48.0 : 42.0;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: roomy ? 52 : 46,
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: roomy ? 18 : 16)),
      ),
      body: Form(
        key: formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(roomy ? 16 : 10, 2, roomy ? 16 : 10, 16),
              children: children,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(roomy ? 16 : 10, 6, roomy ? 16 : 10, 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(btnHeight),
                        foregroundColor: color,
                        side: BorderSide(color: color),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(btnHeight),
                        backgroundColor: color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(saving ? 'Saving…' : 'Save',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Save / branch / auto-fill plumbing shared by every form.
///
/// A form is in EDIT mode when its widget was given an `existing` record: the
/// fields start pre-filled, and Save sends a guarded update (with the
/// `updated_at` that was loaded, so a concurrent change by someone else is
/// caught rather than overwritten).
mixin _FormMixin<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool saving = false;

  TextEditingController c(String k);
  Map<String, dynamic>? get existing;
  bool get isEdit => existing != null;

  // ── branch ────────────────────────────────────────────────────────────────
  // Comes from the signed-in user automatically. Only users allowed to manage
  // branches can file a record under a different one.
  String? _branchOverride;
  Map<String, dynamic> get _rec {
    final e = existing;
    if (e == null) return const {};
    return (e['profile'] is Map) ? Map<String, dynamic>.from(e['profile']) : e;
  }

  String get branchId =>
      _branchOverride ??
      (isEdit && _str(_rec['branchId']).isNotEmpty
          ? _str(_rec['branchId'])
          : (isEdit ? 'main' : (context.read<AuthProvider>().user?.branchId ?? 'main')));
  void setBranch(String v) => setState(() => _branchOverride = v);

  Widget branchField(Color accent) {
    final auth = context.read<AuthProvider>();
    if (auth.can('directory.manageBranches')) {
      return _BranchPicker(accent: accent, value: branchId, onChanged: setBranch);
    }
    final name = isEdit
        ? (_str(_rec['branchName']).isNotEmpty ? _str(_rec['branchName']) : 'Main branch')
        : (auth.user?.branchName ?? 'Main branch');
    return InputDecorator(
      decoration: _dec(context, 'Branch / shop', accent,
          suffixIcon: const Icon(Icons.lock_outline, size: 15)),
      child: Text(name, style: _fieldStyle(context)),
    );
  }

  // ── auto-fill ─────────────────────────────────────────────────────────────
  final Map<String, String> _lastAuto = {};

  /// Puts [value] in field [key] only if the user has not typed their own
  /// there: it is empty, or still holds the last auto-filled value.
  void fillIfFree(String key, String? value) {
    if (value == null || value.trim().isEmpty) return;
    final ctrl = c(key);
    if (ctrl.text.trim().isEmpty || ctrl.text == _lastAuto[key]) {
      ctrl.text = value;
      _lastAuto[key] = value;
    }
  }

  /// 6-digit pincode -> city + state.
  Future<void> pincodeAutofill(String pin) async {
    if (pin.length != 6) return;
    try {
      final res = await ApiService().lookupPincode(pin);
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res['data']);
      fillIfFree('city', _str(d['city']));
      fillIfFree('state', _str(d['state']));
    } catch (_) {/* not found / offline: leave the fields manual */}
  }

  /// IFSC -> bank name (and a sensible account-holder name).
  Future<void> ifscAutofill(String code, {String? holderDefault}) async {
    if (DV.ifsc(code) != null || code.trim().length != 11) return;
    try {
      final res = await ApiService().lookupIfsc(code.trim().toUpperCase());
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res['data']);
      fillIfFree('bankName', _str(d['bank']));
      if (holderDefault != null && holderDefault.trim().isNotEmpty) {
        fillIfFree('bankAcName', holderDefault.trim());
      }
    } catch (_) {}
  }

  /// New records start with the branch's own city / state.
  Future<void> loadBranchDefaults() async {
    if (isEdit) return;
    try {
      final res = await ApiService().getDirectoryBranches();
      if (!mounted || res['success'] != true) return;
      for (final raw in (res['data'] as List)) {
        final b = Map<String, dynamic>.from(raw);
        if (b['_id'].toString() == branchId) {
          fillIfFree('city', _str(b['city']));
          fillIfFree('state', _str(b['state']));
        }
      }
    } catch (_) {}
  }

  // ── save ──────────────────────────────────────────────────────────────────
  /// Validates, runs [build] to get the payload, sends it (create or guarded
  /// edit) and pops with `true` on success.
  Future<void> save(String kind, Map<String, dynamic> Function() build,
      {String? editPath, dynamic updatedAt}) async {
    if (!formKey.currentState!.validate()) {
      _toast(context, 'Please fix the highlighted fields', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      final ok = await _send(context,
          kind: kind,
          editPath: isEdit ? editPath : null,
          body: {
            ...build(),
            if (_branchOverride != null) 'branchId': _branchOverride, // else the server uses the login's branch
            if (isEdit && updatedAt != null) 'expectedUpdatedAt': updatedAt.toString(),
          });
      if (ok && mounted) {
        _toast(context, isEdit ? 'Changes saved' : 'Saved');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _toast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

/// Compound inputs (amount · unit · credit/debit) on one row.
class _InlineRow extends StatelessWidget {
  const _InlineRow(this.items);
  final List<(int, Widget)> items;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: _kGap),
            Expanded(flex: items[i].$1, child: items[i].$2),
          ],
        ],
      );
}

/// Opening-balance inputs shared by the customer and supplier/karigar forms.
mixin _OpeningMixin<T extends StatefulWidget> on State<T> {
  TextEditingController c(String k);

  DateTime openingDate = DateTime.now();
  final Map<String, String> crdr = {'cash': 'credit', 'gold': 'credit', 'silver': 'credit'};
  final Map<String, String> unit = {'gold': 'gram', 'silver': 'gram'};

  /// Pre-fill from a saved `opening` object (edit mode).
  void loadOpening(dynamic op) {
    if (op is! Map) return;
    openingDate = _dateOf(op['date']) ?? openingDate;
    String numStr(dynamic v) => (v is num && v != 0) ? '$v' : '';
    final cash = op['cash'];
    if (cash is Map) {
      c('cash').text = numStr(cash['amount']);
      crdr['cash'] = _str(cash['type']).isEmpty ? 'credit' : _str(cash['type']);
    }
    for (final m in ['gold', 'silver']) {
      final v = op[m];
      if (v is Map) {
        c('${m}Wt').text = numStr(v['weight']);
        unit[m] = _str(v['unit']).isEmpty ? 'gram' : _str(v['unit']);
        crdr[m] = _str(v['type']).isEmpty ? 'credit' : _str(v['type']);
      }
    }
  }

  Widget _cash(Color color) => _InlineRow([
        (3, _Tf('Cash (₹)', c('cash'), color,
            keyboard: const TextInputType.numberWithOptions(decimal: true))),
        (2, _Drop('Cr / Dr', crdr['cash']!, const ['credit', 'debit'],
            (v) => setState(() => crdr['cash'] = v), color)),
      ]);

  Widget _metal(String key, String label, Color color) => _InlineRow([
        (3, _Tf(label, c('${key}Wt'), color,
            keyboard: const TextInputType.numberWithOptions(decimal: true))),
        (2, _Drop('Unit', unit[key]!, const ['gram', 'kg'],
            (v) => setState(() => unit[key] = v), color)),
        (2, _Drop('Cr / Dr', crdr[key]!, const ['credit', 'debit'],
            (v) => setState(() => crdr[key] = v), color)),
      ]);

  Widget openingSection(Color k) => _Section('Opening balance', Icons.balance_outlined, k, [
        _F(_DateField('As on date', openingDate, (d) => setState(() => openingDate = d), k)),
        _F(_cash(k), span: 2),
        _F(_metal('gold', 'Gold weight', k), span: 2),
        _F(_metal('silver', 'Silver weight', k), span: 2),
      ]);

  Map<String, dynamic> openingJson() {
    String t(String k) => c(k).text.trim();
    Map<String, dynamic> weight(String k) =>
        {'weight': double.tryParse(t('${k}Wt')) ?? 0, 'unit': unit[k], 'type': crdr[k]};
    return {
      'date': openingDate.toIso8601String(),
      'cash': {'amount': double.tryParse(t('cash')) ?? 0, 'type': crdr['cash']},
      'gold': weight('gold'),
      'silver': weight('silver'),
    };
  }
}

// ── Add / edit customer ──────────────────────────────────────────────────────

class _ContactRow {
  _ContactRow(this.label, [String text = '']) : ctrl = TextEditingController(text: text);
  String label; // whatsapp | mobile | home | work | other
  final TextEditingController ctrl;
}

/// One "special date" of a customer (the website's Important Dates): an occasion and a day.
class _DateRow {
  _DateRow(String occasion, [this.date]) : ctrl = TextEditingController(text: occasion);
  final TextEditingController ctrl;
  DateTime? date;
}

/// A day from the server's ISO date, kept as that calendar day (no time-zone shift).
DateTime? _dayOf(dynamic v) {
  final t = _str(v);
  if (t.length < 10) return null;
  final d = DateTime.tryParse(t.substring(0, 10));
  return d;
}

const _occasions = ['Birthday', 'Marriage Anniversary', 'Engagement', 'Work Anniversary', 'Other'];

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key, this.existing, this.prefillName = '', this.prefillNumber = ''});

  /// A customer just added from this form (after it popped `true`): the record the server saved, else null.
  static Map<String, dynamic>? get lastCreated => _lastSentData;

  /// What the person already typed elsewhere (billing's search box): put in the name / first number.
  final String prefillName, prefillNumber;

  /// The saved record (legacy fields + `profile`) when editing.
  final Map<String, dynamic>? existing;

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen>
    with _FormMixin<AddCustomerScreen>, _OpeningMixin<AddCustomerScreen> {
  static const _memberships = ['Regular', 'VIP'];
  static const _types = ['Retail', 'Wholesale', 'Corporate', 'Other'];
  static const _genders = ['Not set', 'Male', 'Female', 'Other'];
  static const _maxNumbers = 6;

  final _api = ApiService();
  final _c = <String, TextEditingController>{};
  @override
  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);
  @override
  Map<String, dynamic>? get existing => widget.existing;

  final List<_ContactRow> _rows = [_ContactRow('whatsapp')];
  String _membership = 'Regular';
  String _type = 'Retail';
  String _gender = 'Male';
  bool _genderTouched = false;
  final List<_DateRow> _dates = [];
  String _notify = 'all'; // all | offers | invitations | none (the website's four choices)
  bool _more = false; // the less used details are folded away when adding

  // Live duplicate detection while a number is typed
  Timer? _lookupTimer;
  int _lookupSeq = 0;
  List<Map<String, dynamic>> _matches = [];

  // "Referred by" picker
  Map<String, dynamic>? _referrer;
  Timer? _refTimer;
  int _refSeq = 0;
  List<Map<String, dynamic>> _refResults = [];

  // Bengali auto-fill (name / nickname / address)
  Timer? _translateTimer;

  @override
  void initState() {
    super.initState();
    c('country').text = 'India';
    if (isEdit) {
      _more = true;
      _prefill(widget.existing!);
    } else {
      loadBranchDefaults();
      if (widget.prefillName.trim().isNotEmpty) {
        c('name').text = widget.prefillName.trim();
        _scheduleTranslate();
      }
      if (DV.normalizePhone(widget.prefillNumber).length >= 5) {
        _rows.first.ctrl.text = DV.normalizePhone(widget.prefillNumber);
        _onNumberChanged(_rows.first);
      }
    }
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _refTimer?.cancel();
    _translateTimer?.cancel();
    for (final x in _dates) {
      x.ctrl.dispose();
    }
    for (final x in _c.values) {
      x.dispose();
    }
    for (final r in _rows) {
      r.ctrl.dispose();
    }
    super.dispose();
  }

  String get _lang => context.read<LanguageProvider>().currentLanguage;

  List<Map<String, dynamic>> _asList(dynamic v) =>
      List<Map<String, dynamic>>.from((v as List).map((e) => Map<String, dynamic>.from(e)));

  // ── edit mode: fill the form from the saved record ────────────────────────
  void _prefill(Map<String, dynamic> d) {
    final p = d['profile'] is Map ? Map<String, dynamic>.from(d['profile']) : <String, dynamic>{};
    c('name').text = _str(d['customer_name']);
    c('bengali').text = _str(d['customer_name_bengali']);
    c('nickname').text = _str(d['nickname']);
    c('nicknameBn').text = _str(p['nicknameBn']);
    // The saved Bengali text counts as "not hand-edited yet": if the English
    // name/nickname/address changes and the user never touched the Bengali
    // field, the Bengali follows. Once they type in it themselves it is left alone.
    _lastAuto['bengali'] = c('bengali').text;
    _lastAuto['nicknameBn'] = c('nicknameBn').text;
    c('email').text = _str(d['email']);
    c('address').text = _str(d['address']);
    c('addressBn').text = _str(p['addressBn']);
    _lastAuto['addressBn'] = c('addressBn').text;
    c('father').text = _str(p['fatherName']);
    c('city').text = _str(p['city']);
    c('state').text = _str(p['state']);
    c('country').text = _str(p['country']).isEmpty ? 'India' : _str(p['country']);
    c('pincode').text = _str(p['pincode']);
    c('business').text = _str(p['businessName']);
    c('gst').text = _str(p['gstNo']);
    c('pan').text = _str(p['panNo']);
    c('aadhar').text = _str(p['aadharNo']);
    c('tax').text = _str(p['taxNo']);
    c('notes').text = _str(p['notes']);
    _membership = _memberships.contains(p['membershipStatus']) ? p['membershipStatus'] : 'Regular';
    _type = _types.contains(p['customerType']) ? p['customerType'] : 'Retail';
    _gender = _genders.contains(p['gender']) && _str(p['gender']).isNotEmpty ? p['gender'] : 'Not set';
    _genderTouched = true;
    // the special dates the website keeps in `anniversaries`; a birth date / anniversary kept only in the app profile joins them
    _dates.clear();
    for (final a in (d['anniversaries'] is List ? d['anniversaries'] as List : const [])) {
      _dates.add(_DateRow(_str((a as Map)['occasion']), _dayOf(a['date'])));
    }
    bool has(RegExp re) => _dates.any((x) => re.hasMatch(x.ctrl.text));
    if (_dayOf(p['dob']) != null && !has(RegExp('birth', caseSensitive: false))) _dates.add(_DateRow('Birthday', _dayOf(p['dob'])));
    if (_dayOf(p['anniversary']) != null && !has(RegExp('^(?!.*(work|job|business)).*(marriage|wedding|anniversary)', caseSensitive: false))) {
      _dates.add(_DateRow('Marriage Anniversary', _dayOf(p['anniversary'])));
    }
    _notify = const ['all', 'offers', 'invitations', 'none'].contains(_str(d['notification_type'])) ? _str(d['notification_type']) : 'all';
    loadOpening(p['opening']);

    // phone numbers: the app profile has the full list; older customers only
    // have the four legacy slots
    _rows.clear();
    final contacts = (p['contacts'] is List && (p['contacts'] as List).isNotEmpty)
        ? (p['contacts'] as List).map((e) => (Map<String, dynamic>.from(e))).toList()
        : [
            for (final k in ['whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4'])
              if (_str(d[k]).isNotEmpty)
                {'number': _str(d[k]), 'label': k == 'whatsapp_no' ? 'whatsapp' : 'mobile'}
          ];
    for (var i = 0; i < contacts.length; i++) {
      _rows.add(_ContactRow(i == 0 ? 'whatsapp' : _str(contacts[i]['label']), _str(contacts[i]['number'])));
    }
    if (_rows.isEmpty) _rows.add(_ContactRow('whatsapp'));

    final ref = p['referredBy'];
    if (ref is Map) {
      if (ref['customerId'] != null) {
        _referrer = {
          'id': _str(ref['customerId']),
          'name': _str(ref['name']),
          'nameBn': '',
          'code': ref['code'],
          'phones': [if (_str(ref['mobile']).isNotEmpty) _str(ref['mobile'])],
        };
      } else {
        c('referral').text = _str(ref['text']);
      }
    }
  }

  // ── Bengali auto-fill ─────────────────────────────────────────────────────
  // Same idea as the LGPAdmin website: type the English name / nickname /
  // address and the Bengali one fills itself. Unlike the website it waits for a
  // pause in typing, and never overwrites something the user typed themselves.
  void _scheduleTranslate() {
    _translateTimer?.cancel();
    _translateTimer = Timer(const Duration(milliseconds: 700), () => _translateNow());
  }

  Future<void> _translateNow({bool force = false, List<String> only = const []}) async {
    final want = <String, String>{};
    void add(String apiKey, String en, String bnKey) {
      if (only.isNotEmpty && !only.contains(apiKey)) return;
      final text = c(en).text.trim();
      if (text.isEmpty) return;
      final bn = c(bnKey);
      if (force || bn.text.trim().isEmpty || bn.text == _lastAuto[bnKey]) want[apiKey] = text;
    }

    add('name', 'name', 'bengali');
    add('nickname', 'nickname', 'nicknameBn');
    add('address', 'address', 'addressBn');
    if (want.isEmpty) return;
    try {
      final res = await _api.translateToBengali(want);
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res['data'] ?? {});
      void put(String apiKey, String bnKey) {
        final v = _str(d[apiKey]);
        if (v.isEmpty) return;
        final ctrl = c(bnKey);
        if (force || ctrl.text.trim().isEmpty || ctrl.text == _lastAuto[bnKey]) {
          ctrl.text = v;
          _lastAuto[bnKey] = v;
        }
      }

      put('name', 'bengali');
      put('nickname', 'nicknameBn');
      put('address', 'addressBn');
    } catch (_) {/* offline / service down: the Bengali fields simply stay manual */}
  }

  Widget _retranslateButton(String apiKey) => IconButton(
        tooltip: 'Translate again',
        visualDensity: VisualDensity.compact,
        iconSize: 17,
        icon: const Icon(Icons.translate),
        onPressed: () => _translateNow(force: true, only: [apiKey]),
      );

  // ── live duplicate search ─────────────────────────────────────────────────
  void _onNumberChanged(_ContactRow row) {
    _lookupTimer?.cancel();
    final d = DV.normalizePhone(row.ctrl.text);
    if (d.length < 5) {
      if (_matches.isNotEmpty) setState(() => _matches = []);
      return;
    }
    _lookupTimer = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_lookupSeq;
      try {
        final res = await _api.lookupCustomers(d, exclude: isEdit ? _str(widget.existing!['_id']) : null);
        if (!mounted || seq != _lookupSeq) return;
        setState(() => _matches = _asList(res['data']));
      } catch (_) {/* offline: the server still checks on save */}
    });
  }

  Widget _matchPanel() {
    if (_matches.isEmpty) return const SizedBox.shrink();
    final exact = _matches.where((m) => m['exact'] == true).toList();
    final isDupe = exact.isNotEmpty;
    final color = isDupe ? Colors.red.shade700 : Colors.orange.shade800;
    final shown = (isDupe ? exact : _matches).take(3);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isDupe ? Icons.warning_amber_rounded : Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isDupe ? 'This number is already saved' : 'Similar numbers already saved',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ]),
        for (final m in shown)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 22),
            child: Text(
              [
                bilingualName(_str(m['name']), _str(m['nameBn']), _lang),
                if (m['code'] != null) m['code'],
                (m['matchedNumber'] ?? (m['phones'] as List).firstOrNull ?? '').toString(),
                if (m['branch'] != null) m['branch'],
              ].where((e) => e.toString().isNotEmpty).join('  ·  '),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
      ]),
    );
  }

  // ── contact numbers ───────────────────────────────────────────────────────
  String? _numberError(int i, String? v) {
    final label = _rows[i].label;
    final mobileLike = label == 'whatsapp' || label == 'mobile';
    final err = i == 0
        ? DV.mobile(v)
        : (mobileLike ? DV.mobile(v, required: false) : DV.phone10(v));
    if (err != null) return err;
    final d = DV.normalizePhone(v);
    if (d.isNotEmpty) {
      for (var j = 0; j < i; j++) {
        if (DV.normalizePhone(_rows[j].ctrl.text) == d) return 'Already entered above';
      }
    }
    return null;
  }

  Widget _contactRow(int i, Color k) {
    final row = _rows[i];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 116,
        child: i == 0
            ? InputDecorator(
                decoration: _dec(context, 'Type', k),
                child: Text('WhatsApp', style: _fieldStyle(context)),
              )
            : _Drop('Type', row.label, const ['mobile', 'home', 'work', 'other'],
                (v) => setState(() => row.label = v), k),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _Tf(i == 0 ? 'WhatsApp no. *' : 'Phone number', row.ctrl, k,
            phone: true,
            validator: (v) => _numberError(i, v),
            onChanged: (_) => _onNumberChanged(row)),
      ),
      if (i > 0)
        IconButton(
          tooltip: 'Remove number',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _rows.removeAt(i).ctrl.dispose()),
        )
      else
        const SizedBox(width: 8),
    ]);
  }

  Widget _contactsBlock(Color k) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _rows.length; i++)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _contactRow(i, k)),
          _matchPanel(),
          if (_rows.length < _maxNumbers)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _sectionColor('Contact numbers', k)),
                onPressed: () => setState(() => _rows.add(_ContactRow('mobile'))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add another number'),
              ),
            ),
        ],
      );

  // Special dates: birthday, marriage anniversary, engagement ... as many as needed (the website's Important Dates).
  Widget _dateRow(int i, Color k) {
    final r = _dates[i];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 5,
        child: _Tf('Occasion', r.ctrl, k,
            titleCase: true,
            suffix: PopupMenuButton<String>(
              tooltip: 'Pick an occasion',
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (v) => setState(() => r.ctrl.text = v == 'Other' ? '' : v),
              itemBuilder: (_) => [for (final o in _occasions) PopupMenuItem(value: o, child: Text(o))],
            )),
      ),
      const SizedBox(width: 8),
      Expanded(flex: 5, child: _DateField('Date', r.date, (d) => setState(() => r.date = d), k)),
      IconButton(
        tooltip: 'Remove',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => setState(() => _dates.removeAt(i).ctrl.dispose()),
      ),
    ]);
  }

  Widget _datesBlock(Color k) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < _dates.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: _dateRow(i, k)),
        if (_dates.length < 12)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _sectionColor('Customer', k)),
              onPressed: () => setState(() => _dates.add(_DateRow(_dates.isEmpty ? 'Birthday' : ''))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a special date (birthday, anniversary ...)'),
            ),
          ),
      ]);

  // ── referred by ───────────────────────────────────────────────────────────
  void _onReferralChanged(String v) {
    _refTimer?.cancel();
    final q = v.trim();
    if (q.length < 2 && DV.digits(q).length < 4) {
      if (_refResults.isNotEmpty) setState(() => _refResults = []);
      return;
    }
    _refTimer = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_refSeq;
      try {
        final res = await _api.lookupCustomers(q, exclude: isEdit ? _str(widget.existing!['_id']) : null);
        if (!mounted || seq != _refSeq) return;
        setState(() => _refResults = _asList(res['data']));
      } catch (_) {}
    });
  }

  Widget _referralBlock(Color k) {
    final r = _referrer;
    if (r != null) {
      return InputDecorator(
        decoration: _dec(context, 'Referred by', k),
        child: Row(children: [
          Icon(Icons.verified_user_outlined, size: 18, color: k),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(bilingualName(_str(r['name']), _str(r['nameBn']), _lang),
                  style: _fieldStyle(context).copyWith(fontWeight: FontWeight.w600)),
              Text(
                [if (r['code'] != null) r['code'], (r['phones'] as List).firstOrNull ?? '']
                    .where((e) => e.toString().isNotEmpty)
                    .join('  ·  '),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _referrer = null),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Tf('Referred by  (type name, mobile or customer ID)', c('referral'), k,
          onChanged: _onReferralChanged),
      for (final m in _refResults.take(4))
        InkWell(
          onTap: () => setState(() {
            _referrer = m;
            _refResults = [];
            c('referral').clear();
          }),
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.person_search_outlined, size: 18, color: k),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    bilingualName(_str(m['name']), _str(m['nameBn']), _lang),
                    if (m['code'] != null) m['code'],
                    (m['phones'] as List).firstOrNull ?? '',
                  ].where((e) => e.toString().isNotEmpty).join('  ·  '),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Map<String, dynamic> _build() {
    String t(String k) => c(k).text.trim();
    return {
      'name': t('name'),
      'nameBengali': t('bengali'),
      'nickname': t('nickname'),
      'nicknameBengali': t('nicknameBn'),
      'contacts': [
        for (final r in _rows)
          if (DV.normalizePhone(r.ctrl.text).isNotEmpty)
            {'number': DV.normalizePhone(r.ctrl.text), 'label': r.label},
      ],
      'email': t('email'),
      'address': t('address'),
      'addressBengali': t('addressBn'),
      'membershipStatus': _membership,
      'customerType': _type,
      'fatherName': t('father'),
      'gender': _gender == 'Not set' ? '' : _gender,
      'importantDates': [
        for (final x in _dates)
          if (x.ctrl.text.trim().isNotEmpty || x.date != null)
            {'occasion': x.ctrl.text.trim(), 'date': x.date == null ? '' : DateFormat('yyyy-MM-dd').format(x.date!)},
      ],
      'city': t('city'),
      'state': t('state'),
      'country': t('country'),
      'pincode': t('pincode'),
      if (_referrer != null) 'referredById': _referrer!['id'] else 'referredByText': t('referral'),
      'businessName': t('business'),
      'gstNo': t('gst'),
      'panNo': t('pan'),
      'aadharNo': t('aadhar'),
      'taxNo': t('tax'),
      'notes': t('notes'),
      'notificationType': _notify,
      'opening': openingJson(),
    };
  }

  // What the customer wants to hear about: the website's four choices.
  Widget _notifyChips(Color k) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('Messages', style: TextStyle(fontSize: 12.5, color: Colors.black54))),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final o in const [['all', 'All'], ['offers', 'Offers'], ['invitations', 'Invitations'], ['none', 'None']])
            ChoiceChip(
              label: Text(o[1]),
              selected: _notify == o[0],
              selectedColor: k.withOpacity(0.15),
              labelStyle: TextStyle(fontWeight: _notify == o[0] ? FontWeight.w700 : FontWeight.w500, color: _notify == o[0] ? k : Colors.black87),
              onSelected: (_) => setState(() => _notify = o[0]),
            ),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final k = DirectoryKind.customers.color;
    final genders = isEdit ? _genders : const ['Male', 'Female', 'Other'];
    return _FormPage(
      title: isEdit ? 'Edit Customer' : 'Add Customer',
      formKey: formKey,
      saving: saving,
      color: k,
      onSave: () => save('customers', _build,
          editPath: isEdit ? 'customers/${widget.existing!['_id']}' : null,
          updatedAt: widget.existing?['updated_at']),
      children: [
        // the first things a shop asks for, in the order they are asked: number(s), name, address, messages
        _Section('Contact numbers', Icons.phone_outlined, k, [
          _F(_contactsBlock(k), span: 99),
        ]),
        _Section('Customer', Icons.person_outline, k, [
          _F(
              _Tf('Name *', c('name'), k,
                  titleCase: true,
                  validator: (v) => _required(v, 'Name'),
                  onChanged: (v) {
                    _scheduleTranslate();
                    // "Smt. Rina Das" -> Female (only until the user picks a gender)
                    if (!_genderTouched) {
                      final g = DV.genderFromName(v);
                      if (g != null && g != _gender) setState(() => _gender = g);
                    }
                  }),
              span: 99),
          _F(_Tf('Name in Bengali (fills itself)', c('bengali'), k, suffix: _retranslateButton('name')), span: 99),
          _F(_Tf('Address', c('address'), k, lines: 2, titleCase: true, onChanged: (_) => _scheduleTranslate()), span: 99),
          _F(_Tf('Address in Bengali (fills itself)', c('addressBn'), k, lines: 2, suffix: _retranslateButton('address')), span: 99),
          _F(_notifyChips(k), span: 99),
          _F(_datesBlock(k), span: 99),
          _F(_referralBlock(k), span: 99),
        ]),
        if (!_more)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _more = true),
                icon: const Icon(Icons.expand_more),
                label: const Text('More details (email, birthday, GST, opening balance ...)'),
              ),
            ),
          )
        else ...[
          _Section('More about the customer', Icons.badge_outlined, k, [
            _F(branchField(k), span: 2),
            _F(_Drop('Membership', _membership, _memberships, (v) => setState(() => _membership = v), k)),
            _F(_Drop('Customer type', _type, _types, (v) => setState(() => _type = v), k)),
            _F(_Tf('Nickname', c('nickname'), k, titleCase: true, onChanged: (_) => _scheduleTranslate())),
            _F(_Tf('Nickname in Bengali (fills itself)', c('nicknameBn'), k, suffix: _retranslateButton('nickname'))),
            _F(_Drop('Gender', _gender, genders, (v) => setState(() {
                  _gender = v;
                  _genderTouched = true;
                }), k)),
            _F(_Tf('S/O · D/O · W/O', c('father'), k, titleCase: true)),
            _F(_Tf('Email', c('email'), k, keyboard: TextInputType.emailAddress, validator: DV.email)),
          ]),
          _Section('Address details', Icons.location_on_outlined, k, [
            _F(_Tf('Pincode', c('pincode'), k,
                keyboard: TextInputType.number,
                digits: true,
                maxLength: 6,
                validator: DV.pincode,
                onChanged: (v) => pincodeAutofill(v.trim()))),
            _F(_Tf('City', c('city'), k)),
            _F(_Tf('State', c('state'), k)),
            _F(_Tf('Country', c('country'), k)),
          ]),
          _Section('Business & tax', Icons.business_center_outlined, k, [
            _F(_Tf('Business / shop name', c('business'), k), span: 2),
            _F(_Tf('GST no.', c('gst'), k,
                caps: true,
                maxLength: 15,
                validator: DV.gst,
                onChanged: (_) => _gstAutofill(c('gst'), c('pan'), c('state')))),
            _F(_Tf('PAN no.', c('pan'), k, caps: true, maxLength: 10, validator: DV.pan)),
            _F(_Tf('Aadhaar no.', c('aadhar'), k,
                keyboard: TextInputType.number, digits: true, maxLength: 12, validator: DV.aadhaar)),
            _F(_Tf('Tax no.', c('tax'), k)),
          ]),
          openingSection(k),
          _Section('Other', Icons.notes_outlined, k, [
            _F(_Tf('Notes', c('notes'), k, lines: 2), span: 99),
          ]),
        ],
      ],
    );
  }
}

// ── Add / edit supplier / karigar ────────────────────────────────────────────
class AddPartyScreen extends StatefulWidget {
  const AddPartyScreen({super.key, required this.kind, this.existing});
  final DirectoryKind kind; // suppliers or karigars
  final Map<String, dynamic>? existing;

  @override
  State<AddPartyScreen> createState() => _AddPartyScreenState();
}

class _AddPartyScreenState extends State<AddPartyScreen>
    with _FormMixin<AddPartyScreen>, _OpeningMixin<AddPartyScreen> {
  static const _supplierTypes = ['Wholesaler', 'Retailer', 'Manufacturer', 'Other'];

  final _c = <String, TextEditingController>{};
  @override
  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);
  @override
  Map<String, dynamic>? get existing => widget.existing;

  String _partyType = _supplierTypes.first;
  String _gender = 'M';

  bool get _isKarigar => widget.kind == DirectoryKind.karigars;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _prefill(widget.existing!);
    } else {
      loadBranchDefaults();
    }
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _prefill(Map<String, dynamic> d) {
    final map = {
      'firm': 'firmName', 'first': 'firstName', 'last': 'lastName', 'father': 'fatherName',
      'mobile': 'mobile', 'phone': 'phone', 'email': 'email', 'reference': 'reference',
      'address': 'address', 'city': 'city', 'state': 'state', 'pincode': 'pincode',
      'business': 'businessName', 'gst': 'gstNo', 'pan': 'panNo', 'aadhar': 'aadharNo', 'tax': 'taxNo',
    };
    map.forEach((ctl, key) => c(ctl).text = _str(d[key]));
    final bank = d['bank'] is Map ? Map<String, dynamic>.from(d['bank']) : {};
    c('bankName').text = _str(bank['name']);
    c('bankAcName').text = _str(bank['accountName']);
    c('bankAcNo').text = _str(bank['accountNo']);
    c('ifsc').text = _str(bank['ifsc']);
    final nom = d['nominee'] is Map ? Map<String, dynamic>.from(d['nominee']) : {};
    c('nominee').text = _str(nom['name']);
    c('relation').text = _str(nom['relation']);
    if (!_isKarigar && _supplierTypes.contains(d['partyType'])) _partyType = d['partyType'];
    _gender = _str(d['gender']) == 'F' ? 'F' : 'M';
    loadOpening(d['opening']);
  }

  String get _fullName => [c('first').text.trim(), c('last').text.trim()].where((e) => e.isNotEmpty).join(' ');

  Map<String, dynamic> _build() {
    String t(String k) => c(k).text.trim();
    return {
      'partyType': _isKarigar ? 'Karigar' : _partyType,
      'firmName': t('firm'),
      'firstName': t('first'),
      'lastName': t('last'),
      'fatherName': t('father'),
      'gender': _gender,
      'mobile': t('mobile'),
      'phone': t('phone'),
      'email': t('email'),
      'reference': t('reference'),
      'address': t('address'),
      'city': t('city'),
      'state': t('state'),
      'pincode': t('pincode'),
      'businessName': t('business'),
      'gstNo': t('gst'),
      'panNo': t('pan'),
      'aadharNo': t('aadhar'),
      'taxNo': t('tax'),
      'bank': {
        'name': t('bankName'),
        'accountName': t('bankAcName'),
        'accountNo': t('bankAcNo'),
        'ifsc': t('ifsc'),
      },
      'nominee': {'name': t('nominee'), 'relation': t('relation')},
      'opening': openingJson(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final k = kind.color;
    return _FormPage(
      title: '${isEdit ? 'Edit' : 'Add'} ${kind.singular}',
      formKey: formKey,
      saving: saving,
      color: k,
      onSave: () => save(kind.path, _build,
          editPath: isEdit ? '${kind.path}/${widget.existing!['_id']}' : null,
          updatedAt: widget.existing?['updatedAt']),
      children: [
        _Section(kind.singular, Icons.person_outline, k, [
          _F(branchField(k), span: 2),
          if (!_isKarigar)
            _F(_Drop('Type', _partyType, _supplierTypes,
                (v) => setState(() => _partyType = v), k)),
          _F(_Tf('Firm name', c('firm'), k, titleCase: true)),
          _F(_Tf('First name *', c('first'), k,
              titleCase: true, validator: (v) => _required(v, 'Name'))),
          _F(_Tf('Last name', c('last'), k, titleCase: true)),
          _F(_Tf('Mobile no. *', c('mobile'), k, phone: true, validator: DV.mobile)),
          _F(_Tf('Phone no.', c('phone'), k, phone: true, validator: DV.phone10)),
          _F(_Tf('Email', c('email'), k, keyboard: TextInputType.emailAddress, validator: DV.email)),
          _F(_Tf('Reference', c('reference'), k)),
          _F(_GenderBox(_gender, (v) => setState(() => _gender = v), k)),
          _F(_Tf('Father name', c('father'), k, titleCase: true)),
        ]),
        _Section('Address', Icons.location_on_outlined, k, [
          _F(_Tf('Address', c('address'), k, lines: 2), span: 99),
          _F(_Tf('Pincode', c('pincode'), k,
              keyboard: TextInputType.number,
              digits: true,
              maxLength: 6,
              validator: DV.pincode,
              onChanged: (v) => pincodeAutofill(v.trim()))),
          _F(_Tf('City', c('city'), k)),
          _F(_Tf('State', c('state'), k)),
        ]),
        _Section('Business & tax', Icons.business_center_outlined, k, [
          _F(_Tf('Business / shop name', c('business'), k), span: 2),
          _F(_Tf('GST no.', c('gst'), k,
              caps: true,
              maxLength: 15,
              validator: DV.gst,
              onChanged: (_) => _gstAutofill(c('gst'), c('pan'), c('state')))),
          _F(_Tf('PAN no.', c('pan'), k, caps: true, maxLength: 10, validator: DV.pan)),
          _F(_Tf('Aadhaar no.', c('aadhar'), k,
              keyboard: TextInputType.number, digits: true, maxLength: 12, validator: DV.aadhaar)),
          _F(_Tf('Tax no.', c('tax'), k)),
        ]),
        _Section('Bank details', Icons.account_balance_outlined, k, [
          _F(_Tf('IFSC code', c('ifsc'), k,
              caps: true,
              maxLength: 11,
              validator: DV.ifsc,
              onChanged: (v) => ifscAutofill(v, holderDefault: _fullName))),
          _F(_Tf('Bank name', c('bankName'), k)),
          _F(_Tf('A/c holder name', c('bankAcName'), k, titleCase: true)),
          _F(_Tf('A/c no.', c('bankAcNo'), k, keyboard: TextInputType.number, digits: true)),
          _F(_Tf('Nominee', c('nominee'), k, titleCase: true)),
          _F(_Tf('Relation', c('relation'), k)),
        ]),
        openingSection(k),
      ],
    );
  }
}

// ── Add / edit staff profile ─────────────────────────────────────────────────
class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> with _FormMixin<AddStaffScreen> {
  final _c = <String, TextEditingController>{};
  @override
  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);
  @override
  Map<String, dynamic>? get existing => widget.existing;

  String _gender = 'M';
  String _marital = 'Single';
  DateTime? _dob;
  DateTime? _startDate;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _prefill(widget.existing!);
    } else {
      _startDate = DateTime.now(); // joining date defaults to today
      loadBranchDefaults();
    }
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _prefill(Map<String, dynamic> d) {
    final map = {
      'first': 'firstName', 'last': 'lastName', 'mobile': 'mobile', 'phone': 'phone', 'email': 'email',
      'emName': 'emergencyContactName', 'emPhone': 'emergencyContactPhone', 'address': 'address',
      'city': 'city', 'state': 'state', 'pincode': 'pincode', 'pan': 'panNo', 'aadhar': 'aadharNo',
    };
    map.forEach((ctl, key) => c(ctl).text = _str(d[key]));
    final edu = d['education'] is Map ? Map<String, dynamic>.from(d['education']) : {};
    c('degree').text = _str(edu['degree']);
    c('institution').text = _str(edu['institution']);
    c('year').text = _str(edu['passingYear']);
    c('certs').text = _str(edu['certifications']);
    final emp = d['employment'] is Map ? Map<String, dynamic>.from(d['employment']) : {};
    c('dept').text = _str(emp['department']);
    c('designation').text = _str(emp['designation']);
    c('salary').text = (emp['salary'] is num && emp['salary'] != 0) ? (emp['salary'] as num).toStringAsFixed(0) : '';
    c('prevCompany').text = _str(emp['previousCompany']);
    c('prevDesignation').text = _str(emp['previousDesignation']);
    final bank = emp['bank'] is Map ? Map<String, dynamic>.from(emp['bank']) : {};
    c('bankName').text = _str(bank['name']);
    c('bankAcName').text = _str(bank['accountName']);
    c('bankAcNo').text = _str(bank['accountNo']);
    c('ifsc').text = _str(bank['ifsc']);
    _gender = _str(d['gender']) == 'F' ? 'F' : 'M';
    _marital = ['Single', 'Married', 'Other'].contains(d['maritalStatus']) ? d['maritalStatus'] : 'Single';
    _dob = _dateOf(d['dob']);
    _startDate = _dateOf(emp['startDate']);
  }

  String get _fullName => [c('first').text.trim(), c('last').text.trim()].where((e) => e.isNotEmpty).join(' ');

  Map<String, dynamic> _build() {
    String t(String k) => c(k).text.trim();
    return {
      'firstName': t('first'),
      'lastName': t('last'),
      'dob': _dob?.toIso8601String(),
      'gender': _gender,
      'mobile': t('mobile'),
      'phone': t('phone'),
      'email': t('email'),
      'maritalStatus': _marital,
      'emergencyContactName': t('emName'),
      'emergencyContactPhone': t('emPhone'),
      'address': t('address'),
      'city': t('city'),
      'state': t('state'),
      'pincode': t('pincode'),
      'panNo': t('pan'),
      'aadharNo': t('aadhar'),
      'education': {
        'degree': t('degree'),
        'institution': t('institution'),
        'passingYear': t('year'),
        'certifications': t('certs'),
      },
      'employment': {
        'department': t('dept'),
        'designation': t('designation'),
        'salary': double.tryParse(t('salary')) ?? 0,
        'startDate': _startDate?.toIso8601String(),
        'bank': {
          'name': t('bankName'),
          'accountName': t('bankAcName'),
          'accountNo': t('bankAcNo'),
          'ifsc': t('ifsc'),
        },
        'previousCompany': t('prevCompany'),
        'previousDesignation': t('prevDesignation'),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final k = DirectoryKind.staff.color;
    return _FormPage(
      title: isEdit ? 'Edit Staff' : 'Add Staff',
      formKey: formKey,
      saving: saving,
      color: k,
      onSave: () => save('staff', _build,
          editPath: isEdit ? 'staff/profile/${widget.existing!['_id']}' : null,
          updatedAt: widget.existing?['updatedAt']),
      children: [
        _Section('Staff member', Icons.badge_outlined, k, [
          _F(branchField(k), span: 2),
          _F(_Tf('First name *', c('first'), k,
              titleCase: true, validator: (v) => _required(v, 'Name'))),
          _F(_Tf('Last name', c('last'), k, titleCase: true)),
          _F(_Tf('Mobile no. *', c('mobile'), k, phone: true, validator: DV.mobile)),
          _F(_Tf('Designation', c('designation'), k, titleCase: true)),
          _F(_Tf('Department', c('dept'), k, titleCase: true)),
          _F(_Tf('Monthly salary (₹)', c('salary'), k,
              keyboard: TextInputType.number, digits: true)),
          _F(_DateField('Joining date', _startDate, (d) => setState(() => _startDate = d), k)),
        ]),
        _Section('Personal', Icons.person_outline, k, [
          _F(_GenderBox(_gender, (v) => setState(() => _gender = v), k)),
          _F(_DateField('Date of birth', _dob, (d) => setState(() => _dob = d), k, showAge: true)),
          _F(_Drop('Marital status', _marital, const ['Single', 'Married', 'Other'],
              (v) => setState(() => _marital = v), k)),
          _F(_Tf('Email', c('email'), k, keyboard: TextInputType.emailAddress, validator: DV.email)),
          _F(_Tf('Phone no.', c('phone'), k, phone: true, validator: DV.phone10)),
          _F(_Tf('PAN no.', c('pan'), k, caps: true, maxLength: 10, validator: DV.pan)),
          _F(_Tf('Aadhaar no.', c('aadhar'), k,
              keyboard: TextInputType.number, digits: true, maxLength: 12, validator: DV.aadhaar)),
          _F(_Tf('Emergency contact', c('emName'), k, titleCase: true)),
          _F(_Tf('Emergency phone', c('emPhone'), k, phone: true, validator: DV.phone10)),
        ]),
        _Section('Address', Icons.location_on_outlined, k, [
          _F(_Tf('Address', c('address'), k, lines: 2), span: 99),
          _F(_Tf('Pincode', c('pincode'), k,
              keyboard: TextInputType.number,
              digits: true,
              maxLength: 6,
              validator: DV.pincode,
              onChanged: (v) => pincodeAutofill(v.trim()))),
          _F(_Tf('City', c('city'), k)),
          _F(_Tf('State', c('state'), k)),
        ]),
        _Section('Education', Icons.school_outlined, k, [
          _F(_Tf('Degree / course / grade', c('degree'), k)),
          _F(_Tf('Institution', c('institution'), k, titleCase: true)),
          _F(_Tf('Passing year', c('year'), k,
              keyboard: TextInputType.number, digits: true, maxLength: 4)),
          _F(_Tf('Certifications', c('certs'), k)),
        ]),
        _Section('Bank & previous job', Icons.account_balance_outlined, k, [
          _F(_Tf('IFSC code', c('ifsc'), k,
              caps: true,
              maxLength: 11,
              validator: DV.ifsc,
              onChanged: (v) => ifscAutofill(v, holderDefault: _fullName))),
          _F(_Tf('Bank name', c('bankName'), k)),
          _F(_Tf('A/c holder name', c('bankAcName'), k, titleCase: true)),
          _F(_Tf('A/c no.', c('bankAcNo'), k, keyboard: TextInputType.number, digits: true)),
          _F(_Tf('Previous company', c('prevCompany'), k, titleCase: true)),
          _F(_Tf('Previous designation', c('prevDesignation'), k, titleCase: true)),
        ]),
      ],
    );
  }
}
