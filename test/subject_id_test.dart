// Linking a decision to a signed-in account, so one person's consent correlates across
// web, iOS, Android and desktop. The server has always accepted `subjectId` — validated,
// stored and bound into the hash chain — but only the React Native client ever sent it,
// and only as a constructor argument, which is close to useless: an app builds its
// consent client at launch, before anyone has signed in.
import 'dart:convert';

import 'package:cookie_munch/cookie_munch_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late List<Map<String, dynamic>> bodies;

  http.Client recorder() => MockClient((req) async {
        if (req.body.isNotEmpty) {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return http.Response('', 204);
      });

  CookieMunchConsent client({String? subjectId}) => CookieMunchConsent(
        cbid: 'cb-1',
        apiUrl: 'https://cmp.example.com/',
        region: 'de',
        subjectId: subjectId,
        httpClient: recorder(),
        now: () => 1700000000000,
        stamp: () => 'fixed',
      );

  setUp(() => bodies = []);

  test('no subject id is sent when none is set', () async {
    await client().accept();
    expect(bodies.last.containsKey('subjectId'), isFalse);
  });

  test('an id set after sign-in is attached to later decisions', () async {
    final c = client();
    await c.accept();
    expect(bodies.last.containsKey('subjectId'), isFalse);

    c.subjectId = 'account-42';
    await c.decline();
    expect(bodies.last['subjectId'], 'account-42');
  });

  test('the constructor option still works', () async {
    await client(subjectId: 'account-42').accept();
    expect(bodies.last['subjectId'], 'account-42');
  });

  test('setting it overrides the constructor value', () async {
    final c = client(subjectId: 'from-init');
    c.subjectId = 'after-sign-in';
    await c.accept();
    expect(bodies.last['subjectId'], 'after-sign-in');
  });

  // Signing out must detach the id. Continuing to send it would attribute the next
  // person's decisions on a shared device to the account that just left.
  test('clearing it stops the id being sent', () async {
    final c = client(subjectId: 'account-42');
    c.subjectId = null;
    await c.accept();
    expect(bodies.last.containsKey('subjectId'), isFalse);
  });

  test('an empty string clears it rather than sending an empty id', () async {
    final c = client(subjectId: 'account-42');
    c.subjectId = '';
    await c.accept();
    expect(bodies.last.containsKey('subjectId'), isFalse);
    expect(c.subjectId, isNull);
  });

  test('it is readable back', () {
    final c = client();
    expect(c.subjectId, isNull);
    c.subjectId = 'account-42';
    expect(c.subjectId, 'account-42');
  });

  // Who is signed in is the app's business and can change between launches, so a stale
  // account id baked into a restored record would attribute one person's consent to
  // another.
  test('it is not persisted with the decision', () async {
    final storage = InMemoryConsentStorage();
    final c = CookieMunchConsent(
      cbid: 'cb-1',
      apiUrl: 'https://cmp.example.com/',
      region: 'de',
      subjectId: 'account-42',
      storage: storage,
      httpClient: recorder(),
      now: () => 1700000000000,
      stamp: () => 'fixed',
    );
    await c.accept();
    expect(await storage.read(c.storageKey), isNot(contains('account-42')));
  });
}
