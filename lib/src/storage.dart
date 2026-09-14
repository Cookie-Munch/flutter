/// Pluggable persistence for the consent record. The core client depends only on
/// this interface, never on a concrete plugin — so the SDK stays pure Dart and
/// runs on mobile **and** desktop out of the box.
///
/// Two zero-dependency implementations ship here:
///   * [InMemoryConsentStorage] — ephemeral, the default; great for tests and for
///     apps that re-sync from the server on launch.
///   * [FileConsentStorage] — durable JSON on disk via `dart:io`; works on Android,
///     iOS, macOS, Windows and Linux with no plugin at all.
///
/// To use `shared_preferences` (mobile) instead, add the plugin in your app and
/// implement [ConsentStorage] over it — see the README. Nothing in the core
/// imports it, so it never leaks into desktop builds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A tiny async key/value store. Mirrors AsyncStorage / SharedPreferences shape.
abstract class ConsentStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory storage. Nothing survives a restart — pair it with server sync, or
/// use [FileConsentStorage] for durability. This is the default so the SDK has
/// zero platform requirements.
class InMemoryConsentStorage implements ConsentStorage {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// Durable storage backed by a single JSON file (`dart:io`). Cross-platform on
/// every native target. Provide an absolute [path]; on mobile derive it from
/// `path_provider`'s app-documents directory, on desktop use a file under the
/// user's home/app-support directory.
///
/// All keys live in one JSON object, so several [ConsentStorage] consumers can
/// share the same file safely.
class FileConsentStorage implements ConsentStorage {
  FileConsentStorage(this.path);

  /// Absolute path to the backing JSON file.
  final String path;

  Future<Map<String, dynamic>> _load() async {
    try {
      final f = File(path);
      if (!await f.exists()) return {};
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      // Corrupt/unreadable file — behave as empty rather than crashing the app.
      return {};
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(data), flush: true);
  }

  @override
  Future<String?> read(String key) async {
    final data = await _load();
    final v = data[key];
    return v is String ? v : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final data = await _load();
    data[key] = value;
    await _save(data);
  }

  @override
  Future<void> delete(String key) async {
    final data = await _load();
    data.remove(key);
    await _save(data);
  }
}
