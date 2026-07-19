import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/location_point.dart';

LocationPoint _pointUpdatedSecondsAgo(int seconds) {
  return LocationPoint(
    userId: 'u1',
    displayName: 'Test',
    lat: 0,
    lng: 0,
    heading: 0,
    speed: 0,
    updatedAt: Timestamp.fromDate(DateTime.now().subtract(Duration(seconds: seconds))),
  );
}

void main() {
  group('LocationPoint.status', () {
    test('is live at 0s', () {
      expect(_pointUpdatedSecondsAgo(0).status, SignalStatus.live);
    });

    test('is live at the 15s boundary (inclusive)', () {
      expect(_pointUpdatedSecondsAgo(15).status, SignalStatus.live);
    });

    test('is weak just past the live boundary', () {
      expect(_pointUpdatedSecondsAgo(16).status, SignalStatus.weak);
    });

    test('is weak at the 60s boundary (inclusive)', () {
      expect(_pointUpdatedSecondsAgo(60).status, SignalStatus.weak);
    });

    test('is lost just past the weak boundary', () {
      expect(_pointUpdatedSecondsAgo(61).status, SignalStatus.lost);
    });

    test('is lost well past the weak boundary', () {
      expect(_pointUpdatedSecondsAgo(3600).status, SignalStatus.lost);
    });
  });

  group('LocationPoint.isStale', () {
    test('is false while live', () {
      expect(_pointUpdatedSecondsAgo(0).isStale, false);
    });

    test('is true once weak or lost', () {
      expect(_pointUpdatedSecondsAgo(16).isStale, true);
      expect(_pointUpdatedSecondsAgo(61).isStale, true);
    });
  });

  group('LocationPoint.lastSeenLabel', () {
    test('"Just now" for under 5s', () {
      expect(_pointUpdatedSecondsAgo(0).lastSeenLabel, 'Just now');
      expect(_pointUpdatedSecondsAgo(4).lastSeenLabel, 'Just now');
    });

    test('seconds label between 5s and 1 minute', () {
      expect(_pointUpdatedSecondsAgo(5).lastSeenLabel, '5s ago');
      expect(_pointUpdatedSecondsAgo(59).lastSeenLabel, '59s ago');
    });

    test('minutes label between 1 minute and 1 hour', () {
      expect(_pointUpdatedSecondsAgo(60).lastSeenLabel, '1m ago');
      expect(_pointUpdatedSecondsAgo(125).lastSeenLabel, '2m ago');
    });

    test('hours label beyond 1 hour', () {
      expect(_pointUpdatedSecondsAgo(3600).lastSeenLabel, '1h ago');
      expect(_pointUpdatedSecondsAgo(7260).lastSeenLabel, '2h ago');
    });
  });

  group('LocationPoint.fromDoc / toMap', () {
    test('toMap includes the fields written to Firestore', () {
      final point = _pointUpdatedSecondsAgo(0);
      final map = point.toMap();

      expect(map['displayName'], 'Test');
      expect(map['lat'], 0);
      expect(map['lng'], 0);
      expect(map['heading'], 0);
      expect(map['speed'], 0);
      expect(map.containsKey('updatedAt'), true);
    });
  });
}
