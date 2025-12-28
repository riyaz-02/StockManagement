import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/container_model.dart' as models;
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';

class ContainerViewScreen extends StatefulWidget {
  final models.ItemContainer container;

  const ContainerViewScreen({super.key, required this.container});

  @override
  State<ContainerViewScreen> createState() => _ContainerViewScreenState();
}

class _ContainerViewScreenState extends State<ContainerViewScreen> {
  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.container.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Container Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoRow(
                      languageProvider.translate('container_type'),
                      widget.container.type,
                    ),
                    const Divider(),
                    _buildInfoRow(
                      languageProvider.translate('capacity'),
                      '${widget.container.capacity} slots',
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatChip(
                          languageProvider.translate('occupied_slots'),
                          widget.container.occupiedSlots.toString(),
                          AppColors.statusActive,
                        ),
                        _buildStatChip(
                          languageProvider.translate('available_slots'),
                          widget.container.availableSlots.toString(),
                          AppColors.slotEmpty,
                        ),
                        _buildStatChip(
                          languageProvider.translate('reserved_slots'),
                          widget.container.reservedSlots.toString(),
                          AppColors.slotReserved,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Legend
            Text(
              'Slot Status:',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildLegendItem('Empty', AppColors.slotEmpty),
                _buildLegendItem('Occupied', AppColors.slotOccupied),
                _buildLegendItem('Booked', AppColors.slotBooked),
                _buildLegendItem('Reserved', AppColors.slotReserved),
              ],
            ),
            const SizedBox(height: 24),

            // Slots Grid
            Text(
              'Slots Layout:',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildSlotsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Widget _buildSlotsGrid() {
    final columns = widget.container.layoutType == 'linear' ? 5 : 6;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: widget.container.slots.length,
      itemBuilder: (context, index) {
        final slot = widget.container.slots[index];
        return _buildSlotItem(slot);
      },
    );
  }

  Widget _buildSlotItem(models.ContainerSlot slot) {
    Color slotColor;
    IconData? icon;
    
    if (slot.isReserved) {
      slotColor = AppColors.slotReserved;
      icon = Icons.lock;
    } else if (slot.isOccupied) {
      slotColor = AppColors.slotOccupied;
      icon = Icons.check_circle;
    } else {
      slotColor = AppColors.slotEmpty;
      icon = null;
    }

    return GestureDetector(
      onTap: slot.isOccupied
          ? () {
              // TODO: Navigate to item details
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Item ID: ${slot.itemId}')),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: slotColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: slotColor.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            const SizedBox(height: 4),
            Text(
              slot.slotNumber.toString(),
              style: TextStyle(
                color: slot.isEmpty ? Colors.black54 : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
