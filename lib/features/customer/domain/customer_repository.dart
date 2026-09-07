import 'customer_models.dart';

abstract class CustomerDirectoryRepository {
  Future<List<CustomerProfile>> list();

  Future<Map<String, CustomerProfile>> idCache();

  Future<CustomerProfile?> byId(String id);

  Future<CustomerProfile?> byName(String name);

  Future<String> nextId();

  Future<CustomerProfile> add({required String name, String phone = ''});
}

abstract class UnifiedUdhaarRepository {
  Future<List<UnifiedUdhaarRow>> list();

  Future<List<UnifiedUdhaarRow>> forCustomerId(String customerId);

  Future<double> remainingFor(String customerId);

  Future<int> nextReceiptSeq();

  Future<UnifiedUdhaarRow> insertSettlement({
    required String customerId,
    required String customerName,
    required double amountPkr,
    required SettlementPaymentMode paymentMode,
    required String shiftId,
    String notes = '',
    DateTime? timestamp,
  });
}
