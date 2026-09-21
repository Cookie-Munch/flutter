/// Which privacy regime applies to a person, and what that means for the app.
///
/// A Dart port of `packages/geo/src/regulation.ts` — the same table as the web
/// embed and the iOS/Android SDKs, so the four cannot disagree about someone's
/// rights. Resolving locally costs nothing and works offline, but see
/// [CookieMunchConsent.refreshRegulation]: a device's locale says where the phone
/// was sold, not where its owner is standing.
library;

import 'dart:convert';

/// Opt-in ("ask before anything fires") vs opt-out ("fire, but honour a refusal").
enum ConsentModel {
  optIn('opt-in'),
  optOut('opt-out');

  const ConsentModel(this.wire);

  /// The value as it appears on the wire and in the other three ports.
  final String wire;

  /// Lenient parse — an unrecognised value degrades to the safe direction rather
  /// than throwing, so a server that learns a new regime tomorrow cannot crash an
  /// app shipped today.
  static ConsentModel from(Object? value) =>
      ConsentModel.values.firstWhere((m) => m.wire == value, orElse: () => ConsentModel.optIn);
}

enum RegionClass {
  eu('eu'),
  us('us'),
  br('br'),
  ca('ca'),
  other('other');

  const RegionClass(this.wire);

  final String wire;

  static RegionClass from(Object? value) =>
      RegionClass.values.firstWhere((c) => c.wire == value, orElse: () => RegionClass.other);
}

/// The signalling framework third parties will read.
enum SignalFramework {
  tcf('tcf'),
  gpp('gpp'),
  none('none');

  const SignalFramework(this.wire);

  final String wire;

  static SignalFramework from(Object? value) =>
      SignalFramework.values.firstWhere((f) => f.wire == value, orElse: () => SignalFramework.none);
}

/// The US state law governing a visitor, when one does.
///
/// There are around twenty comprehensive state laws and they differ on what a consent
/// UI must do: whether a universal opt-out signal must be honoured, whether sensitive
/// data needs opt-in, and the age below which a minor needs consent. Only the server
/// can say which one applies — a device's locale gives a country at best, never a state
/// — so this is populated from `/config/:cbid` and is null when resolving locally.
class UsStateLaw {
  const UsStateLaw({
    required this.id,
    required this.state,
    required this.name,
    required this.universalOptOut,
    required this.sensitiveOptIn,
    required this.minorOptInUnder,
  });

  /// Stable id, e.g. `tdpsa`.
  final String id;

  /// Two-letter state code.
  final String state;
  final String name;

  /// The law requires honouring a universal opt-out signal.
  final bool universalOptOut;

  /// Sensitive data needs opt-in consent rather than an opt-out.
  final bool sensitiveOptIn;

  /// Opt-in required below this age for sale / targeted advertising; 0 = no rule.
  final int minorOptInUnder;

  static UsStateLaw? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final state = value['state'];
    if (id is! String || state is! String) return null;
    return UsStateLaw(
      id: id,
      state: state,
      name: value['name'] is String ? value['name'] as String : id,
      universalOptOut: value['universalOptOutInForce'] == true || value['universalOptOut'] == true,
      sensitiveOptIn: value['sensitiveOptIn'] == true,
      minorOptInUnder: value['minorOptInUnder'] is num ? (value['minorOptInUnder'] as num).toInt() : 0,
    );
  }
}

/// The resolved regime for one person.
class Regulation {
  const Regulation({
    required this.region,
    required this.regionClass,
    required this.gdprApplies,
    required this.ccpaApplies,
    required this.lgpdApplies,
    required this.model,
    required this.defaultGranted,
    required this.framework,
    required this.forcedOptOut,
    required this.consentRequired,
    this.stateLaw,
  });

  /// ISO 3166-1 alpha-2, optionally with a subdivision (`us-ca`).
  final String region;
  final RegionClass regionClass;
  final bool gdprApplies;
  final bool ccpaApplies;
  final bool lgpdApplies;
  final ConsentModel model;

  /// What categories default to before the person has said anything.
  final bool defaultGranted;
  final SignalFramework framework;

  /// A browser/OS-level signal (GPC, DNT) already expressed a refusal for them.
  final bool forcedOptOut;

  /// Whether a decision still has to be collected. See
  /// [CookieMunchConsent.isConsentRequired], which also accounts for a decision
  /// this person already made in the app.
  final bool consentRequired;

