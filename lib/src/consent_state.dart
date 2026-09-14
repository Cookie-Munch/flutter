/// Pure-Dart consent model. Contains **no Flutter imports**, so it runs on every
/// target — Android, iOS, macOS, Windows, Linux — and is unit-testable with plain
/// `dart test` (no widget/`dart:ui` binding required).
///
/// The wire shape is kept byte-for-byte identical to the web, iOS, Android and
/// React Native SDKs so consent records are uniform across every platform.
library;

import 'dart:math';

/// How the current decision was reached. `implied` is the pre-choice default;
/// `explicit` means the user actively chose.
enum ConsentMethod {
  implied,
  explicit;

  /// The value sent on the wire / persisted to storage.
  String get wire => this == ConsentMethod.explicit ? 'explicit' : 'implied';

  /// Parses a wire value, defaulting to [ConsentMethod.implied].
  static ConsentMethod fromWire(String? s) =>
      s == 'explicit' ? ConsentMethod.explicit : ConsentMethod.implied;
}

/// The four standard consent categories, shared with every Cookie Munch SDK.
/// `necessary` is always granted and cannot be withdrawn.
enum ConsentCategory {
  necessary,
  preferences,
  statistics,
  marketing;

  /// Resolves a category from its lowercase name, or `null` if unknown.
  static ConsentCategory? fromName(String s) {
    for (final c in ConsentCategory.values) {
      if (c.name == s) return c;
    }
    return null;
  }
}

/// The three user-controllable choices (necessary is implicit and always on).
class Choices {
  const Choices({
    this.preferences = false,
    this.statistics = false,
    this.marketing = false,
  });

  final bool preferences;
  final bool statistics;
  final bool marketing;

  /// Everything granted.
  static const Choices all =
      Choices(preferences: true, statistics: true, marketing: true);

  /// Nothing beyond necessary.
  static const Choices none = Choices();

  Choices copyWith({bool? preferences, bool? statistics, bool? marketing}) =>
      Choices(
        preferences: preferences ?? this.preferences,
        statistics: statistics ?? this.statistics,
        marketing: marketing ?? this.marketing,
      );

  Map<String, dynamic> toJson() => {
        'preferences': preferences,
        'statistics': statistics,
        'marketing': marketing,
      };

  @override
  bool operator ==(Object other) =>
      other is Choices &&
      other.preferences == preferences &&
      other.statistics == statistics &&
      other.marketing == marketing;

  @override
  int get hashCode => Object.hash(preferences, statistics, marketing);
}

/// An immutable snapshot of a device's consent. Mirrors the web/iOS/Android/RN
/// SDKs field-for-field.
class ConsentState {
  const ConsentState({
    this.necessary = true,
    this.preferences = false,
    this.statistics = false,
    this.marketing = false,
    this.method = ConsentMethod.implied,
    required this.stamp,
    this.ver = 1,
    required this.utc,
    this.region = 'unknown',
  });

  /// A fresh implied state with a new random [stamp] and the current [utc].
  factory ConsentState.initial({
    String region = 'unknown',
    String Function()? stamp,
    int Function()? now,
  }) =>
      ConsentState(
        stamp: (stamp ?? newStamp)(),
        utc: (now ?? _nowMs)(),
        region: region,
      );

  /// `necessary` cookies are always allowed; this is always `true`.
  final bool necessary;
  final bool preferences;
  final bool statistics;
  final bool marketing;
  final ConsentMethod method;

  /// Stable per-decision identifier (v4 UUID), used to dedupe records server-side.
  final String stamp;

  /// Schema version of the choices contract.
  final int ver;

  /// Milliseconds since the Unix epoch when the decision was made.
  final int utc;

  /// Coarse region tag (e.g. `gb`, `us-ca`, `unknown`).
  final String region;

  /// `true` once the user has made an explicit choice.
  bool get hasResponse => method == ConsentMethod.explicit;

  /// `true` if any non-necessary category is granted.
  bool get consented => preferences || statistics || marketing;

  /// The three controllable choices as a [Choices].
  Choices get choices =>
      Choices(preferences: preferences, statistics: statistics, marketing: marketing);

  /// Whether [category] is currently granted. `necessary` is always `true`.
  bool allows(ConsentCategory category) {
    switch (category) {
      case ConsentCategory.necessary:
        return true;
      case ConsentCategory.preferences:
        return preferences;
      case ConsentCategory.statistics:
        return statistics;
      case ConsentCategory.marketing:
        return marketing;
    }
  }

  ConsentState copyWith({
    bool? necessary,
    bool? preferences,
    bool? statistics,
    bool? marketing,
    ConsentMethod? method,
    String? stamp,
    int? ver,
    int? utc,
    String? region,
  }) {
    return ConsentState(
      necessary: necessary ?? this.necessary,
      preferences: preferences ?? this.preferences,
      statistics: statistics ?? this.statistics,
      marketing: marketing ?? this.marketing,
      method: method ?? this.method,
      stamp: stamp ?? this.stamp,
      ver: ver ?? this.ver,
      utc: utc ?? this.utc,
      region: region ?? this.region,
    );
  }

  /// Applies a set of [Choices], flipping the record to an explicit decision.
  ConsentState withChoices(Choices c, {required int utc}) => copyWith(
        necessary: true,
        preferences: c.preferences,
        statistics: c.statistics,
        marketing: c.marketing,
        method: ConsentMethod.explicit,
        utc: utc,
      );

  Map<String, dynamic> toJson() => {
        'necessary': true,
        'preferences': preferences,
        'statistics': statistics,
        'marketing': marketing,
        'method': method.wire,
        'stamp': stamp,
        'ver': ver,
        'utc': utc,
        'region': region,
      };

  /// Restores state from persisted JSON. [necessary] is always coerced to `true`.
  factory ConsentState.fromJson(
    Map<String, dynamic> json, {
    String fallbackRegion = 'unknown',
  }) {
    return ConsentState(
      necessary: true,
      preferences: json['preferences'] as bool? ?? false,
      statistics: json['statistics'] as bool? ?? false,
      marketing: json['marketing'] as bool? ?? false,
      method: ConsentMethod.fromWire(json['method'] as String?),
      stamp: json['stamp'] as String? ?? newStamp(),
      ver: (json['ver'] as num?)?.toInt() ?? 1,
      utc: (json['utc'] as num?)?.toInt() ?? _nowMs(),
      region: json['region'] as String? ?? fallbackRegion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConsentState &&
      other.necessary == necessary &&
      other.preferences == preferences &&
      other.statistics == statistics &&
      other.marketing == marketing &&
      other.method == method &&
      other.stamp == stamp &&
      other.ver == ver &&
      other.utc == utc &&
      other.region == region;

  @override
  int get hashCode => Object.hash(necessary, preferences, statistics, marketing,
      method, stamp, ver, utc, region);
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Generates an RFC-4122 v4 UUID using [Random.secure] (with a graceful fallback
/// to [Random] on the rare platform where a secure source is unavailable).
/// Pure Dart — no plugins, works on mobile and desktop alike.
String newStamp() {
  Random rng;
  try {
    rng = Random.secure();
  } catch (_) {
    rng = Random(DateTime.now().microsecondsSinceEpoch);
  }
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
