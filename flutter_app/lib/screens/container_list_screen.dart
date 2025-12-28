import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
import '../providers/language_provider.dart';
import 'container_view_screen.dart';
import 'add_container_screen.dart';

class ContainerListScreen extends StatefulWidget {
  const ContainerListScreen({super.key});

  @override
  State<ContainerListScreen> createState() => _ContainerListScreenState();
}

class _ContainerListScreenState extends State<ContainerListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<ContainerProvider>(context, listen: false).fetchContainers());
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.translate('containers')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddContainerScreen()),
          );
          // Refresh list after adding
          if (mounted) {
            Provider.of<ContainerProvider>(context, listen: false).fetchContainers();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Consumer<ContainerProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
                  const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    languageProvider.translate('no_data'),
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
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
            padding: const EdgeInsets.all(16),
            itemCount: provider.containers.length,
            itemBuilder: (context, index) {
              final container = provider.containers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.inventory_2, size: 40),
                  title: Text(container.name),
                  subtitle: Text(
                    '${container.occupiedSlots}/${container.capacity} slots occupied',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContainerViewScreen(container: container),
                      ),
                    );
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
