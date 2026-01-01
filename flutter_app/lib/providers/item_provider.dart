import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/item_model.dart';
import '../services/api_service.dart';

class ItemProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Item> _items = [];
  Item? _selectedItem;
  bool _isLoading = false;
  String? _error;

  List<Item> get items => _items;
  Item? get selectedItem => _selectedItem;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get all items
  Future<void> fetchItems({String? status, Map<String, String>? filters}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      Map<String, String>? queryParams = filters;
      if (status != null) {
        queryParams = {...?filters, 'status': status};
      }
      final response = await _apiService.getItems(queryParams: queryParams);
      if (response['success'] == true) {
        _items = (response['data']['items'] as List)
            .map((item) => Item.fromJson(item))
            .toList();
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Get item by barcode
  Future<Item?> getItemByBarcode(String barcode) async {
    try {
      final response = await _apiService.getItemByBarcode(barcode);
      if (response['success'] == true) {
        return Item.fromJson(response['data']['item']);
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
    return null;
  }

  // Scan barcode
  Future<Item?> scanBarcode(String barcode) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.scanBarcode(barcode);
      if (response['success'] == true) {
        _selectedItem = Item.fromJson(response['data']['item']);
        _isLoading = false;
        notifyListeners();
        return _selectedItem;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Create item
  Future<bool> createItem(Map<String, dynamic> itemData, [List<XFile>? images]) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      Map<String, dynamic> response;
      
      if (images != null && images.isNotEmpty) {
        // Prepare string fields for multipart
        Map<String, String> stringFields = {};
        itemData.forEach((key, value) {
          if (value != null) {
            stringFields[key] = value.toString();
          }
        });
        
        response = await _apiService.createItemWithImages(stringFields, images);
      } else {
        response = await _apiService.createItem(itemData);
      }

      if (response['success'] == true) {
        final newItem = Item.fromJson(response['data']['item']);
        _items.insert(0, newItem);
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

  // Update item
  Future<bool> updateItem(String id, Map<String, dynamic> itemData, [List<XFile>? images]) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      Map<String, dynamic> response;
      
      if (images != null && images.isNotEmpty) {
        // Prepare string fields
        Map<String, String> stringFields = {};
        itemData.forEach((key, value) {
          if (value != null) {
            stringFields[key] = value.toString();
          }
        });
        
        response = await _apiService.updateItemWithImages(id, stringFields, images);
      } else {
        response = await _apiService.updateItem(id, itemData);
      }

      if (response['success'] == true) {
        final updatedItem = Item.fromJson(response['data']['item']);
        final index = _items.indexWhere((item) => item.id == id);
        if (index != -1) {
          _items[index] = updatedItem;
        }
        if (_selectedItem?.id == id) {
          _selectedItem = updatedItem;
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

  // Delete item
  Future<bool> deleteItem(String id) async {
    try {
      final response = await _apiService.deleteItem(id);
      if (response['success'] == true) {
        _items.removeWhere((item) => item.id == id);
        if (_selectedItem?.id == id) {
          _selectedItem = null;
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
    return false;
  }

  void setSelectedItem(Item? item) {
    _selectedItem = item;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
