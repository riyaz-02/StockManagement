import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../utils/app_constants.dart';
import 'storage_service.dart';

class ApiService {
  final StorageService _storage = StorageService();
  
  // Get headers with auth token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Handle API response
  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = json.decode(response.body);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(body['message'] ?? 'An error occurred');
    }
  }

  // Authentication
  Future<Map<String, dynamic>> login(String mobile, String password) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'mobile': mobile, 'password': password}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/auth/me'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateLanguage(String language) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/auth/language'),
      headers: await _getHeaders(),
      body: json.encode({'language': language}),
    );
    return _handleResponse(response);
  }

  // Containers
  Future<Map<String, dynamic>> getContainers({Map<String, String>? queryParams}) async {
    var uri = Uri.parse('${AppConstants.baseUrl}/containers');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }
    
    final response = await http.get(
      uri,
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getContainer(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/containers/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> createContainer(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/containers'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateContainer(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/containers/$id'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteContainer(String id, {bool force = false}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/containers/$id').replace(
      queryParameters: force ? {'force': 'true'} : null,
    );
    
    final response = await http.delete(
      uri,
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<String?> uploadContainerImage(Uint8List bytes, String filename) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/containers/upload');
    final request = http.MultipartRequest('POST', uri);
    
    // Auth header only (MultipartRequest sets Content-Type automatically)
    final token = await _storage.getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final body = _handleResponse(response);
    
    if (body['success'] == true) {
      return body['url'];
    }
    return null;
  }

  // Items
  Future<Map<String, dynamic>> getItems({Map<String, String>? queryParams}) async {
    var uri = Uri.parse('${AppConstants.baseUrl}/items');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getItem(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/items/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getItemByBarcode(String barcode) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/items/barcode/$barcode'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> createItem(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/items'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateItem(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/items/$id'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteItem(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/items/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Scan
  Future<Map<String, dynamic>> scanBarcode(String barcode) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/scan'),
      headers: await _getHeaders(),
      body: json.encode({'barcode': barcode}),
    );
    return _handleResponse(response);
  }

  // Repair
  Future<Map<String, dynamic>> sendToRepair(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/repair/send'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> returnFromRepair(String repairLogId) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/repair/return'),
      headers: await _getHeaders(),
      body: json.encode({'repairLogId': repairLogId}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getRepairItems() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/repair'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Tally
  Future<Map<String, dynamic>> startTally(String description) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally/start'),
      headers: await _getHeaders(),
      body: json.encode({'description': description}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> scanItemInTally(String tallySessionId, String barcode) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally/scan'),
      headers: await _getHeaders(),
      body: json.encode({
        'tallySessionId': tallySessionId,
        'barcode': barcode,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> lockTally(String tallySessionId) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally/lock'),
      headers: await _getHeaders(),
      body: json.encode({'tallySessionId': tallySessionId}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getTallySessions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tally'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getTallySession(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tally/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Bookings
  Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/bookings'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getBookings({String? status}) async {
    var uri = Uri.parse('${AppConstants.baseUrl}/bookings');
    if (status != null) {
      uri = uri.replace(queryParameters: {'status': status});
    }
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> cancelBooking(String id) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/bookings/$id/cancel'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> completeBooking(String id) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/bookings/$id/complete'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Reports
  Future<Map<String, dynamic>> getDailySummary() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/reports/daily'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  String getTallyPdfUrl(String tallyId) {
    return '${AppConstants.baseUrl}/reports/tally/$tallyId/pdf';
  }

  String getTallyExcelUrl(String tallyId) {
    return '${AppConstants.baseUrl}/reports/tally/$tallyId/excel';
  }

  // Settings APIs
  Future<Map<String, dynamic>> getSettings(String category) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/settings/$category'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSetting(String category, String type) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/settings/$category/$type'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateSetting(
    String category,
    String type,
    List<String> values,
  ) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/settings/$category/$type'),
      headers: await _getHeaders(),
      body: json.encode({'values': values}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addSettingValue(
    String category,
    String type,
    String value,
  ) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/settings/$category/$type/add'),
      headers: await _getHeaders(),
      body: json.encode({'value': value}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteSettingValue(
    String category,
    String type,
    String value,
  ) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/settings/$category/$type/$value'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> initializeSettings() async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/settings/initialize'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }
}
