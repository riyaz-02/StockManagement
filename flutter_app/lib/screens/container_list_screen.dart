import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../models/container_model.dart' as models;
import 'container_view_screen.dart';
import 'add_container_screen.dart';
import 'item_details_screen.dart';
import '../utils/app_constants.dart';
import 'recycle_bin_screen.dart';

import 'edit_container_screen.dart';
import '../utils/app_toast.dart';

class ContainerListScreen extends StatefulWidget {
  const ContainerListScreen({super.key});

  @override
  State<ContainerListScreen> createState() => _ContainerListScreenState();
}

class _ContainerListScreenState extends State<ContainerListScreen>
    with AutomaticKeepAliveClientMixin {
  String _statusFilter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _refreshContainers());
  }

  void _refreshContainers() {
    if (mounted) {
      Provider.of<ContainerProvider>(context, listen: false).fetchContainers();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          languageProvider.t('containers'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE94560), Color(0xFFD32F2F)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE94560).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddContainerScreen()),
            );
            _refreshContainers();
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Active', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Inactive', 'inactive'),
                const SizedBox(width: 8),
                _buildFilterChip('Locked', 'locked'),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ContainerProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.error != null && provider.containers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${provider.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => provider.fetchContainers(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (provider.containers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No containers found',
                          style:
                              const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap + to add a container',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  key: const PageStorageKey<String>('containersListView'),
                  padding: const EdgeInsets.all(16),
                  itemCount: _filterContainers(provider.containers).length,
                  itemBuilder: (context, index) {
                    final container =
                        _filterContainers(provider.containers)[index];
                    // Use specific colors for status
                    Color statusColor = Colors.grey;
                    String statusText = 'INACTIVE';

                    if (container.isActive) {
                      if (container.isLocked) {
                        statusColor = Colors.orange;
                        statusText = 'LOCKED';
                      } else {
                        statusColor = Colors.green;
                        statusText = 'ACTIVE';
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ContainerViewScreen(container: container),
                            ),
                          ).then((_) => _refreshContainers());
                        },
                        onLongPress: () {
                          _showContainerOptions(context, container);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Container Image (Placeholder)
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: statusColor.withOpacity(0.3)),
                                  image: (container.image != null &&
                                          container.image!.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(container.image!
                                                  .startsWith('http')
                                              ? container.image!
                                              : '${AppConstants.baseUrl}${container.image}'),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: (container.image == null ||
                                        container.image!.isEmpty)
                                    ? Icon(
                                        container.isLocked
                                            ? Icons.lock
                                            : Icons.inventory_2,
                                        size: 30,
                                        color: statusColor,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),

                              // 2. Details Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Name and Type Row
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                container.name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                container.qrCode ??
                                                    container.id
                                                        .substring(0, 8),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            container.type.toUpperCase(),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Stats Row
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Slots Info
                                        Row(
                                          children: [
                                            Icon(Icons.grid_view,
                                                size: 14,
                                                color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${container.availableSlots}/${container.capacity} Avl',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        // Status Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: statusColor
                                                    .withOpacity(0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                container.isLocked
                                                    ? Icons.lock
                                                    : (container.isActive
                                                        ? Icons.check_circle
                                                        : Icons.cancel),
                                                size: 12,
                                                color: statusColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _statusFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFD32F2F)],
                )
              : null,
          color: isSelected ? null : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  List<models.ItemContainer> _filterContainers(
      List<models.ItemContainer> containers) {
    if (_statusFilter == 'all') return containers;

    return containers.where((container) {
      switch (_statusFilter) {
        case 'active':
          return container.isActive;
        case 'inactive':
          return !container.isActive;
        case 'locked':
          return container.isLocked;
        default:
          return true;
      }
    }).toList();
  }

  void _showContainerOptions(
      BuildContext context, models.ItemContainer container) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                container.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new, color: Colors.blue),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ContainerViewScreen(container: container),
                    ),
                  ).then((_) => _refreshContainers());
                },
              ),
              ListTile(
                leading: Icon(
                  container.isLocked ? Icons.lock_open : Icons.lock_outline,
                  color: Colors.orange,
                ),
                title: Text(container.isLocked ? 'Unlock' : 'Lock'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Provider.of<ContainerProvider>(context, listen: false)
                      .toggleContainerLock(container.id, !container.isLocked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.black87),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EditContainerScreen(container: container),
                    ),
                  ).then((_) => _refreshContainers());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Move to Trash?'),
                      content: const Text('Delete this container?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && mounted) {
                    final provider =
                        Provider.of<ContainerProvider>(context, listen: false);
                    final success =
                        await provider.deleteContainer(container.id);

                    if (success) {
                      _refreshContainers(); // Refresh after successful delete
                    } else {
                      if (mounted && provider.error != null) {
                        showAppSnackBar(
                          context,
                          SnackBar(
                            content: Text(provider.error!),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
