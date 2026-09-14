/// The Cookie Munch consent client — the framework-agnostic core.
///
/// It has **no Flutter imports** (only `dart:*` and `package:http`), so it runs
/// identically on Android, iOS, macOS, Windows and Linux, and is fully unit
/// testable with `dart test` by injecting a mock [http.Client].
///
/// Design mirrors the React Native client (`packages/react-native/src/client.ts`):
/// an implied default, pluggable storage, `load`/`accept`/`decline`/`submitCustom`,
/// an `onChange` subscription, region awareness, and best-effort API sync. It adds
/// a [gate] helper — the native equivalent of the web embed's prior-blocking.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'consent_state.dart';
import 'storage.dart';

/// A self-hosted Cookie Munch consent client.
///
/// Instantiate one directly (recommended for dependency injection and testing),
/// or use the app-wide [CookieMunchConsent.instance] configured once via
/// [CookieMunchConsent.configure].
class CookieMunchConsent {
  /// Creates a client. Nothing is read from storage until you call [load].
  ///
  /// * [cbid] — your Cookie Munch site id.
  /// * [apiUrl] — base URL of your self-hosted server (trailing slash optional).
  /// * [storage] — where the decision is persisted; defaults to
  ///   [InMemoryConsentStorage] (pure Dart, no plugins). Use [FileConsentStorage]
  ///   for durability across restarts.
  /// * [httpClient] — injectable for tests; defaults to a real [http.Client].
  /// * [region] — coarse region tag applied to the record and the sync header.
  CookieMunchConsent({
    required this.cbid,
    required String apiUrl,
    ConsentStorage? storage,
    http.Client? httpClient,
    this.region = 'unknown',
    this.storageKey = 'CookieMunch',
    int Function()? now,
    String Function()? stamp,
  })  : _apiUrl = _trim(apiUrl),
        _storage = storage ?? InMemoryConsentStorage(),
        _http = httpClient ?? http.Client(),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _stamp = stamp ?? newStamp {
    _state = ConsentState.initial(region: region, stamp: _stamp, now: _now);
  }

  /// The Cookie Munch site id this client reports consent for.
  final String cbid;

  /// Coarse region tag (e.g. `gb`, `us-ca`).
  final String region;

  /// Storage key under which the decision is persisted.
  final String storageKey;

  final String _apiUrl;
  final ConsentStorage _storage;
  final http.Client _http;
  final int Function() _now;
  final String Function() _stamp;

  late ConsentState _state;
  final Set<void Function(ConsentState)> _listeners = {};
  final StreamController<ConsentState> _controller =
      StreamController<ConsentState>.broadcast();
  bool _disposed = false;

  // --- app-wide shared instance (optional convenience) ----------------------

  static CookieMunchConsent? _shared;

  /// The app-wide client configured by [configure]. Throws if unconfigured.
  static CookieMunchConsent get instance {
    final s = _shared;
    if (s == null) {
      throw StateError(
          'CookieMunchConsent.instance used before CookieMunchConsent.configure()');
    }
    return s;
  }

  /// Whether the shared [instance] has been configured.
  static bool get isConfigured => _shared != null;

