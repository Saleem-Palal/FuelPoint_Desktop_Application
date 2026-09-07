import '../../../services/database_helper.dart';
import '../domain/customer_models.dart';
import '../domain/customer_repository.dart';

class SqliteCustomerDirectoryRepository implements CustomerDirectoryRepository {
  SqliteCustomerDirectoryRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  @override
  Future<List<CustomerProfile>> list() async {
    final List<Map<String, Object?>> rows = await _db.queryCustomers();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Map<String, CustomerProfile>> idCache() async {
    final List<CustomerProfile> rows = await list();
    return <String, CustomerProfile>{
      for (final CustomerProfile row in rows) row.id: row,
    };
  }

  @override
  Future<CustomerProfile?> byId(String id) async {
    final String key = normalizeCustomerIdQuery(id);
    final String lookup = key.isEmpty ? id.trim() : key;
    if (lookup.isEmpty) {
      return null;
    }
    final Map<String, Object?>? row = await _db.queryCustomerById(lookup);
    if (row == null) {
      return null;
    }
    return _fromRow(row);
  }

  @override
  Future<CustomerProfile?> byName(String name) async {
    if (isWalkInCustomer(name)) {
      return null;
    }
    final Map<String, Object?>? row = await _db.queryCustomerByName(name);
    if (row == null) {
      return null;
    }
    return _fromRow(row);
  }

  @override
  Future<String> nextId() async {
    return formatCustomerId(await _db.nextCustomerSequence());
  }

  @override
  Future<CustomerProfile> add({required String name, String phone = ''}) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Customer name is required');
    }
    final CustomerProfile? duplicate = await byName(trimmed);
    if (duplicate != null) {
      return duplicate;
    }
    final CustomerProfile next = CustomerProfile(
      id: await nextId(),
      name: trimmed,
      phone: phone.trim(),
      createdAt: DateTime.now(),
    );
    await _db.upsertCustomer(id: next.id, name: next.name);
    return next;
  }

  static CustomerProfile _fromRow(Map<String, Object?> row) {
    return CustomerProfile(
      id: '${row['customer_ID'] ?? ''}'.trim(),
      name: '${row['Customer_Name'] ?? ''}'.trim(),
    );
  }
}
