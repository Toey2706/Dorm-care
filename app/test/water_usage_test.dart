import 'package:dorm_care_staff/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('th'));

  final receivedAt = DateTime.utc(2026, 11, 19, 17, 0, 2);
  final ready = {
    'state': 'ready',
    'flow_lpm': 0,
    'total_liters_since_boot': 12.345,
    'received_at_ms': receivedAt.millisecondsSinceEpoch,
    'stale': true,
  };

  test('reads the latest telemetry and stale state', () {
    final reading = WaterUsage.fromJson(ready) as WaterReading;
    expect(reading.flowLpm, 0);
    expect(reading.totalLiters, 12.345);
    expect(reading.receivedAt, receivedAt);
    expect(reading.stale, isTrue);
  });

  test('distinguishes a missing meter from a meter without telemetry', () {
    final unconfigured =
        WaterUsage.fromJson({'state': 'unconfigured'}) as WaterUnavailable;
    final noData =
        WaterUsage.fromJson({'state': 'no_data'}) as WaterUnavailable;
    expect(unconfigured.isConfigured, isFalse);
    expect(noData.isConfigured, isTrue);
  });

  test('rejects an invalid reading instead of displaying a fabricated value',
      () {
    expect(() => WaterUsage.fromJson({...ready, 'flow_lpm': -1}),
        throwsFormatException);
    expect(() => WaterUsage.fromJson({...ready, 'received_at_ms': null}),
        throwsFormatException);
  });

  test('shows Bangkok date and seconds even in another device time zone', () {
    expect(
      thaiDate(receivedAt,
          utcOffset: const Duration(hours: 7), showSeconds: true),
      '20 พ.ย. 2569 · 00:00:02',
    );
  });
}
