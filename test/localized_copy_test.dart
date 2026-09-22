import 'package:cookie_munch/cookie_munch.dart';
import 'package:test/test.dart';

/// The banner's words arrive with the config, in the visitor's language. An app cannot
/// carry forty catalogues, and five SDKs each carrying their own is five chances to
/// disagree about what one banner says.
void main() {
  const body = '''
  {
    "regulation": null,
    "copy": {
      "language": "he",
      "rtl": true,
      "banner": { "title": "הפרטיות שלך חשובה לנו", "acceptAll": "אישור הכול", "rejectAll": "דחיית הכול" },
      "categories": { "statistics": { "label": "סטטיסטיקה", "description": "תיאור" } },
      "reopen": "הגדרות עוגיות"
    }
  }
  ''';

  test('reads the server\'s copy', () {
    final copy = LocalizedCopy.fromConfigJson(body)!;
    expect(copy.language, 'he');
    expect(copy.rtl, isTrue);
    expect(copy.acceptAll, 'אישור הכול');
    expect(copy.categories['statistics']?.label, 'סטטיסטיקה');
    expect(copy.reopen, 'הגדרות עוגיות');
  });

  test('a response without copy is not an error', () {
    expect(LocalizedCopy.fromConfigJson('{"regulation":null}'), isNull);
  });

  test('a malformed body is no copy, never a crash', () {
    expect(LocalizedCopy.fromConfigJson('{not json'), isNull);
    expect(LocalizedCopy.fromConfigJson(''), isNull);
    expect(LocalizedCopy.fromConfigJson('[]'), isNull);
  });

  test('missing fields are null rather than empty strings', () {
    final copy = LocalizedCopy.fromConfigJson(
      '{"copy":{"language":"en","rtl":false,"banner":{},"categories":{},"reopen":""}}',
    )!;
    expect(copy.title, isNull);
    expect(copy.acceptAll, isNull);
    expect(copy.reopen, isNull);
    expect(copy.categories, isEmpty);
  });
}
