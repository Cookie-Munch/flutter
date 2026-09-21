// Carrying a decision from the Flutter app into a WebView. The contract that
// matters is that the WEB READER recovers the right decision — not that the four
// ports emit byte-identical strings. See packages/core/test/webview-bridge.test.ts
// for the reader these must satisfy.
import 'dart:convert';

import 'package:cookie_munch/cookie_munch_core.dart';
import 'package:test/test.dart';

ConsentState _state() => ConsentState(
      preferences: true,
      statistics: false,
      marketing: true,
      method: ConsentMethod.explicit,
      stamp: 'abc-123',
      ver: 1,
      utc: 1700000000000,
      region: 'de',
    );

/// Undo the cookie layer, the way the embed's `parseValue` does.
Map<String, dynamic> _readBack(String encoded) =>
    jsonDecode(Uri.decodeComponent(encoded)) as Map<String, dynamic>;

/// Undo BOTH layers, the way the embed's `parseWebViewConsent` does: once to pull
/// the parameter out of the query string, once to turn the cookie value into JSON.
Map<String, dynamic> _readBackFromQuery(String raw) => _readBack(Uri.decodeComponent(raw));

void main() {
  group('javaScript', () {
    test('writes the cookie the embed reads, carrying every field', () {
      final js = WebViewBridge.javaScript(_state());
      expect(js, startsWith("document.cookie='CookieMunch='"));
      expect(js, contains('path=/'));
      expect(js, contains('max-age=${WebViewBridge.defaultMaxAge}'));
      expect(js, contains('SameSite=Lax'));

      final value = RegExp(r"'CookieMunch='\+'([^']*)'").firstMatch(js)!.group(1)!;
      final decoded = _readBack(value);
      expect(decoded['preferences'], isTrue);
      expect(decoded['statistics'], isFalse);
      expect(decoded['marketing'], isTrue);
      expect(decoded['method'], 'explicit');
      expect(decoded['stamp'], 'abc-123');
      expect(decoded['region'], 'de');
      expect(decoded['necessary'], isTrue);
    });

    // Every platform evaluator takes a single string; a multi-line program is a
    // common source of silent cross-platform failures.
    test('is a single line', () {
      expect(WebViewBridge.javaScript(_state()), isNot(contains('\n')));
    });

    test('honours a custom lifetime', () {
      expect(WebViewBridge.javaScript(_state(), maxAge: 60), contains('max-age=60'));
    });

    test('can also write the legacy cookie for a migrating app', () {
      final js = WebViewBridge.javaScript(_state(), alsoLegacyCookie: true);
      expect(js, contains("'CookieMunch='"));
      expect(js, contains("'CookieConsent='"));
      // Two complete statements, not one malformed concatenation.
      expect(RegExp(r'document\.cookie=').allMatches(js).length, 2);
    });

    // The value is JSON inside a single-quoted JS literal. A quote or an angle
    // bracket that escaped unescaped would either break the statement or, if the
    // statement were ever inlined into a page, close the script tag.
    test('escapes anything that could break out of the literal', () {
      final hostile = ConsentState(
        preferences: true,
        statistics: true,
        marketing: true,
        method: ConsentMethod.explicit,
        stamp: "'; alert(1); //</script><x y='",
        ver: 1,
        utc: 1700000000000,
        region: 'de',
      );
      final js = WebViewBridge.javaScript(hostile);

      // Nothing that could close an enclosing script tag survives.
      expect(js, isNot(contains('</script')));

      // Every quote in the statement is either one of the three literal pairs or
      // backslash-escaped. If one were not, the literal would terminate early and
      // the rest of the stamp would be evaluated as code.
      expect(js.replaceAll(r"\'", '').split("'").length - 1, 6);

      // And the escaping is lossless: the reader recovers the stamp exactly, so a
      // legitimate-but-awkward value is carried across rather than mangled.
      final value = RegExp(r"'CookieMunch='\+'(.*)'\+';path").firstMatch(js)!.group(1)!;
      expect(_readBack(value.replaceAll(r"\'", "'"))['stamp'], hostile.stamp);
    });
  });

  group('queryString and urlCarrying', () {
    test('round-trips through a web-style decode', () {
      final qs = WebViewBridge.queryString(_state());
      expect(qs, startsWith('${WebViewBridge.param}='));
      final decoded = _readBackFromQuery(qs.substring(WebViewBridge.param.length + 1));
      expect(decoded['stamp'], 'abc-123');
      expect(decoded['marketing'], isTrue);
    });

    test('preserves a query the caller already had', () {
      final url = WebViewBridge.urlCarrying(
        Uri.parse('https://example.com/help?topic=billing'),
        _state(),
      );
      expect(url.queryParameters['topic'], 'billing');
      expect(url.queryParameters[WebViewBridge.param], isNotNull);
    });

    // A WebView that reloads its own URL would otherwise accumulate parameters
    // until the request line was too long to send.
    test('replaces rather than duplicating on a second pass', () {
      var url = WebViewBridge.urlCarrying(Uri.parse('https://example.com/'), _state());
      url = WebViewBridge.urlCarrying(url, _state());
      expect(RegExp('${WebViewBridge.param}=').allMatches(url.toString()).length, 1);
    });

    test('the parameter survives Uri parsing intact', () {
      final url = WebViewBridge.urlCarrying(Uri.parse('https://example.com/'), _state());
      final reparsed = Uri.parse(url.toString());
      // `queryParameters` peels the outer layer, leaving exactly the cookie value.
      final decoded = _readBack(reparsed.queryParameters[WebViewBridge.param]!);
      expect(decoded['stamp'], 'abc-123');
      expect(decoded['region'], 'de');
    });

    // The bug this file shipped with for one commit: single-encoding round-trips
    // for simple values and then corrupts the first decision containing a `%`.
    test('survives a value containing a literal percent sign', () {
      const awkward = ConsentState(
        preferences: true,
        statistics: true,
        marketing: true,
        method: ConsentMethod.explicit,
        stamp: '100%-sure',
        ver: 1,
        utc: 1700000000000,
        region: 'de',
      );
      final qs = WebViewBridge.queryString(awkward);
      final decoded = _readBackFromQuery(qs.substring(WebViewBridge.param.length + 1));
      expect(decoded['stamp'], '100%-sure');
    });
  });
}
