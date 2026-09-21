/// Carrying consent from a Flutter app into a WebView.
///
/// A hybrid app collects consent natively, then opens web content — a help centre,
/// a checkout, an article. That page runs our embed, finds no stored decision, and
/// prompts again. The person has now been asked twice for the same thing, and the
/// second answer is the one the web side keeps.
///
/// Two ways across, because platforms differ in what they allow:
///   * [javaScript] — a statement to evaluate inside the WebView, which writes the
///     same cookie the embed already reads. Preferred: it survives navigation
///     within the origin and needs no cooperation from the page.
///   * [queryString] / [urlCarrying] — a parameter appended to the URL, for cases
///     where script evaluation is unavailable.
///
/// A Dart port of `packages/core/src/webview-bridge.ts`, matching the Swift and
/// Kotlin bridges. The contract that matters is that the *web reader* recovers the
/// right decision — not that the four produce byte-identical strings.
library;

import 'dart:convert';

import 'consent_state.dart';

/// The bridge. All members are static; there is nothing to instantiate.
class WebViewBridge {
  const WebViewBridge._();

  /// Query parameter carrying a serialised decision.
  static const String param = 'cm_consent';

  /// Cookie the web embed reads.
  static const String cookieName = 'CookieMunch';

  /// Cookiebot's name, for apps migrating from it.
  static const String legacyCookieName = 'CookieConsent';

  /// Twelve months, matching the embed's own default cookie lifetime.
  static const int defaultMaxAge = 60 * 60 * 24 * 365;

  /// The serialised, URL-encoded value the web side stores.
  ///
  /// `Uri.encodeComponent` is already `encodeURIComponent`'s escape set, so the
  /// output round-trips through the embed's `decodeURIComponent` unchanged.
  static String serialize(ConsentState state) =>
      Uri.encodeComponent(jsonEncode(state.toJson()));

  /// Escape for embedding inside a single-quoted JavaScript string literal.
  static String jsString(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      // `</script` would close an inline tag if this were ever inlined.
      .replaceAll('<', r'\x3c');

  /// A single JavaScript statement that seeds a WebView with this decision.
  ///
  /// One line and expression-only on purpose: every platform's evaluator takes a
  /// string, and a multi-line program is a common source of silent failures.
  /// Pass it to `webview_flutter`'s `runJavaScript`, ideally from an
  /// `onPageStarted` callback so it lands before the embed reads the cookie.
  static String javaScript(
    ConsentState state, {
    int maxAge = defaultMaxAge,
    bool alsoLegacyCookie = false,
  }) {
    final value = serialize(state);
    final attrs = ';path=/;max-age=$maxAge;SameSite=Lax';
    String write(String name) =>
        "document.cookie='${jsString(name)}='+'${jsString(value)}'+'${jsString(attrs)}';";
    return alsoLegacyCookie
        ? '${write(cookieName)}${write(legacyCookieName)}'
        : write(cookieName);
  }

  /// A URL parameter carrying this decision, for when script evaluation is
  /// unavailable. Append to the URL you are about to load.
  ///
  /// The value is percent-encoded TWICE, and that is deliberate: [serialize] is the
  /// cookie value, which is itself already encoded, and the reader unwraps both
  /// layers — once pulling the parameter out of the query string, once turning the
  /// cookie value back into JSON. Encoding only once round-trips for simple values
  /// and then silently corrupts the first decision whose JSON contains a literal
  /// `%`. See `parseWebViewConsent` in packages/core/src/webview-bridge.ts.
  static String queryString(ConsentState state) =>
      '$param=${Uri.encodeComponent(serialize(state))}';

  /// [url] with the decision attached, replacing any existing [param] rather than
  /// appending a second copy — a WebView that reloads its own URL would otherwise
  /// accumulate them until the request line was too long to send.
  static Uri urlCarrying(Uri url, ConsentState state) {
    // `queryParameters` decodes on read and `replace` re-encodes on write, which
    // together preserve exactly one of the two layers described on [queryString].
    final params = Map<String, String>.from(url.queryParameters)
      ..[param] = serialize(state);
    return url.replace(queryParameters: params);
  }
}
