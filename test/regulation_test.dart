// The jurisdiction table, and the client API built on it. The same cases are
// pinned in packages/server/test/config-regulation.test.ts, the Swift
// RegulationTests and the Kotlin RegulationTest — four ports, one table, so a
// drift in any of them shows up as a failure here or there.
import 'package:cookie_munch/cookie_munch_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Regulation.resolve', () {
    test('europe is gdpr opt-in', () {
      final reg = Regulation.resolve('de');
      expect(reg.regionClass, RegionClass.eu);
      expect(reg.gdprApplies, isTrue);
      expect(reg.ccpaApplies, isFalse);
      expect(reg.model, ConsentModel.optIn);
      expect(reg.defaultGranted, isFalse);
      expect(reg.framework, SignalFramework.tcf);
    });

    test('the united kingdom counts as europe', () {
      expect(Regulation.resolve('gb').regionClass, RegionClass.eu);
      expect(Regulation.resolve('uk').regionClass, RegionClass.eu);
    });

    test('california is ccpa opt-out', () {
      final reg = Regulation.resolve('us-ca');
      expect(reg.regionClass, RegionClass.us);
      expect(reg.ccpaApplies, isTrue);
      expect(reg.model, ConsentModel.optOut);
      expect(reg.defaultGranted, isTrue);
      expect(reg.framework, SignalFramework.gpp);
    });

    test('brazil is lgpd', () {
      expect(Regulation.resolve('br').lgpdApplies, isTrue);
      expect(Regulation.resolve('br').model, ConsentModel.optIn);
    });

    test('region is case insensitive and tolerant of subdivisions', () {
      expect(Regulation.resolve('FR').regionClass, RegionClass.eu);
      expect(Regulation.resolve('US-NY').regionClass, RegionClass.us);
    });

    // A geo lookup that fails must never silently downgrade someone's protections.
    test('unknown region falls back to opt-in', () {
      for (final region in [null, '', 'zz', 'unknown']) {
        final reg = Regulation.resolve(region);
        expect(reg.model, ConsentModel.optIn, reason: 'region $region');
        expect(reg.defaultGranted, isFalse, reason: 'region $region');
      }
    });

    test('gpc forces opt-out only where collection would otherwise proceed', () {
      expect(Regulation.resolve('us-ca', gpc: true).forcedOptOut, isTrue);
      // Under GDPR nothing fires before consent, so there is nothing for GPC to stop.
      expect(Regulation.resolve('de', gpc: true).forcedOptOut, isFalse);
    });

    test('do not track forces opt-out and can be disabled', () {
      expect(Regulation.resolve('us-tx', dnt: true).forcedOptOut, isTrue);
      expect(Regulation.resolve('us-tx', dnt: true, honorDnt: false).forcedOptOut, isFalse);
    });

    test('consent required is false only when they signalled already', () {
      expect(Regulation.resolve('de').consentRequired, isTrue);
      expect(Regulation.resolve('us-ca').consentRequired, isTrue);
      expect(Regulation.resolve('us-ca', gpc: true).consentRequired, isFalse);
    });
  });

  group('Regulation.fromConfigJson', () {
    test('parses the config payload', () {
      final reg = Regulation.fromConfigJson('''
        {"cbid":"x","region":"us-ca","regulation":{
          "region":"us-ca","class":"us",
          "regulations":{"gdprApplies":false,"ccpaApplies":true,"lgpdApplies":false},
          "model":"opt-out","defaultState":"granted","framework":"gpp",
          "forcedOptOut":true,"consentRequired":false}}
      ''')!;
      expect(reg.region, 'us-ca');
      expect(reg.regionClass, RegionClass.us);
      expect(reg.ccpaApplies, isTrue);
      expect(reg.model, ConsentModel.optOut);
      expect(reg.defaultGranted, isTrue);
      expect(reg.forcedOptOut, isTrue);
      expect(reg.consentRequired, isFalse);
    });

    // A server that learns a new jurisdiction tomorrow must not crash an app
    // shipped today.
    test('unrecognised class parses as other rather than throwing', () {
      final reg = Regulation.fromConfigJson(
        '{"regulation":{"region":"jp","class":"apac","regulations":{},'
        '"model":"opt-in","defaultState":"denied","framework":"none",'
        '"forcedOptOut":false,"consentRequired":true}}',
      )!;
      expect(reg.regionClass, RegionClass.other);
      expect(reg.model, ConsentModel.optIn);
    });

    // Defaulting a missing bool to false would suppress every prompt on the
    // planet, so it is derived instead.
    test('a missing consentRequired is derived, not defaulted to false', () {
      final reg = Regulation.fromConfigJson(
        '{"regulation":{"region":"de","class":"eu","regulations":{"gdprApplies":true},'
        '"model":"opt-in","defaultState":"denied","framework":"tcf","forcedOptOut":false}}',
      )!;
      expect(reg.consentRequired, isTrue);
    });

    test('absent or malformed payloads parse to null rather than throwing', () {
      expect(Regulation.fromConfigJson('{"cbid":"x"}'), isNull);
      expect(Regulation.fromConfigJson('not json at all'), isNull);
      expect(Regulation.fromConfigJson(''), isNull);
    });
  });

  group('CookieMunchConsent regulation API', () {
    CookieMunchConsent client(String region, {http.Client? httpClient}) =>
        CookieMunchConsent(
          cbid: 'cb-1',
          apiUrl: 'https://cmp.example.com/',
          region: region,
          httpClient: httpClient ?? MockClient((_) async => http.Response('', 204)),
          now: () => 1700000000000,
          stamp: () => 'fixed',
        );

    test('resolves offline from the configured region', () {
      expect(client('de').applicableRegulation.gdprApplies, isTrue);
      expect(client('us-ca').applicableRegulation.ccpaApplies, isTrue);
    });

    test('consent is required before the user has answered', () {
      expect(client('de').isConsentRequired, isTrue);
    });

    // The single most useful property in the whole API: once they have answered,
    // stop asking. An app that re-prompts on every cold start is the reason
    // people install content blockers.
    test('consent is not required once the user has answered', () async {
      final c = client('de');
      await c.accept();
      expect(c.isConsentRequired, isFalse);
    });

    test('declining still counts as answering', () async {
      final c = client('de');
      await c.decline();
      expect(c.isConsentRequired, isFalse);
    });

    test('an opt-out signal answers for them under an opt-out regime', () {
      final c = client('us-ca');
      expect(c.isConsentRequired, isTrue);
      c.globalPrivacyControl = true;
      expect(c.isConsentRequired, isFalse);
      expect(c.applicableRegulation.forcedOptOut, isTrue);
    });

    // GPC is a refusal, not a regime change — a GDPR prompt is still owed.
    test('global privacy control does not suppress a gdpr prompt', () {
      final c = client('de');
      c.globalPrivacyControl = true;
      expect(c.isConsentRequired, isTrue);
    });

    test('do not track behaves like gpc', () {
      final c = client('us-tx');
      c.doNotTrack = true;
      expect(c.isConsentRequired, isFalse);
    });

    test('refresh adopts the server answer over the local guess', () async {
      // A German-locale phone, physically in California. Locale says GDPR; the
      // server, which sees the IP, says CCPA — and the server is right.
      Uri? asked;
      Map<String, String>? sent;
      final c = client('de', httpClient: MockClient((req) async {
        asked = req.url;
        sent = req.headers;
        return http.Response(
          '{"regulation":{"region":"us-ca","class":"us",'
          '"regulations":{"gdprApplies":false,"ccpaApplies":true,"lgpdApplies":false},'
          '"model":"opt-out","defaultState":"granted","framework":"gpp",'
          '"forcedOptOut":false,"consentRequired":true}}',
          200,
        );
      }));
      expect(c.applicableRegulation.gdprApplies, isTrue);

      await c.refreshRegulation();

      expect(c.applicableRegulation.ccpaApplies, isTrue);
      expect(c.applicableRegulation.gdprApplies, isFalse);
      expect(asked.toString(), 'https://cmp.example.com/config/cb-1');
      expect(sent!['X-CookieMunch-Region'], 'de');
    });

    // Offline, or a server not yet upgraded. Either way the app keeps an answer.
    test('refresh failure leaves the local regulation intact', () async {
      final c = client('de', httpClient: MockClient((_) async => throw Exception('offline')));
      await c.refreshRegulation();
      expect(c.applicableRegulation.gdprApplies, isTrue);
      expect(c.isConsentRequired, isTrue);
    });

    test('refresh ignores a response with no regulation block', () async {
      final c = client('de', httpClient: MockClient((_) async => http.Response('{"cbid":"cb-1"}', 200)));
      await c.refreshRegulation();
      expect(c.applicableRegulation.gdprApplies, isTrue);
    });

    test('a non-2xx response is not parsed at all', () async {
      final c = client('de', httpClient: MockClient((_) async => http.Response('{"regulation":{}}', 500)));
      await c.refreshRegulation();
      expect(c.applicableRegulation.gdprApplies, isTrue);
    });
  });
}
