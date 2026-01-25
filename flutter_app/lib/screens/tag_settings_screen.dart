import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class TagSettingsScreen extends StatefulWidget {
  const TagSettingsScreen({Key? key}) : super(key: key);

  @override
  State<TagSettingsScreen> createState() => _TagSettingsScreenState();
}

class _TagSettingsScreenState extends State<TagSettingsScreen> {
  final _widthController = TextEditingController(text: '50');
  final _heightController = TextEditingController(text: '30');
  
  Map<String, Color> _purityColors = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final settings = await settingsProvider.getTagSettings();
      
      if (settings != null && mounted) {
        setState(() {
          _widthController.text = settings['tagWidth']?.toString() ?? '50';
          _heightController.text = settings['tagHeight']?.toString() ?? '30';
          
          // Load purity colors
          final purityColors = settings['purityColors'] as List? ?? [];
          _purityColors = {};
          for (var pc in purityColors) {
            final purity = pc['purity'] as String;
            final colorHex = pc['color'] as String;
            _purityColors[purity] = _hexToColor(colorHex);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    
    try {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      
      final purityColorsList = _purityColors.entries.map((e) => {
        'purity': e.key,
        'color': _colorToHex(e.value),
      }).toList();
      
      await settingsProvider.updateTagSettings(
        tagWidth: double.parse(_widthController.text),
        tagHeight: double.parse(_heightController.text),
        purityColors: purityColorsList,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag settings saved successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  void _pickColor(String purity, Color currentColor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pick color for $purity'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              setState(() {
                _purityColors[purity] = color;
              });
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('Tag Printing Settings', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag Size Section
                  const Text('Tag Size (mm)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          decoration: const InputDecoration(
                            labelText: 'Width',
                            border: OutlineInputBorder(),
                            suffixText: 'mm',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          decoration: const InputDecoration(
                            labelText: 'Height',
                            border: OutlineInputBorder(),
                            suffixText: 'mm',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Purity Colors Section
                  const Text('Purity Colors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Tap to change color for each purity', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  if (_purityColors.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No purity options found. Add purities in Item Settings first.'),
                      ),
                    )
                  else
                    ..._purityColors.entries.map((entry) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: entry.value,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_colorToHex(entry.value)),
                          trailing: const Icon(Icons.edit, color: Colors.blue),
                          onTap: () => _pickColor(entry.key, entry.value),
                        ),
                      );
                    }).toList(),
                  
                  const SizedBox(height: 32),
                  
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }
}
