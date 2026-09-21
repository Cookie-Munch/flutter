# cookie_munch (Flutter / Dart)

The **Cookie Munch** Flutter & Dart SDK for the Cookie Munch Consent
Management Platform. It mirrors the web, iOS (Swift), Android (Kotlin) and React
Native SDKs exactly — same consent model, same `POST /api/v1/consent`, same
offline-safe behavior — so consent records are uniform across every platform.

**Runs everywhere Flutter runs — mobile *and* desktop.** The consent core is
pure Dart (no platform plugins), so Android, iOS, **macOS, Windows and Linux**
are all first-class targets. The only Flutter dependency is the optional
[`ConsentBanner`] widget; the client itself imports nothing but `dart:*` and
`package:http`.

## Install

In your app's `pubspec.yaml`:

```yaml
dependencies:
  cookie_munch:
    path: ../native/flutter   # or your package path / git ref
```

Then `flutter pub get`.

## Quick start (mobile & desktop)

```dart
import 'package:flutter/material.dart';
import 'package:cookie_munch/cookie_munch.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CookieMunchConsent.configure(
    cbid: 'your-site-id',
    apiUrl: 'https://api.cookiemunch.net',
    region: 'gb',
    // Default storage is in-memory. For durability across restarts:
    // storage: FileConsentStorage('/absolute/path/consent.json'),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: const [
            // ... your app ...
            Align(
              alignment: Alignment.bottomCenter,
              child: ConsentBanner(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- Persists the decision via a pluggable `ConsentStorage`, then best-effort syncs
  to `<apiUrl>/api/v1/consent` — **offline-safe**: a decision is stored locally
  even if the POST fails, and can retry on next launch.
- The banner shows only while `!CookieMunchConsent.instance.hasResponse`.
- The banner is themed (uses your `Theme`) and accepts label/color overrides.

### Reading / changing consent

```dart
final c = CookieMunchConsent.instance;

if (c.allows(ConsentCategory.marketing)) { /* enable marketing SDKs */ }

await c.acceptAll();
await c.rejectAll();
await c.submitCustom(preferences: true, statistics: true, marketing: false);
await c.set(ConsentCategory.statistics, true); // toggle one category

// React to changes (e.g. in a StatefulWidget):
final off = c.onChange((state) => print('marketing=${state.marketing}'));
// ...later: off();
// or a stream: c.changes.listen((state) { ... });
```

### The `gate` pattern — native prior-blocking

The web embed *prior-blocks* third-party scripts until consent. On native, do the
same with `gate`: your code runs **only once** the category is granted (now if it
already is, otherwise the first time it's granted).

```dart
// Analytics init runs only after 'statistics' consent — immediately or later.
CookieMunchConsent.instance.gate(ConsentCategory.statistics, () {
  MyAnalytics.start();
});

// Returns a cancel fn if you need to drop a still-pending gate.
final cancel = c.gate(ConsentCategory.marketing, initAdSdk);
```

## Desktop notes

- No changes needed: the default `InMemoryConsentStorage` and `FileConsentStorage`
  both work on macOS/Windows/Linux with zero plugins.
- For a durable path on desktop, point `FileConsentStorage` at a file under the
  user's app-support/home directory (e.g. via `path_provider`'s
  `getApplicationSupportDirectory()`), or any writable absolute path.

## Storage options

| Storage | Persistence | Deps | Platforms |
|---|---|---|---|
| `InMemoryConsentStorage` (default) | none | none | all (incl. web) |
| `FileConsentStorage(path)` | file on disk | none (`dart:io`) | mobile + desktop |
| your own `ConsentStorage` | anything | your choice | your choice |

To back consent with `shared_preferences` on mobile, add the plugin in **your**
app and adapt it — the core never imports it, so it never leaks into desktop
builds:

```dart
class PrefsConsentStorage implements ConsentStorage {
  PrefsConsentStorage(this._p);
  final SharedPreferences _p;
  @override Future<String?> read(String k) async => _p.getString(k);
  @override Future<void> write(String k, String v) async => _p.setString(k, v);
  @override Future<void> delete(String k) async => _p.remove(k);
}
```

## Testing / non-widget use

Import the Flutter-free core for services, isolates, or plain `dart test`:

```dart
import 'package:cookie_munch/cookie_munch_core.dart';
```

Inject a mock `http.Client` (e.g. `package:http/testing` `MockClient`) so no real
network is hit. See `test/client_test.dart`.

## iOS App Tracking Transparency (ATT)

Only request the OS tracking prompt **after** the user grants `marketing` —
never on launch — to stay consistent with the banner. Add the
[`app_tracking_transparency`](https://pub.dev/packages/app_tracking_transparency)
package and `NSUserTrackingUsageDescription` to your `Info.plist`, then:

```dart
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:cookie_munch/cookie_munch.dart';

// Gate the ATT prompt on marketing consent — fires now or when granted later.
CookieMunchConsent.instance.gate(ConsentCategory.marketing, () {
  AppTrackingTransparency.requestTrackingAuthorization();
});
```

This matches the iOS SDK's `requestTrackingIfMarketingGranted()` and the RN
SDK's `expo-tracking-transparency` gating on `marketing`.
