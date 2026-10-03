import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_constants.dart';
import 'storage_service.dart';

class ApiService {
  final StorageService _storage = StorageService();

  /// The branch an admin has switched to ('' = the whole firm). Sent as `X-Branch`; the server ignores it for staff who
  /// lack every-branch access, so it can never widen what someone may see.
  static String activeBranch = '';

  /// The GST registration (GSTIN) the GST Summary shows: '' = the firm's default, 'ALL' = every registration (only the
  /// summary / register / export can add them up; returns, credit and filings always belong to one GSTIN).
  static String activeGstin = '';

  // Get headers with auth token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (activeBranch.isNotEmpty) 'X-Branch': activeBranch,
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
      print(
          '[API] Response preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      throw Exception(
          'Server returned HTML instead of JSON. Status: ${response.statusCode}. This usually means the endpoint was not found or there\'s a server configuration issue.');
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
  Future<Map<String, dynamic>> getContainers(
      {Map<String, String>? queryParams}) async {
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

  Future<Map<String, dynamic>> createContainer(
      Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/containers'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateContainer(
      String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/containers/$id'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteContainer(String id,
      {bool force = false}) async {
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
  Future<Map<String, dynamic>> getItems(
      {Map<String, String>? queryParams}) async {
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

  Future<Map<String, dynamic>> updateItem(
      String id, Map<String, dynamic> data) async {
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

  Future<Map<String, dynamic>> restoreItem(
      String id, String containerId, int? slotNumber) async {
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
  Future<Map<String, dynamic>> createOutwardMovement(
      Map<String, dynamic> data) async {
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

  Future<Map<String, dynamic>> getOutwardMovements(
      {String? status, String? movementType}) async {
    String url = '${AppConstants.baseUrl}/outward-movements';
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (movementType != null) params['movementType'] = movementType;

    final uri = Uri.parse(url)
        .replace(queryParameters: params.isNotEmpty ? params : null);
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

  Future<Map<String, dynamic>> updateBooking(
      String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/bookings/$id'),
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

  Future<Map<String, dynamic>> removeFromWishlist(
      String mobile, String itemId) async {
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
  Future<Map<String, dynamic>> createItemWithImages(
      Map<String, String> fields, List<XFile> images) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/items');
    final request = http.MultipartRequest('POST', uri);
    return _sendMultipartRequest(request, fields, images);
  }

  // Update item with images (Multipart)
  Future<Map<String, dynamic>> updateItemWithImages(
      String id, Map<String, String> fields, List<XFile> images) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/items/$id');
    final request = http.MultipartRequest('PUT', uri);
    return _sendMultipartRequest(request, fields, images);
  }

  // Helper for multipart requests
  Future<Map<String, dynamic>> _sendMultipartRequest(
      http.MultipartRequest request,
      Map<String, String> fields,
      List<XFile> images) async {
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
      if (image.name.toLowerCase().endsWith('.jpg') ||
          image.name.toLowerCase().endsWith('.jpeg')) {
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
  Future<Map<String, dynamic>> tallyPreview() async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/tally/preview'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> tallySummary(String id) async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/tally/$id/summary'), headers: await _getHeaders()));

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
  Future<Map<String, dynamic>> scanItemInTally(
      String tallyId, String barcode) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/scan'),
      headers: await _getHeaders(),
      body: json.encode({'barcode': barcode}),
    );
    return _handleResponse(response);
  }

  // Verify weight for approx/bulk items during tally
  Future<Map<String, dynamic>> verifyTallyWeight(
      String tallyId, String itemId, double verifiedWeight) async {
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
  Future<Map<String, dynamic>> lockTally(String tallyId,
      {String? remarks}) async {
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

  // Remove a single unscanned item from stock + tally (admin only)
  Future<Map<String, dynamic>> removeUnscannedTallyItem(
      String tallyId, String itemId) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/remove-item'),
      headers: await _getHeaders(),
      body: json.encode({'itemId': itemId}),
    );
    return _handleResponse(response);
  }

  // Remove all (or a subset of) unscanned items from stock + tally (admin only)
  Future<Map<String, dynamic>> removeAllUnscannedTallyItems(String tallyId,
      {List<String>? itemIds}) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/remove-unscanned'),
      headers: await _getHeaders(),
      body: json.encode({if (itemIds != null) 'itemIds': itemIds}),
    );
    return _handleResponse(response);
  }

  // Add a just-created item into an active tally (as expected + scanned)
  Future<Map<String, dynamic>> addItemToTally(
      String tallyId, String barcode) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/add-item'),
      headers: await _getHeaders(),
      body: json.encode({'barcode': barcode}),
    );
    return _handleResponse(response);
  }

