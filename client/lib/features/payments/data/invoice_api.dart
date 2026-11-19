import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../models/invoice_model.dart';

class InvoiceListResult {
  const InvoiceListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  final List<InvoiceModel> items;
  final int total;
  final int page;
  final int totalPages;
}

abstract final class InvoiceApi {
  static Future<InvoiceListResult> list({
    int page = 1,
    int limit = 10,
    String? customerId,
    String? paymentStatus,
    String? month,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (customerId != null) query['customerId'] = customerId;
    if (paymentStatus != null) query['paymentStatus'] = paymentStatus;
    if (month != null) query['month'] = month;

    final response = await DioClient.instance.get(
      ApiEndpoints.invoices,
      queryParameters: query,
    );

    final data = parseData(response); // returns { data: [...], total: N }
    List<dynamic> rawList = [];
    var total = 0;
    var currentPage = page;
    var totalPages = 1;
    if (data is Map<String, dynamic>) {
      rawList = (data['data'] as List?) ??
                (data['invoices'] as List?) ?? [];
      total = (data['total'] as num?)?.toInt() ?? rawList.length;
      currentPage = (data['page'] as num?)?.toInt() ?? page;
      totalPages = (data['totalPages'] as num?)?.toInt() ??
          (total == 0 ? 1 : ((total + limit - 1) ~/ limit));
    } else if (data is List) {
      rawList = data;
      total = rawList.length;
    }

    final items = rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => InvoiceModel.fromJson(e))
        .toList();
    return InvoiceListResult(
      items: items,
      total: total,
      page: currentPage,
      totalPages: totalPages,
    );
  }

  static Future<List<InvoiceModel>> getOverdue() async {
    final response = await DioClient.instance.get(
      ApiEndpoints.invoicesOverdue,
    );

    final data = parseData(response);
    List<dynamic> rawList = [];
    if (data is Map<String, dynamic>) {
      rawList = (data['data'] as List?) ??
                (data['invoices'] as List?) ?? [];
    } else if (data is List) {
      rawList = data;
    }

    return rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => InvoiceModel.fromJson(e))
        .toList();
  }

  static Future<InvoiceModel> getById(String id) async {
    final response = await DioClient.instance.get(
      ApiEndpoints.invoiceById(id),
    );
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    return InvoiceModel.fromJson(data);
  }

  static Future<InvoiceModel> generate({
    required String customerId,
    required DateTime billingStart,
    required DateTime billingEnd,
    String? subscriptionId,
  }) async {
    final response = await DioClient.instance.post(
      ApiEndpoints.invoicesGenerate,
      data: {
        'customerId': customerId,
        'billingStart': _calendarDay(billingStart),
        'billingEnd': _calendarDay(billingEnd),
        'subscriptionId': ?subscriptionId,
      },
    );
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    return InvoiceModel.fromJson(data);
  }

  static Future<InvoiceModel> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await DioClient.instance.put(
      ApiEndpoints.invoiceById(id),
      data: body,
    );
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    return InvoiceModel.fromJson(data);
  }

  static Future<String> share(String id) async {
    final response = await DioClient.instance.post(
      ApiEndpoints.invoiceShare(id),
    );
    final data = parseData(response);
    if (data is Map<String, dynamic>) {
      final url = data['shareUrl'] ?? data['url'];
      if (url != null && url.toString().trim().isNotEmpty) {
        return url.toString();
      }
    }
    return '';
  }

  static Future<void> voidInvoice(String id) async {
    await DioClient.instance.post(ApiEndpoints.invoiceVoid(id));
  }

  /// Daily meal receipt for a customer (GET /invoices/daily).
  static Future<Map<String, dynamic>> getDailyReceipt({
    required String customerId,
    required DateTime date,
  }) async {
    try {
      final ds =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final response = await DioClient.instance.get(
        ApiEndpoints.invoicesDaily,
        queryParameters: {'customerId': customerId, 'date': ds},
      );
      final data = parseData(response);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw ApiException('Invalid response');
    } catch (e) {
      rethrow;
    }
  }
}

/// Local calendar day, so an IST date picker does not shift back to the previous UTC day.
String _calendarDay(DateTime date) {
  final local = date.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}