  /// The US state law governing this person, when the server resolved one. Null
  /// when resolving locally: a device cannot know which state someone is in.
  final UsStateLaw? stateLaw;

  // EU 27 + EEA + UK, lowercase ISO 3166-1 alpha-2.
  static const Set<String> _euEeaUk = {
    'at', 'be', 'bg', 'hr', 'cy', 'cz', 'dk', 'ee', 'fi', 'fr', 'de', 'gr', 'hu', 'ie',
    'it', 'lv', 'lt', 'lu', 'mt', 'nl', 'pl', 'pt', 'ro', 'sk', 'si', 'es', 'se',
    'is', 'li', 'no',
    'gb', 'uk',
  };

  static RegionClass classify(String? region) {
    if (region == null || region.isEmpty) return RegionClass.other;
    final country = region.toLowerCase().split('-').first;
    if (_euEeaUk.contains(country)) return RegionClass.eu;
    if (country == 'us') return RegionClass.us;
    if (country == 'br') return RegionClass.br;
    if (country == 'ca') return RegionClass.ca;
    return RegionClass.other;
  }

  /// Resolve the regime for [region] and the opt-out signals available on device.
  ///
  /// [honorDnt] treats [dnt] as a refusal (default `true`). [unknownModel] is the
  /// regime for regions we don't recognise — opt-in by default, which is the safe
  /// direction to be wrong in.
  static Regulation resolve(
    String? region, {
    bool gpc = false,
    bool dnt = false,
    bool honorDnt = true,
    ConsentModel unknownModel = ConsentModel.optIn,
  }) {
    final cls = classify(region);

    final ConsentModel model;
    final SignalFramework framework;
    switch (cls) {
      case RegionClass.us:
        model = ConsentModel.optOut;
        framework = SignalFramework.gpp;
      case RegionClass.eu:
        model = ConsentModel.optIn;
        framework = SignalFramework.tcf;
      case RegionClass.br:
      case RegionClass.ca:
        model = ConsentModel.optIn;
        framework = SignalFramework.none;
      case RegionClass.other:
        model = unknownModel;
        framework = SignalFramework.none;
    }

    // GPC/DNT only matter where collection would otherwise proceed. Under an
    // opt-in regime nothing fires before consent anyway, so there is nothing to
    // force.
    final forced = model == ConsentModel.optOut && (gpc || (honorDnt && dnt));

    return Regulation(
      region: region ?? '',
      regionClass: cls,
      gdprApplies: cls == RegionClass.eu,
      ccpaApplies: cls == RegionClass.us,
      lgpdApplies: cls == RegionClass.br,
      model: model,
      defaultGranted: model == ConsentModel.optOut,
      framework: framework,
      forcedOptOut: forced,
      consentRequired: !forced,
    );
  }

  /// Parse the `regulation` block of a `/config/:cbid` response. Returns `null`
  /// when the block is absent (an older server) or malformed — the caller then
  /// keeps whatever it resolved locally.
  static Regulation? fromConfigJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final reg = decoded['regulation'];
      if (reg is! Map) return null;
      final flags = reg['regulations'] is Map ? reg['regulations'] as Map : const {};
      final forced = reg['forcedOptOut'] == true;
      return Regulation(
        region: reg['region'] is String ? reg['region'] as String : '',
        regionClass: RegionClass.from(reg['class']),
        gdprApplies: flags['gdprApplies'] == true,
        ccpaApplies: flags['ccpaApplies'] == true,
        lgpdApplies: flags['lgpdApplies'] == true,
        model: ConsentModel.from(reg['model']),
        defaultGranted: reg['defaultState'] == 'granted',
        framework: SignalFramework.from(reg['framework']),
        forcedOptOut: forced,
        // An older server could omit this. Defaulting a missing bool to false
        // would silently suppress every prompt, so it is derived instead.
        consentRequired: reg.containsKey('consentRequired') ? reg['consentRequired'] == true : !forced,
        stateLaw: UsStateLaw.fromJson(reg['stateLaw']),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      'Regulation(region: $region, class: ${regionClass.wire}, model: ${model.wire}, '
      'gdpr: $gdprApplies, ccpa: $ccpaApplies, lgpd: $lgpdApplies, '
      'framework: ${framework.wire}, forcedOptOut: $forcedOptOut, consentRequired: $consentRequired'
      '${stateLaw == null ? '' : ', stateLaw: ${stateLaw!.id}'})';
}
