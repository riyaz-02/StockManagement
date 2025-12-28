import 'package:flutter/material.dart';
import '../models/container_model.dart' as models;
import '../services/api_service.dart';

class ContainerProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<models.ItemContainer> _containers = [];
  models.ItemContainer? _selectedContainer;
  bool _isLoading = false;
  String? _error;

  List<models.ItemContainer> get containers => _containers;
  models.ItemContainer? get selectedContainer => _selectedContainer;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fetch all containers
  Future<void> fetchContainers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getContainers();
      if (response['success'] == true) {
        // Handle both response structures: data.containers or direct data array
        final containersData = response['data'];
        List<dynamic> containersList;
        
        if (containersData is Map && containersData.containsKey('containers')) {
          containersList = containersData['containers'] as List;
        } else if (containersData is List) {
          containersList = containersData;
        } else {
          containersList = [];
        }
        
        _containers = containersList
            .map((container) => models.ItemContainer.fromJson(container))
            .toList();
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      print('Container fetch error: $e'); // Debug log
    }

    _isLoading = false;
    notifyListeners();
  }

  // Get single container
  Future<void> fetchContainer(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getContainer(id);
      if (response['success'] == true) {
        _selectedContainer = models.ItemContainer.fromJson(response['data']['container']);
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create container
  Future<bool> createContainer(Map<String, dynamic> containerData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.createContainer(containerData);
      if (response['success'] == true) {
        final newContainer = models.ItemContainer.fromJson(response['data']['container']);
        _containers.insert(0, newContainer);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  void setSelectedContainer(models.ItemContainer? container) {
    _selectedContainer = container;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
