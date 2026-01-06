import 'package:flutter/material.dart';
import 'dart:typed_data';
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

  // Update container
  Future<bool> updateContainer(String id, Map<String, dynamic> containerData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.updateContainer(id, containerData);
      if (response['success'] == true) {
        final updatedContainer = models.ItemContainer.fromJson(response['data']['container']);
        final index = _containers.indexWhere((c) => c.id == id);
        if (index != -1) {
          _containers[index] = updatedContainer;
        }
        if (_selectedContainer?.id == id) {
          _selectedContainer = updatedContainer;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    _isLoading = false;
    notifyListeners();
    return false;
  }



  // Fetch deleted containers (Recycle Bin)
  // Note: This does not affect global _isLoading to avoid rebuilding the main list
  Future<List<models.ItemContainer>> fetchDeletedContainers() async {
    try {
      // Add timestamp to prevent caching (HTTP 304 fix)
      final response = await _apiService.getContainers(queryParams: {
        'isDeleted': 'true',
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      if (response['success'] == true) {
        final containersData = response['data']['containers'] as List;
        return containersData
            .map((container) => models.ItemContainer.fromJson(container))
            .toList();
      }
    } catch (e) {
      print('Fetch deleted error: $e');
      // We don't set global _error here to avoid disrupting main UI
    }
    return [];
  }

  // Restore container
  Future<bool> restoreContainer(String id) async {
    // Note: We don't set global _isLoading here to prevent rebuilding the details screen
    // The UI can handle its own loading state if needed
    try {
      final response = await _apiService.updateContainer(id, {
        'isDeleted': false,
        'isActive': true,
      });

      if (response['success'] == true) {
        // Refresh main list in background
        fetchContainers(); 
        return true;
      }
    } catch (e) {
       print('Restore error: $e');
    }
    return false;
  }

  // Permanently delete container
  Future<bool> deleteContainerPermanently(String id) async {
    try {
      final response = await _apiService.deleteContainer(id, force: true);
      if (response['success'] == true) {
        return true;
      }
    } catch (e) {
      print('Permanent delete error: $e');
    }
    return false;
  }

  Future<bool> deleteContainer(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.deleteContainer(id);
      if (response['success'] == true) {
        _containers.removeWhere((c) => c.id == id);
        if (_selectedContainer?.id == id) {
          _selectedContainer = null;
        }
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

  // Get next available serial for a prefix (checks both active and deleted containers)
  Future<int> getNextSerial(String prefix) async {
    int maxSerial = 0;
    
    // Check active containers
    for (var container in _containers) {
      String? code = container.qrCode;
      
      if (code != null && code.startsWith(prefix)) {
        String remaining = code.substring(prefix.length);
        int? serial = int.tryParse(remaining);
        if (serial != null && serial > maxSerial) {
          maxSerial = serial;
        }
      }
    }
    
    // Also check deleted containers to avoid barcode conflicts
    try {
      final deletedContainers = await fetchDeletedContainers();
      for (var container in deletedContainers) {
        String? code = container.qrCode;
        
        if (code != null && code.startsWith(prefix)) {
          String remaining = code.substring(prefix.length);
          int? serial = int.tryParse(remaining);
          if (serial != null && serial > maxSerial) {
            maxSerial = serial;
          }
        }
      }
    } catch (e) {
      print('Error checking deleted containers for serial: $e');
    }
    
    return maxSerial + 1;
  }

  void setSelectedContainer(models.ItemContainer? container) {
    _selectedContainer = container;
    notifyListeners();
  }

  Future<String?> uploadImage(Uint8List bytes, String filename) async {
    try {
      return await _apiService.uploadContainerImage(bytes, filename);
    } catch (e) {
      print('Provider upload error: $e');
      return null;
    }
  }

  // Toggle container lock status
  Future<bool> toggleContainerLock(String id, bool isLocked) async {
    try {
      final response = await _apiService.updateContainer(id, {
        'isLocked': isLocked,
      });

      if (response['success'] == true) {
        // Update local list
        final updatedContainer = models.ItemContainer.fromJson(response['data']['container']);
        final index = _containers.indexWhere((c) => c.id == id);
        if (index != -1) {
          _containers[index] = updatedContainer;
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      print('Lock toggle error: $e');
    }
    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
