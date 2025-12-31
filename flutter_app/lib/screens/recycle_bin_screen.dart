import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
import '../models/container_model.dart' as models;
import '../providers/language_provider.dart';
import 'container_view_screen.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  late Future<List<models.ItemContainer>> _deletedContainersFuture;

  @override
  void initState() {
    super.initState();
    _loadDeletedContainers();
  }

  void _loadDeletedContainers() {
    setState(() {
      _deletedContainersFuture = Provider.of<ContainerProvider>(context, listen: false).fetchDeletedContainers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<models.ItemContainer>>(
        future: _deletedContainersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDeletedContainers,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final deletedContainers = snapshot.data ?? [];

          if (deletedContainers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delete_outline, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Recycle Bin is Empty',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deletedContainers.length,
            itemBuilder: (context, index) {
              final container = deletedContainers[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: const Icon(Icons.inventory_2_outlined, color: Colors.red),
                  ),
                  title: Text(
                    container.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${container.capacity} slots • ${container.type}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContainerViewScreen(container: container),
                      ),
                    ).then((_) => _loadDeletedContainers()); // Refresh on return
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
