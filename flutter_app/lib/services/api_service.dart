import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
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
    // Check if response is HTML instead of JSON
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/html')) {
      print('[API] ERROR: Received HTML response instead of JSON');
      print('[API] Status Code: ${response.statusCode}');
      print('[API] URL: ${response.request?.url}');
      print('[API] Response preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      throw Exception('Server returned HTML instead of JSON. Status: ${response.statusCode}. This usually means the endpoint was not found or there\'s a server configuration issue.');
    }

    try {
      final body = json.decode(response.body);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'An error occurred');
      }
    } catch (e) {
      if (e is FormatException) {
        print('[API] JSON Parse Error: ${e.message}');
        print('[API] Response body: ${response.body}');
        throw Exception('Invalid JSON response from server');
      }
      rethrow;
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
    // Add timestamp to prevent caching (HTTP 304 fix)
    final uri = Uri.parse('${AppConstants.baseUrl}/containers/$id').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final response = await http.get(
      uri,
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

  Future<Map<String, dynamic>> getItemFilterOptions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/items/filter-options'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getItem(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/items/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }
  
  // Alias for getItem
  Future<Map<String, dynamic>> getItemById(String id) async {
    return getItem(id);
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

  Future<Map<String, dynamic>> restoreItem(String id, String containerId, int? slotNumber) async {
    final body = {
      'containerId': containerId,
      if (slotNumber != null) 'slotNumber': slotNumber,
    };
    
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/items/$id/restore'),
      headers: await _getHeaders(),
      body: json.encode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> permanentDeleteItem(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/items/$id/permanent'),
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

  // Lookup barcode - searches both items and containers
  Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/scan/lookup/$barcode'),
      headers: await _getHeaders(),
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

  // Outward Movements
  Future<Map<String, dynamic>> createOutwardMovement(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/outward-movements'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> returnItem(String movementId) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/outward-movements/$movementId/return'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getItemMovements(String itemId) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/outward-movements/item/$itemId'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getOutwardMovements({String? status, String? movementType}) async {
    String url = '${AppConstants.baseUrl}/outward-movements';
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (movementType != null) params['movementType'] = movementType;
    
    final uri = Uri.parse(url).replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: await _getHeaders());
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

  // Bookings
  Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/bookings'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }


  
  Future<Map<String, dynamic>> updateBooking(String id, Map<String, dynamic> data) async {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/bookings/$id'),
        headers: await _getHeaders(),
        body: json.encode(data),
      );
      return _handleResponse(response);
  }

  Future<Map<String, dynamic>> sellItem(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/items/$id/sell'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> markItemAsNoSell(String id) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/items/$id/mark-no-sell'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> markItemAsActive(String id) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/items/$id/mark-active'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }



  Future<Map<String, dynamic>> getDeletedItems() async {
     final response = await http.get(
       Uri.parse('${AppConstants.baseUrl}/items?status=deleted'),
       headers: await _getHeaders(),
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

  // Customers & Wishlist
  Future<Map<String, dynamic>> addToWishlist(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/customers/wishlist'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> removeFromWishlist(String mobile, String itemId) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/customers/wishlist/remove'),
      headers: await _getHeaders(),
      body: json.encode({'mobile': mobile, 'itemId': itemId}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getItemInteractions(String itemId) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/customers/item/$itemId'),
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

  // Create item with images (Multipart)
  Future<Map<String, dynamic>> createItemWithImages(Map<String, String> fields, List<XFile> images) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/items');
    final request = http.MultipartRequest('POST', uri);
    return _sendMultipartRequest(request, fields, images);
  }

  // Update item with images (Multipart)
  Future<Map<String, dynamic>> updateItemWithImages(String id, Map<String, String> fields, List<XFile> images) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/items/$id');
    final request = http.MultipartRequest('PUT', uri);
    return _sendMultipartRequest(request, fields, images);
  }

  // Helper for multipart requests
  Future<Map<String, dynamic>> _sendMultipartRequest(http.MultipartRequest request, Map<String, String> fields, List<XFile> images) async {
    // Add headers
    final headers = await _getHeaders();
    request.headers.addAll(headers);
    // Remove content-type as MultipartRequest sets it automatically
    request.headers.remove('Content-Type');

    // Add text fields
    fields.forEach((key, value) {
      if (value.isNotEmpty) {
        request.fields[key] = value;
      }
    });

    print('Sending API Request: ${request.method} ${request.url}');
    print('Fields: ${request.fields}');


    // Add images
    for (var image in images) {
       final bytes = await image.readAsBytes();
       
       String? mimeType;
       if (image.name.toLowerCase().endsWith('.jpg') || image.name.toLowerCase().endsWith('.jpeg')) {
         mimeType = 'image/jpeg';
       } else if (image.name.toLowerCase().endsWith('.png')) {
         mimeType = 'image/png';
       } else if (image.name.toLowerCase().endsWith('.webp')) {
         mimeType = 'image/webp';
       }
       
       request.files.add(http.MultipartFile.fromBytes(
         'images', 
         bytes,
         filename: image.name,
         contentType: mimeType != null ? MediaType.parse(mimeType) : null,
       ));
    }

    // Send request
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  // ==================== TALLY METHODS ====================
  
  // Create new tally session
  Future<Map<String, dynamic>> createTally(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  // Get all tally sessions
  Future<Map<String, dynamic>> getTallySessions({String? status}) async {
    var uri = Uri.parse('${AppConstants.baseUrl}/tally');
    if (status != null) {
      uri = uri.replace(queryParameters: {'status': status});
    }
    
    final response = await http.get(
      uri,
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Get single tally session
  Future<Map<String, dynamic>> getTallySession(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tally/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Scan item in tally
  Future<Map<String, dynamic>> scanItemInTally(String tallyId, String barcode) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/scan'),
      headers: await _getHeaders(),
      body: json.encode({'barcode': barcode}),
    );
    return _handleResponse(response);
  }

  // Verify weight for approx/bulk items during tally
  Future<Map<String, dynamic>> verifyTallyWeight(String tallyId, String itemId, double verifiedWeight) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/verify-weight'),
      headers: await _getHeaders(),
      body: json.encode({
        'itemId': itemId,
        'verifiedWeight': verifiedWeight,
      }),
    );
    return _handleResponse(response);
  }

  // Lock tally session
  Future<Map<String, dynamic>> lockTally(String tallyId, {String? remarks}) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/lock'),
      headers: await _getHeaders(),
      body: json.encode({'remarks': remarks ?? ''}),
    );
    return _handleResponse(response);
  }

  // Get tally report
  Future<Map<String, dynamic>> getTallyReport(String tallyId) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/report'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Delete tally session
  Future<Map<String, dynamic>> deleteTallySession(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/tally/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Analytics APIs
  
  // Get dashboard statistics
  Future<Map<String, dynamic>> getDashboardStats() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/analytics/dashboard'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Tag Printing APIs
  
  // Get all items for tag printing
  Future<List<Map<String, dynamic>>> getItemsForTagPrinting() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tag-print/items'),
      headers: await _getHeaders(),
    );
    final data = _handleResponse(response);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // Record tag print event
  Future<Map<String, dynamic>> recordTagPrint(List<String> itemIds) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tag-print/record'),
      headers: await _getHeaders(),
      body: json.encode({'itemIds': itemIds}),
    );
    return _handleResponse(response);
  }

  // Get tag print history for an item
  Future<Map<String, dynamic>> getTagPrintHistory(String itemId) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tag-print/history/$itemId'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Generate PDF for selected items (server-side)
  Future<Uint8List> generateTagsPDF(List<String> itemIds) async {
    try {
      final token = await _storage.getToken();
      
      // Custom headers for PDF download - don't use _getHeaders()
      final headers = {
        'Content-Type': 'application/json', // For request body
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/tag-print/generate-pdf'),
        headers: headers,
        body: jsonEncode({'itemIds': itemIds}),
      );

      print('[API] PDF response status: ${response.statusCode}');
      print('[API] PDF response length: ${response.bodyBytes.length}');
      print('[API] Content-Type: ${response.headers['content-type']}');
      print('[API] First 10 bytes: ${response.bodyBytes.take(10).toList()}');

      if (response.statusCode == 200) {
        // Return raw bytes directly
        final bytes = response.bodyBytes;
        print('[API] Returning ${bytes.length} bytes');
        return bytes;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        print('[API] Error response: $errorBody');
        throw Exception('Failed to generate PDF: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[API] Exception generating PDF: $e');
      rethrow;
    }
  }

  // Cloudinary Image Upload
  /// Upload single image to Cloudinary
  /// [folder] - Optional folder name: 'items' (default) or 'containers'
  /// Returns: {success: bool, data: {url: String, publicId: String}}
  Future<Map<String, dynamic>> uploadImage(XFile imageFile, {String folder = 'items'}) async {
    try {
      final token = await _storage.getToken();
      // Add folder query parameter
      final uri = Uri.parse('${AppConstants.baseUrl}/upload/single?folder=$folder');
      
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add image file
      final bytes = await imageFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: imageFile.name,
          contentType: MediaType('image', imageFile.name.split('.').last),
        ),
      );
      
      print('[API] Uploading image to Cloudinary ($folder): ${imageFile.name}');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      return _handleResponse(response);
    } catch (e) {
      print('[API] Image upload error: $e');
      rethrow;
    }
  }

  /// Delete image from Cloudinary
  /// imageUrl: Full Cloudinary URL
  /// Returns: true if deleted successfully
  Future<bool> deleteImage(String imageUrl) async {
    try {
      // Extract public_id from URL
      // URL format: https://res.cloudinary.com/cloud-name/image/upload/v1234/folder/filename.jpg
      final urlParts = imageUrl.split('/');
      final uploadIndex = urlParts.indexOf('upload');
      
      if (uploadIndex == -1) {
        print('[API] Not a Cloudinary URL, skipping deletion');
        return false;
      }

      // Get everything after 'upload/v123456/'
      final publicIdWithExt = urlParts.sublist(uploadIndex + 2).join('/');
      // Remove file extension
      final publicId = publicIdWithExt.substring(0, publicIdWithExt.lastIndexOf('.'));
      
      // Replace / with -- for URL encoding
      final encodedPublicId = publicId.replaceAll('/', '--');
      
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/upload/$encodedPublicId'),
        headers: await _getHeaders(),
      );
      
      if (response.statusCode == 200) {
        print('[API] ✅ Image deleted from Cloudinary: $publicId');
        return true;
      } else {
        print('[API] ⚠️ Failed to delete image: ${response.body}');
        return false;
      }
    } catch (e) {
      print('[API] Image deletion error: $e');
      return false;
    }
  }

  // User Management Methods
  /// Get all users (admin only)
  Future<Map<String, dynamic>> getUsers() async {
    try {
      final token = await _storage.getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Get users error: $e');
      rethrow;
    }
  }

  /// Get single user by ID
  Future<Map<String, dynamic>> getUser(String id) async {
    try {
      final token = await _storage.getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Get user error: $e');
      rethrow;
    }
  }

  /// Create new user (admin only)
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    try {
      final token = await _storage.getToken();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/users'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(userData),
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Create user error: $e');
      rethrow;
    }
  }

  /// Update user profile
  Future<Map<String, dynamic>> updateUser(String id, Map<String, dynamic> userData) async {
    try {
      final token = await _storage.getToken();
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/users/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(userData),
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Update user error: $e');
      rethrow;
    }
  }

  /// Delete user (admin only)
  Future<Map<String, dynamic>> deleteUser(String id) async {
    try {
      final token = await _storage.getToken();
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/users/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Delete user error: $e');
      rethrow;
    }
  }

  /// Change password
  Future<Map<String, dynamic>> changePassword(String userId, String currentPassword, String newPassword) async {
    try {
      final token = await _storage.getToken();
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/users/$userId/password'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      print('[API] Change password error: $e');
      rethrow;
    }
  }

  // Tag Settings
  Future<Map<String, dynamic>> getTagSettings() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tag-settings'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateTagSettings(Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tag-settings'),
      headers: await _getHeaders(),
      body: jsonEncode(data),
    );
    return _handleResponse(response);
  }

  // Generate PDF for blank tags
  Future<Uint8List> generateBlankTagsPDF(Map<String, int> purityCounts) async {
    try {
      final token = await _storage.getToken();
      
      // Custom headers for PDF download
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/tag-print/generate-blank-tags-pdf'),
        headers: headers,
        body: jsonEncode({'purityCounts': purityCounts}),
      );

      print('[API] Blank Tags PDF response status: ${response.statusCode}');
      print('[API] Blank Tags PDF response length: ${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        print('[API] Returning ${bytes.length} bytes for blank tags PDF');
        return bytes;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        print('[API] Error response: $errorBody');
        throw Exception('Failed to generate blank tags PDF: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[API] Exception generating blank tags PDF: $e');
      rethrow;
    }
  }
}
