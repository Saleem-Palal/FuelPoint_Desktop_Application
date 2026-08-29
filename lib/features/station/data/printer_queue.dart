import '../domain/dispenser_models.dart';

/// FIFO thermal printer queue. Jobs are held locally until a printer claims them.
class PrinterQueue {
  final List<PrintJob> _jobs = <PrintJob>[];

  List<PrintJob> get pending => List<PrintJob>.unmodifiable(_jobs);

  void enqueue(SaleTransaction transaction) {
    _jobs.add(PrintJob(transaction: transaction, queuedAt: DateTime.now()));
  }

  PrintJob? takeNext() {
    if (_jobs.isEmpty) {
      return null;
    }
    return _jobs.removeAt(0);
  }

  void clear() {
    _jobs.clear();
  }
}
