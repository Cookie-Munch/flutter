// Tests the pure-Dart Cookie Munch core. No Flutter binding, no real network:
// the HTTP layer is mocked with package:http/testing MockClient, and storage is
// in-memory (or a temp file). Runs under `dart test` and `flutter test` alike.
import 'dart:convert';
import 'dart:io';

import 'package:cookie_munch/cookie_munch_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A MockClient that records every request and returns 204.
class _Recorder {
  final List<http.Request> requests = [];
  final List<Map<String, String>> headers = [];
  final List<Map<String, dynamic>> bodies = [];
  bool fail = false;

  MockClient get client => MockClient((req) async {
        requests.add(req);
        headers.add(req.headers);
        if (req.body.isNotEmpty) {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        if (fail) throw const SocketExceptionLike();
        return http.Response('', 204);
      });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

CookieMunchConsent make({
  ConsentStorage? storage,
  http.Client? httpClient,
  String region = 'gb',
}) =>
    CookieMunchConsent(
      cbid: 'demo',
      apiUrl: 'https://api.test/',
      storage: storage ?? InMemoryConsentStorage(),
      httpClient: httpClient ?? _Recorder().client,
      region: region,
      now: () => 1000,
      stamp: () => 'm-stamp',
    );

void main() {
  group('load', () {
    test('implied default when nothing is stored', () async {
      final c = make();
      final s = await c.load();
      expect(s.necessary, isTrue);
      expect(s.marketing, isFalse);
      expect(s.method, ConsentMethod.implied);
      expect(c.hasResponse, isFalse);
      c.dispose();
    });

    test('restores a previously persisted choice', () async {
      final storage = InMemoryConsentStorage();
      final c1 = make(storage: storage);
      await c1.load();
      await c1.acceptAll();
      c1.dispose();

      final c2 = make(storage: storage);
      final restored = await c2.load();
      expect(restored.marketing, isTrue);
      expect(c2.hasResponse, isTrue);
      c2.dispose();
    });

    test('corrupt payload falls back to implied default', () async {
      final storage = InMemoryConsentStorage();
      await storage.write('CookieMunch', 'not-json');
      final c = make(storage: storage);
      final s = await c.load();
      expect(s.method, ConsentMethod.implied);
      c.dispose();
    });
  });

  group('accept / decline / submitCustom', () {
    test('acceptAll grants all, persists, and POSTs the right contract',
        () async {
      final rec = _Recorder();
      final storage = InMemoryConsentStorage();
      final c = make(storage: storage, httpClient: rec.client);
      await c.load();
      final s = await c.acceptAll();

      expect(s.marketing, isTrue);
      expect(s.method, ConsentMethod.explicit);
      expect(await storage.read('CookieMunch'), contains('"marketing":true'));

      expect(rec.requests.single.url.toString(),
          'https://api.test/api/v1/consent');
      expect(rec.requests.single.method, 'POST');
      expect(rec.headers.single['X-CookieMunch-Region'], 'gb');
      final body = rec.bodies.single;
      expect(body['cbid'], 'demo');
      expect(body['stamp'], 'm-stamp');
      expect(body['method'], 'explicit');
      expect(body['utc'], 1000);
      expect(body['url'], 'app://demo');
      expect((body['choices'] as Map)['marketing'], isTrue);
      c.dispose();
    });

    test('rejectAll denies every non-necessary category', () async {
      final c = make();
      await c.load();
      final s = await c.rejectAll();
      expect(s.marketing, isFalse);
      expect(s.statistics, isFalse);
      expect(s.preferences, isFalse);
      expect(s.necessary, isTrue);
      expect(c.hasResponse, isTrue);
      c.dispose();
    });

    test('submitCustom records the exact choices', () async {
      final c = make();
      await c.load();
      final s = await c.submitCustom(
          preferences: true, statistics: false, marketing: true);
      expect(s.preferences, isTrue);
      expect(s.statistics, isFalse);
      expect(s.marketing, isTrue);
      c.dispose();
    });

    test('accept/decline aliases match acceptAll/rejectAll', () async {
      final c = make();
      await c.load();
      expect((await c.accept()).marketing, isTrue);
      expect((await c.decline()).marketing, isFalse);
      c.dispose();
    });

    test('set toggles one category, leaving the rest intact', () async {
      final c = make();
      await c.load();
      await c.submitCustom(
          preferences: true, statistics: true, marketing: true);
      final s = await c.set(ConsentCategory.marketing, false);
      expect(s.marketing, isFalse);
      expect(s.statistics, isTrue);
      expect(s.preferences, isTrue);
      c.dispose();
    });

    test('set on necessary is a no-op (stays granted)', () async {
      final c = make();
      await c.load();
      final s = await c.set(ConsentCategory.necessary, false);
      expect(s.necessary, isTrue);
      c.dispose();
    });
  });

  group('offline resilience', () {
    test('persists locally even when the API POST throws', () async {
      final rec = _Recorder()..fail = true;
      final storage = InMemoryConsentStorage();
      final c = make(storage: storage, httpClient: rec.client);
      await c.load();
      final s = await c.acceptAll(); // must not throw
      expect(s.marketing, isTrue);
      expect(await storage.read('CookieMunch'), contains('"marketing":true'));
      c.dispose();
    });
  });

  group('onChange', () {
    test('callback fires per decision and can unsubscribe', () async {
      final c = make();
      await c.load();
      var calls = 0;
      final off = c.onChange((_) => calls++);
      await c.acceptAll();
      expect(calls, 1);
      off();
      await c.rejectAll();
      expect(calls, 1);
      c.dispose();
    });

    test('changes stream emits committed state', () async {
      final c = make();
      await c.load();
      final future = c.changes.first;
      await c.acceptAll();
      final emitted = await future;
      expect(emitted.marketing, isTrue);
      c.dispose();
    });
  });

  group('gate', () {
    test('runs immediately when the category is already allowed', () async {
      final c = make();
      await c.load();
      await c.acceptAll();
      var ran = false;
      c.gate(ConsentCategory.statistics, () => ran = true);
      expect(ran, isTrue);
      c.dispose();
    });

    test('defers until the category is granted, then fires once', () async {
      final c = make();
      await c.load();
      var runs = 0;
      c.gate(ConsentCategory.marketing, () => runs++);
      expect(runs, 0); // implied default: not yet allowed
      await c.acceptAll();
      expect(runs, 1);
      await c.submitCustom(
          preferences: true, statistics: true, marketing: true);
      expect(runs, 1); // fires only once
      c.dispose();
    });

    test('cancel prevents a pending gate from firing', () async {
      final c = make();
      await c.load();
      var ran = false;
      final cancel = c.gate(ConsentCategory.marketing, () => ran = true);
      cancel();
      await c.acceptAll();
      expect(ran, isFalse);
      c.dispose();
    });
  });

  group('state model', () {
    test('region and utc round-trip through JSON', () {
      final s = ConsentState(
          stamp: 'x', utc: 42, region: 'us-ca', marketing: true);
      final back = ConsentState.fromJson(s.toJson());
      expect(back.region, 'us-ca');
      expect(back.utc, 42);
      expect(back.marketing, isTrue);
      expect(back.necessary, isTrue);
    });

    test('newStamp yields distinct v4-shaped UUIDs', () {
      final a = newStamp();
      final b = newStamp();
      expect(a, isNot(b));
      expect(a.length, 36);
      expect(a[14], '4'); // version nibble
    });
  });

  group('FileConsentStorage', () {
    test('durably round-trips a decision across client instances', () async {
      final dir = await Directory.systemTemp.createTemp('cm_test');
      final path = '${dir.path}/consent.json';
      final storage = FileConsentStorage(path);

      final c1 = make(storage: storage);
      await c1.load();
      await c1.submitCustom(
          preferences: true, statistics: false, marketing: true);
      c1.dispose();

      final c2 = make(storage: FileConsentStorage(path));
      final restored = await c2.load();
      expect(restored.marketing, isTrue);
      expect(restored.statistics, isFalse);
      expect(restored.hasResponse, isTrue);
      c2.dispose();

      await dir.delete(recursive: true);
    });
  });
}