  /// Configures and loads the app-wide [instance]. Call once at startup, e.g.
  /// inside `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<CookieMunchConsent> configure({
    required String cbid,
    required String apiUrl,
    ConsentStorage? storage,
    http.Client? httpClient,
    String region = 'unknown',
    String storageKey = 'CookieMunch',
  }) async {
    final c = CookieMunchConsent(
      cbid: cbid,
      apiUrl: apiUrl,
      storage: storage,
      httpClient: httpClient,
      region: region,
      storageKey: storageKey,
    );
    _shared = c;
    await c.load();
    return c;
  }

  /// Resets the shared instance (primarily for tests).
  static void resetShared() => _shared = null;

  // --- state accessors ------------------------------------------------------

  /// The current consent snapshot.
  ConsentState get state => _state;

  /// `true` once the user has made an explicit choice.
  bool get hasResponse => _state.hasResponse;

  /// Whether [category] is currently granted. `necessary` is always `true`.
  bool allows(ConsentCategory category) => _state.allows(category);

  /// A broadcast stream of state changes (fires on every committed decision).
  Stream<ConsentState> get changes => _controller.stream;

  /// Registers a change callback; returns an unsubscribe function. Mirrors the
  /// React Native client's `onChange`.
  void Function() onChange(void Function(ConsentState) cb) {
    _listeners.add(cb);
    return () => _listeners.remove(cb);
  }

  // --- lifecycle ------------------------------------------------------------

  /// Restores any persisted decision. If none exists, keeps the implied default
  /// tagged with [region]. Safe to call multiple times.
  Future<ConsentState> load() async {
    final raw = await _storage.read(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _state = ConsentState.fromJson(decoded, fallbackRegion: region);
      } catch (_) {
        // Corrupt payload — keep the implied default.
      }
    }
    _emit();
    return _state;
  }

  /// Grants every category.
  Future<ConsentState> acceptAll() => submit(Choices.all);

  /// Alias for [acceptAll] (React Native parity).
  Future<ConsentState> accept() => acceptAll();

  /// Denies every non-necessary category.
  Future<ConsentState> rejectAll() => submit(Choices.none);

  /// Alias for [rejectAll] (React Native parity).
  Future<ConsentState> decline() => rejectAll();

  /// Records an exact set of choices.
  Future<ConsentState> submitCustom({
    required bool preferences,
    required bool statistics,
    required bool marketing,
  }) =>
      submit(Choices(
        preferences: preferences,
        statistics: statistics,
        marketing: marketing,
      ));

  /// Records an exact [Choices] set, persists it, notifies listeners, then
  /// best-effort syncs to the API.
  Future<ConsentState> submit(Choices choices) async {
    _state = _state.withChoices(choices, utc: _now());
    await _persist();
    _emit();
    // Offline-safe: the decision is already persisted; a failed POST is swallowed.
    await _sync(_state);
    return _state;
  }

  /// Toggles a single [category] on/off, preserving the others. `necessary` is
  /// immutable and this is a no-op for it.
  Future<ConsentState> set(ConsentCategory category, bool value) {
    final c = _state.choices;
    switch (category) {
      case ConsentCategory.necessary:
        return Future.value(_state);
      case ConsentCategory.preferences:
        return submit(c.copyWith(preferences: value));
      case ConsentCategory.statistics:
        return submit(c.copyWith(statistics: value));
      case ConsentCategory.marketing:
        return submit(c.copyWith(marketing: value));
    }
  }

  /// Runs [fn] only once [category] is granted — the native equivalent of the
  /// web embed's prior-blocking. If the category is already allowed, [fn] runs
  /// immediately; otherwise it fires the first time consent for that category is
  /// granted. Returns a cancel function that unregisters a still-pending gate.
  ///
  /// ```dart
  /// consent.gate(ConsentCategory.statistics, () => initAnalytics());
  /// ```
  void Function() gate(ConsentCategory category, void Function() fn) {
    if (allows(category)) {
      fn();
      return () {};
    }
    late final void Function() off;
    off = onChange((s) {
      if (s.allows(category)) {
        off();
        fn();
      }
    });
    return off;
  }

  /// Closes the change stream. Call when a non-shared client is discarded.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    _controller.close();
  }

  // --- internals ------------------------------------------------------------

  void _emit() {
    for (final cb in List.of(_listeners)) {
      try {
        cb(_state);
      } catch (_) {
        // A listener error must never break a consent decision.
      }
    }
    if (!_controller.isClosed) _controller.add(_state);
  }

  Future<void> _persist() =>
      _storage.write(storageKey, jsonEncode(_state.toJson()));

  /// POSTs the decision to `<apiUrl>/api/v1/consent`. Wrapped so a network
  /// failure never loses the (already-persisted) decision.
  Future<void> _sync(ConsentState s) async {
    if (_apiUrl.isEmpty) return;
    try {
      await _http.post(
        Uri.parse('$_apiUrl/api/v1/consent'),
        headers: {
          'Content-Type': 'application/json',
          'X-CookieMunch-Region': s.region,
        },
        body: jsonEncode({
          'cbid': cbid,
          'stamp': s.stamp,
          'choices': s.choices.toJson(),
          'method': s.method.wire,
          'ver': s.ver,
          'utc': s.utc,
          'url': 'app://$cbid',
        }),
      );
    } catch (_) {
      // Offline: swallow — decision persisted, can retry on next launch.
    }
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
