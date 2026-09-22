import 'dart:convert';

/// The banner's words in the visitor's language, resolved by the server.
///
/// Forty languages will not fit in an app bundle, and five native SDKs each shipping their
/// own catalogue is five chances to disagree about what one banner says. So the platform
/// resolves the copy the same way it resolves the regulatory regime — once, server-side —
/// and this is that answer. It is null until [CookieMunchConsent.refreshRegulation] has run;
/// the banner falls back to its English strings, so an app that has never reached the
/// network still asks.
class LocalizedCopy {
  const LocalizedCopy({
    required this.language,
    required this.rtl,
    required this.categories,
    this.title,
    this.body,
    this.acceptAll,
    this.rejectAll,
    this.save,
    this.customize,
    this.reopen,
  });

  /// The language actually used, which may be the site's default rather than the one asked for.
  final String language;

  /// Written right to left. A banner mirrors its layout, not merely its text.
  final bool rtl;

  final String? title;
  final String? body;
  final String? acceptAll;
  final String? rejectAll;
  final String? save;
  final String? customize;

  /// Keyed by category id: necessary, preferences, statistics, marketing.
  final Map<String, CategoryText> categories;

  /// The label on the affordance that reopens the prompt.
  final String? reopen;

  /// Reads the `copy` block of a `/config/:cbid` response. Null when absent or malformed —
  /// a damaged body must never crash a banner, it just falls back to English.
  static LocalizedCopy? fromConfigJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      final copy = decoded['copy'];
      if (copy is! Map<String, dynamic>) return null;
      final banner = copy['banner'] is Map<String, dynamic>
          ? copy['banner'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final categories = <String, CategoryText>{};
      final rawCategories = copy['categories'];
      if (rawCategories is Map<String, dynamic>) {
        rawCategories.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            categories[key] = CategoryText(
              label: value['label'] as String? ?? '',
              description: value['description'] as String? ?? '',
            );
          }
        });
      }
      String? text(String key) {
        final value = banner[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      final reopen = copy['reopen'];
      return LocalizedCopy(
        language: copy['language'] as String? ?? 'en',
        rtl: copy['rtl'] == true,
        title: text('title'),
        body: text('body'),
        acceptAll: text('acceptAll'),
        rejectAll: text('rejectAll'),
        save: text('save'),
        customize: text('customize'),
        categories: categories,
        reopen: reopen is String && reopen.isNotEmpty ? reopen : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What one category is called, and what it means.
class CategoryText {
  const CategoryText({required this.label, required this.description});
  final String label;
  final String description;
}