  // Generate a saved inventory snapshot from a locked tally
  Future<Map<String, dynamic>> updateTallyInventory(String tallyId) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/tally/$tallyId/update-inventory'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Get inventory snapshot history
  Future<Map<String, dynamic>> getInventorySnapshots() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/inventory-snapshots'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Get single inventory snapshot
  Future<Map<String, dynamic>> getInventorySnapshot(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/inventory-snapshots/$id'),
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
        throw Exception(
            'Failed to generate PDF: ${response.statusCode} - $errorBody');
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
  Future<Map<String, dynamic>> uploadImage(XFile imageFile,
      {String folder = 'items'}) async {
    try {
      final token = await _storage.getToken();
      // Add folder query parameter
      final uri =
          Uri.parse('${AppConstants.baseUrl}/upload/single?folder=$folder');

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
      final publicId =
          publicIdWithExt.substring(0, publicIdWithExt.lastIndexOf('.'));

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
  Future<Map<String, dynamic>> updateUser(
      String id, Map<String, dynamic> userData) async {
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
  Future<Map<String, dynamic>> changePassword(
      String userId, String currentPassword, String newPassword) async {
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

  // Admin reset of another user's password (no current password needed)
  Future<Map<String, dynamic>> resetPassword(
      String userId, String newPassword) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/users/$userId/reset-password'),
      headers: await _getHeaders(),
      body: json.encode({'newPassword': newPassword}),
    );
    return _handleResponse(response);
  }

  // Set/clear one user's individual permission overrides (admin only)
  Future<Map<String, dynamic>> updateUserPermissionOverrides(
      String userId, Map<String, bool?> overrides) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/users/$userId/permission-overrides'),
      headers: await _getHeaders(),
      body: json.encode({'overrides': overrides}),
    );
    return _handleResponse(response);
  }

  // ── Roles & Permissions ─────────────────────────────────────────────────────
  // The full permission taxonomy (groups + keys + labels)
  Future<Map<String, dynamic>> getPermissionDefinitions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/permissions/definitions'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // The caller's own effective permission map
  Future<Map<String, dynamic>> getMyPermissions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/permissions/me'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // All role permission grids (admin only)
  Future<Map<String, dynamic>> getRolePermissionGrids() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/permissions/roles'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // Update one role's permission grid (admin only)
  Future<Map<String, dynamic>> updateRolePermissionGrid(
      String role, Map<String, bool> permissions) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/permissions/roles/$role'),
      headers: await _getHeaders(),
      body: json.encode({'permissions': permissions}),
    );
    return _handleResponse(response);
  }

  // Tag Settings
  Future<Map<String, dynamic>> getTagSettings() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/tag-settings'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateTagSettings(
      Map<String, dynamic> data) async {
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
      print(
          '[API] Blank Tags PDF response length: ${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        print('[API] Returning ${bytes.length} bytes for blank tags PDF');
        return bytes;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        print('[API] Error response: $errorBody');
        throw Exception(
            'Failed to generate blank tags PDF: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[API] Exception generating blank tags PDF: $e');
      rethrow;
    }
  }

  // ==================== STORE MANAGEMENT APIs ====================

  // ── Stock Dashboard & Bulk Weights ──────────────────────────────────────

  Future<Map<String, dynamic>> getStockDashboard() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/stock/dashboard'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getBulkWeights({String? metalType}) async {
    var uri = Uri.parse('${AppConstants.baseUrl}/stock/bulk-weights');
    if (metalType != null) {
      uri = uri.replace(queryParameters: {'metalType': metalType});
    }
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addBulkWeight(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/stock/bulk-weights'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateBulkWeight(
      String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/stock/bulk-weights/$id'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteBulkWeight(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/stock/bulk-weights/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getStockDailySummary({
    String? startDate,
    String? endDate,
    String? metalType,
  }) async {
    final params = <String, String>{};
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    if (metalType != null) params['metalType'] = metalType;
    final uri = Uri.parse('${AppConstants.baseUrl}/stock/daily-summary')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getStockReconciliation() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/stock/reconciliation'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // ── Stock Summary (metal balance and difference), history, snapshot ─────

  Future<Map<String, dynamic>> getStockSummary() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/stock/summary'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSummaryMovements({int limit = 30}) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/stock/summary/movements?limit=$limit'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> saveStockSnapshot() async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/stock/summary/snapshot'),
      headers: await _getHeaders(),
      body: json.encode({}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSummaryHistory(
      {String view = 'daily', String? from, String? to}) async {
    final params = <String, String>{'view': view};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final uri = Uri.parse('${AppConstants.baseUrl}/stock/summary/history')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  // ── Wastage reports ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getWastageReports(
      {String? status, String? metal, int page = 1, int limit = 20}) async {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (metal != null && metal.isNotEmpty) params['metal'] = metal;
    final uri = Uri.parse('${AppConstants.baseUrl}/stock/wastage')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getWastageReport(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/stock/wastage/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> createWastage(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/stock/wastage'),
      headers: await _getHeaders(),
      body: json.encode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateWastage(
      String id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/stock/wastage/$id'),
      headers: await _getHeaders(),
      body: json.encode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> approveWastage(String id, String comment) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/stock/wastage/$id/approve'),
      headers: await _getHeaders(),
      body: json.encode({'comment': comment}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> rejectWastage(String id, String comment) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/stock/wastage/$id/reject'),
      headers: await _getHeaders(),
      body: json.encode({'comment': comment}),
    );
    return _handleResponse(response);
  }

  // ── Purchases ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPurchases({
    String? metalType,
    String? biller,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
    String sort = 'date_desc',
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'sort': sort,
    };
    if (metalType != null) params['metalType'] = metalType;
    if (biller != null) params['biller'] = biller;
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;

    final uri = Uri.parse('${AppConstants.baseUrl}/purchases')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getPurchase(String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/purchases/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> createPurchase(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/purchases'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updatePurchase(
      String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/purchases/$id'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deletePurchase(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/purchases/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> previewPurchaseGst({
    required double totalAmount,
    String transactionType = 'intra-state',
  }) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/purchases/preview-gst')
        .replace(queryParameters: {
      'totalAmount': totalAmount.toString(),
      'transactionType': transactionType,
    });
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  // ── GST ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGstConfig() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/gst/config'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateGstConfig(
      Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/gst/config'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> calculateGst({
    required double baseAmount,
    String transactionType = 'intra-state',
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/gst/calculate'),
      headers: await _getHeaders(),
      body: json.encode({
        'baseAmount': baseAmount,
        'transactionType': transactionType,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> validateGstin(String gstin) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/gst/validate-gstin'),
      headers: await _getHeaders(),
      body: json.encode({'gstin': gstin}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> validatePan(String pan) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/gst/validate-pan'),
      headers: await _getHeaders(),
      body: json.encode({'pan': pan}),
    );
    return _handleResponse(response);
  }

  // ── Purchase Bill Attachment Upload ─────────────────────────────────────────

  /// Uploads a single purchase bill (image or PDF) to Cloudinary via the backend.
  /// [filePath] absolute path to the file on device.
  /// [mimeType] e.g. 'image/jpeg' or 'application/pdf'.
  /// Returns { url, publicId, originalName, format }
  Future<Map<String, dynamic>> uploadPurchaseBill({
    required String filePath,
    required String mimeType,
    required String originalName,
  }) async {
    final token = await _storage.getToken();
    final uri = Uri.parse('${AppConstants.baseUrl}/purchases/upload-bill');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'attachment',
        filePath,
        contentType: MediaType.parse(mimeType),
      ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  /// Deletes a Cloudinary purchase bill attachment by its publicId.
  Future<Map<String, dynamic>> deletePurchaseBillAttachment(
      String publicId) async {
    // Replace / with -- so it's URL-safe (same as main upload routes)
    final safeId = publicId.replaceAll('/', '--');
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/purchases/attachment/$safeId'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Fetches autocomplete suggestions (suppliers, GSTINs, descriptions).
  Future<Map<String, dynamic>> getPurchaseSuggestions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/purchases/suggestions'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Fetches quarterly ITC summary for a financial year.
  /// [fy] — e.g. '2025-26'. Defaults to current FY on backend.
  Future<Map<String, dynamic>> getItcSummary({String? fy}) async {
    final params = fy != null ? '?fy=$fy' : '';
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/purchases/itc-summary$params'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  // ── App Version (update nudge) ─────────────────────────────────────────────
  // Public endpoint — checked at splash, before login is guaranteed.
  Future<Map<String, dynamic>> getAppVersion() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/app-version'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateAppVersion(
      Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/app-version'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  // ── Presence ("I'm here, on this screen") for the website's Staff & Roles > Live now ──────
  // Best-effort only: a missed heartbeat must never surface as an error anywhere in the app.
  Future<void> pingPresence({required String screen}) async {
    try {
      await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/presence/ping'),
            headers: await _getHeaders(),
            body: json.encode({'platform': 'app', 'screen': screen}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // no connection, or the server is asleep — the next scheduled ping tries again
    }
  }

  // ── Push Notifications ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerFcmToken(String token,
      {String platform = 'android'}) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/users/fcm-token'),
      headers: await _getHeaders(),
      body: json.encode({'token': token, 'platform': platform}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> sendNotification(
      Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/notifications/send'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getNotificationHistory() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/notifications'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }
  // ── User Directory (customers / staff / suppliers / karigars) ─────────────

  Future<Map<String, dynamic>> getDirectorySummary() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/summary'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Type-ahead over customers by phone digits, customer code or name. Used for
  /// live duplicate detection and the "referred by" picker.
  Future<Map<String, dynamic>> lookupCustomers(String q, {String? exclude}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/directory/customers/lookup')
        .replace(queryParameters: {'q': q, if (exclude != null) 'exclude': exclude});
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  /// English -> Bengali for a customer's name / nickname / address (server-side).
  Future<Map<String, dynamic>> translateToBengali(Map<String, String> texts) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/directory/translate'),
      headers: await _getHeaders(),
      body: json.encode(texts),
    );
    return _handleResponse(response);
  }

  /// Pincode -> state / district / city. Throws when not found.
  Future<Map<String, dynamic>> lookupPincode(String pin) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/lookup/pincode/$pin'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// IFSC -> bank / branch / city. Throws when not found.
  Future<Map<String, dynamic>> lookupIfsc(String code) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/lookup/ifsc/$code'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Guarded update of a directory record. Like [createDirectoryRecord] it does
  /// not throw on 4xx: check `success`, `statusCode` and `conflict`.
  /// [path] is e.g. `customers/<id>` or `staff/profile/<id>`.
  Future<Map<String, dynamic>> updateDirectoryRecord(
      String path, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/directory/$path'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      body['statusCode'] = response.statusCode;
      return body;
    } catch (_) {
      throw Exception('Unexpected server response (${response.statusCode})');
    }
  }

  /// Who changed this record, and how (newest first).
  Future<Map<String, dynamic>> getDirectoryHistory(String entity, String id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/history/$entity/$id'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Branches / shops (includes the built-in "main" branch as the first item).
  Future<Map<String, dynamic>> getDirectoryBranches() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/branches'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// [kind] is one of: customers, staff, suppliers, karigars.
  Future<Map<String, dynamic>> getDirectoryList(
    String kind, {
    String q = '',
    int page = 1,
    int limit = 25,
  }) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/directory/$kind').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'page': '$page',
        'limit': '$limit',
      },
    );
    final response = await http.get(uri, headers: await _getHeaders());
    return _handleResponse(response);
  }

  /// [path] is the record path after /directory/, e.g. `customers/<id>` or
  /// `staff/login/<id>`.
  Future<Map<String, dynamic>> getDirectoryRecord(String path) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/directory/$path'),
      headers: await _getHeaders(),
    );
    return _handleResponse(response);
  }

  /// Insert-only. Unlike other calls this does not throw on 4xx so the UI can
  /// react to a 409 duplicate warning; check `success` and `statusCode`.
  Future<Map<String, dynamic>> createDirectoryRecord(
      String kind, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/directory/$kind'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      body['statusCode'] = response.statusCode;
      return body;
    } catch (_) {
      throw Exception('Unexpected server response (${response.statusCode})');
    }
  }
  // ── GST billing ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> billingMeta() async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/billing/meta'),
      headers: await _getHeaders()));

  Future<Map<String, dynamic>> billingStats({String? from, String? to}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/billing/stats').replace(
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to});
    return _handleResponse(await http.get(uri, headers: await _getHeaders()));
  }

  /// Balances shown while billing a saved customer (wallet, due, recent bills).
  Future<Map<String, dynamic>> billingCustomerSummary(String customerId) async =>
      _handleResponse(await http.get(
          Uri.parse('${AppConstants.baseUrl}/billing/customer/$customerId'),
          headers: await _getHeaders()));

  Future<Map<String, dynamic>> billingList(
      {String q = '', String status = 'all', int page = 1, int limit = 20}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/billing/invoices').replace(
        queryParameters: {
      if (q.isNotEmpty) 'q': q,
      'status': status,
      'page': '$page',
      'limit': '$limit',
    });
    return _handleResponse(await http.get(uri, headers: await _getHeaders()));
  }

  Future<Map<String, dynamic>> billingInvoice(String id) async => _handleResponse(
      await http.get(Uri.parse('${AppConstants.baseUrl}/billing/invoices/$id'),
          headers: await _getHeaders()));

  /// Saves an invoice. Does not throw on 4xx (so the screen can show the
  /// server's message); check `success`. Safe to retry with the same
  /// `requestId`: the server will never create a second invoice.
  Future<Map<String, dynamic>> billingCreate(Map<String, dynamic> body) async =>
      _postTolerant('${AppConstants.baseUrl}/billing/invoices', body);

  /// How much cash can still be taken today from this customer / mobile (Income Tax Act s.269ST: below Rs 2,00,000 a day).
  Future<Map<String, dynamic>> billingCashToday({String customerId = '', String mobile = ''}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/billing/cash-today').replace(queryParameters: {
      if (customerId.isNotEmpty) 'customerId': customerId,
      if (mobile.isNotEmpty) 'mobile': mobile,
    });
    return _handleResponse(await http.get(uri, headers: await _getHeaders()));
  }

  /// Counts a print on the server (shared with the website): ORIGINAL first, then DUPLICATE.
  Future<Map<String, dynamic>> billingPrint(String id) async =>
      _postTolerant('${AppConstants.baseUrl}/billing/invoices/$id/print', {});

  Future<Map<String, dynamic>> billingPay(String id, Map<String, dynamic> body) async =>
      _postTolerant('${AppConstants.baseUrl}/billing/invoices/$id/payments', body);

  /// Making charge per gram of the last sale of the same kind of piece (Stock Setting rule "last entry").
  Future<Map<String, dynamic>> billingLastMaking({required String name, String metal = '', bool userWise = false}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/billing/last-making').replace(queryParameters: {'name': name, if (metal.isNotEmpty) 'metal': metal, if (userWise) 'userWise': '1'});
    return _handleResponse(await http.get(uri, headers: await _getHeaders()));
  }

  // ── Credit notes (returns / refunds) ───────────────────────────────────────
  Future<Map<String, dynamic>> creditNoteState(String invoiceId) async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/credit-notes/invoice/$invoiceId'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> creditNotePreview(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/credit-notes/preview', body);
  Future<Map<String, dynamic>> creditNoteCreate(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/credit-notes', body);

  // ── Old metal / raw metal ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> oldMetalList({String kind = '', String q = '', String used = '', String status = ''}) async {
    final qp = {if (kind.isNotEmpty) 'kind': kind, if (q.isNotEmpty) 'q': q, if (used.isNotEmpty) 'used': used, if (status.isNotEmpty) 'status': status};
    return _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/old-metal').replace(queryParameters: qp.isEmpty ? null : qp), headers: await _getHeaders()));
  }

  /// Received old metal of this customer that is not yet adjusted on a bill.
  Future<Map<String, dynamic>> oldMetalAvailable({String customerId = '', String mobile = '', String name = ''}) async {
    final qp = {if (customerId.isNotEmpty) 'customerId': customerId, if (mobile.isNotEmpty) 'mobile': mobile, if (name.isNotEmpty) 'name': name};
    return _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/old-metal/available').replace(queryParameters: qp), headers: await _getHeaders()));
  }
  Future<Map<String, dynamic>> oldMetalCreate(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/old-metal', body);
  Future<Map<String, dynamic>> oldMetalCancel(String id) => _sendTolerant('POST', '${AppConstants.baseUrl}/old-metal/$id/cancel', {});

  // ── Stock Setting (valuation / wastage / labour rules) ─────────────────────
  Future<Map<String, dynamic>> stockSettings() async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/stock-settings'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> stockSettingsSave(Map<String, dynamic> changes) => _sendTolerant('PUT', '${AppConstants.baseUrl}/stock-settings', changes);
  Future<Map<String, dynamic>> stockSettingsReset() => _sendTolerant('POST', '${AppConstants.baseUrl}/stock-settings/reset', {});

  // ── Customer orders ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> orders({String q = '', String status = ''}) async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/orders').replace(queryParameters: {if (q.isNotEmpty) 'q': q, if (status.isNotEmpty) 'status': status}), headers: await _getHeaders()));
  Future<Map<String, dynamic>> order(String id) async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/orders/$id'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> orderCreate(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/orders', body);
  Future<Map<String, dynamic>> orderAdvance(String id, Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/orders/$id/advance', body);
  Future<Map<String, dynamic>> orderStatus(String id, Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/orders/$id/status', body);
  Future<Map<String, dynamic>> orderCancel(String id, Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/orders/$id/cancel', body);

  // ── Estimates (price quotations) ───────────────────────────────────────────
  Future<Map<String, dynamic>> estimates({String q = '', String status = ''}) async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/estimates').replace(queryParameters: {if (q.isNotEmpty) 'q': q, if (status.isNotEmpty) 'status': status}), headers: await _getHeaders()));
  Future<Map<String, dynamic>> estimate(String id) async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/estimates/$id'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> estimateCreate(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/estimates', body);
  Future<Map<String, dynamic>> estimateConverted(String id, String invoiceNumber) => _sendTolerant('POST', '${AppConstants.baseUrl}/estimates/$id/converted', {'invoiceNumber': invoiceNumber});
  Future<Map<String, dynamic>> estimateCancel(String id) async => _handleResponse(await http.delete(Uri.parse('${AppConstants.baseUrl}/estimates/$id'), headers: await _getHeaders()));

  // ── Today's rate, expenses, Day Book, pending dues ─────────────────────────
  Future<Map<String, dynamic>> rates() async => _handleResponse(await http.get(Uri.parse('${AppConstants.baseUrl}/rates'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> ratesSave(Map<String, dynamic> body) => _sendTolerant('PUT', '${AppConstants.baseUrl}/rates', body);
  Future<Map<String, dynamic>> expenses({String? from, String? to}) async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/expenses').replace(queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to}), headers: await _getHeaders()));
  Future<Map<String, dynamic>> expenseCreate(Map<String, dynamic> body) => _sendTolerant('POST', '${AppConstants.baseUrl}/expenses', body);
  Future<Map<String, dynamic>> expenseCancel(String id) async => _handleResponse(await http.delete(Uri.parse('${AppConstants.baseUrl}/expenses/$id'), headers: await _getHeaders()));
  Future<Map<String, dynamic>> billingDues({String q = ''}) async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/billing/dues').replace(queryParameters: {if (q.isNotEmpty) 'q': q}), headers: await _getHeaders()));
  Future<Map<String, dynamic>> billingDayBook({String? from, String? to}) async => _handleResponse(await http.get(
      Uri.parse('${AppConstants.baseUrl}/billing/daybook').replace(queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to}), headers: await _getHeaders()));

  // ── GST Summary (reports, returns, ITC, due dates, filings) ────────────────
  /// `one`: the call belongs to a single GSTIN, so "all registrations" falls back to the firm's default one.
  Map<String, String> _gstScope(Map<String, String>? q, {bool one = false}) => {
        ...?q,
        if (activeGstin.isNotEmpty && !(one && activeGstin == 'ALL')) 'gstin': activeGstin,
      };

  Future<Map<String, dynamic>> _gstGet(String path, {Map<String, String>? q, bool one = false}) async {
    final scoped = _gstScope(q, one: one);
    final uri = Uri.parse('${AppConstants.baseUrl}/gst-reports/$path').replace(queryParameters: scoped.isEmpty ? null : scoped);
    return _handleResponse(await http.get(uri, headers: await _getHeaders()));
  }

  String _gstUrl(String path) {
    final g = _gstScope(null, one: true)['gstin'];
    return '${AppConstants.baseUrl}/gst-reports/$path${g == null ? '' : '?gstin=${Uri.encodeQueryComponent(g)}'}';
  }

  Future<Map<String, dynamic>> gstSettings() => _gstGet('settings');
  Future<Map<String, dynamic>> gstSummary(Map<String, String> q) => _gstGet('summary', q: q);
  Future<Map<String, dynamic>> gstRegister(Map<String, String> q) => _gstGet('register', q: q);
  Future<Map<String, dynamic>> gstReturns(String period) => _gstGet('returns', q: {'period': period}, one: true);
  Future<Map<String, dynamic>> gstItc() => _gstGet('itc', one: true);
  Future<Map<String, dynamic>> gstCalendar() => _gstGet('calendar', one: true);
  Future<Map<String, dynamic>> gstFilings() => _gstGet('filings', one: true);
  Future<Map<String, dynamic>> gstExport(Map<String, String> q) => _gstGet('export', q: q);

  /// Every invoice of one month plus its totals: the data behind the printable "GST Invoice Record".
  Future<Map<String, dynamic>> gstMonthlyRecord(int year, int month) => _gstGet('monthly-record', q: {'year': '$year', 'month': '$month'}, one: true);

  Future<Map<String, dynamic>> gstUpdateSettings(Map<String, dynamic> body) => _sendTolerant('PUT', _gstUrl('settings'), body);
  Future<Map<String, dynamic>> gstCreateFiling(Map<String, dynamic> body) => _sendTolerant('POST', _gstUrl('filings'), body);
  Future<Map<String, dynamic>> gstUpdateFiling(String id, Map<String, dynamic> body) => _sendTolerant('PUT', _gstUrl('filings/$id'), body);

  Future<Map<String, dynamic>> _sendTolerant(String method, String url, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = method == 'PUT'
        ? await http.put(Uri.parse(url), headers: headers, body: json.encode(body))
        : await http.post(Uri.parse(url), headers: headers, body: json.encode(body));
    try {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      decoded['statusCode'] = response.statusCode;
      return decoded;
    } catch (_) {
      throw Exception('Unexpected server response (${response.statusCode})');
    }
  }

  Future<Map<String, dynamic>> _postTolerant(String url, Map<String, dynamic> body) async {
    final response = await http.post(Uri.parse(url),
        headers: await _getHeaders(), body: json.encode(body));
    try {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      decoded['statusCode'] = response.statusCode;
      return decoded;
    } catch (_) {
      throw Exception('Unexpected server response (${response.statusCode})');
    }
  }
}
