import 'package:no_lean/features/recovery/domain/daily_check_in.dart';
import 'package:no_lean/features/recovery/services/check_in_inbox.dart';

/// In-memory inbox with the same drain / acknowledge contract as the file one.
class MemoryCheckInInbox implements CheckInInbox {
  final pending = <CheckInEntry>[];
  List<CheckInEntry> _draining = [];

  @override
  Future<void> append(CheckInEntry entry) async => pending.add(entry);

  @override
  Future<List<CheckInEntry>> drain() async {
    _draining = [..._draining, ...pending];
    pending.clear();
    return List.of(_draining);
  }

  @override
  Future<void> acknowledge() async => _draining = [];
}
