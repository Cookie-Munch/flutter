// Prints the bridge output for a fixed state so it can be captured into
// packages/core/test/fixtures-dart-bridge.json and checked against the real web
// reader. A page must not be able to tell which platform seeded it.
import 'package:cookie_munch/cookie_munch_core.dart';
import 'package:test/test.dart';

void main() {
  test('print fixture', () {
    const state = ConsentState(
      preferences: true,
      statistics: false,
      marketing: true,
      method: ConsentMethod.explicit,
      stamp: 'abc-123',
      ver: 1,
      utc: 1700000000000,
      region: 'de',
    );
    print('DART_JS>>>${WebViewBridge.javaScript(state)}<<<');
    print('DART_QS>>>${WebViewBridge.queryString(state)}<<<');
  });
}
