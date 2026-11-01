import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wedding_app/api.dart';
import 'package:wedding_app/main.dart';
import 'package:wedding_app/state.dart';
import 'package:wedding_app/ui.dart';

/// A tiny in-memory stand-in for the API, enough to drive the first-run flow.
class FakeServer {
  final calls = <String>[];
  Map<String, dynamic>? wedding;

  Map<String, dynamic> summary() => {
        'wedding': wedding,
        'role': 'owner',
        'events': [
          {'id': 'e1', 'kind': 'poruwa', 'title': null, 'starts_at': '2027-05-20T04:30:00.000Z', 'venue': 'Cinnamon Grand'}
        ],
        'counts': {'guests': 0, 'sent': 0, 'opened': 0, 'replied': 0, 'seats': 0},
        'plan': {'plan': 'free', 'limits': {'guests': 50}},
        'nextStep': {'key': 'choose_template', 'label': 'Choose an invitation design'},
        'suggestAdvanced': false,
      };

  Future<http.Response> handle(http.Request r) async {
    final path = '${r.method} ${r.url.path}';
    calls.add(path);
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    Map<String, dynamic> out;
    switch (path) {
      case 'POST /api/auth/email/start':
        out = {'sent': true, 'devCode': '123456'};
      case 'POST /api/auth/email/verify':
        if (body['code'] != '123456') return http.Response(jsonEncode({'error': 'invalid_code', 'message': 'That code is wrong or has expired.'}), 401);
        out = {'token': 'tok'};
      case 'GET /api/me':
        out = {'user': {'id': 'u1', 'email': 'nimal@example.com', 'locale': 'en', 'staff_role': null}};
      case 'GET /api/weddings':
        out = {'weddings': wedding == null ? [] : [wedding]};
      case 'POST /api/weddings':
        expect(body['partner1'], 'Nimal');
        expect(body['event']['starts_at'], endsWith('Z'));
        wedding = {'id': 'w1', 'partner1': body['partner1'], 'partner2': body['partner2'], 'mode': body['mode'], 'language': 'en', 'kind': body['kind'], 'invitation': {}};
        out = summary();
      case 'GET /api/templates':
        out = {'templates': []};
      case 'GET /api/weddings/w1/guests':
        out = {'guests': []};
      case 'GET /api/weddings/w1/guests/duplicates':
        out = {'pairs': []};
      case 'GET /api/weddings/w1/dashboard':
        out = {'totals': {'invited': 0, 'sent': 0, 'opened': 0}, 'events': [], 'recentMessages': []};
      case 'GET /api/weddings/w1/follow-ups':
        out = {'guests': []};
      case 'GET /api/weddings/w1':
        out = summary();
      default:
        return http.Response(jsonEncode({'error': 'not_found', 'message': 'no route $path'}), 404);
    }
    return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json'});
  }
}

void main() {
  test('event times are stored as Sri Lanka time', () {
    expect(slToIso(DateTime(2027, 5, 20), const TimeOfDay(hour: 10, minute: 0)), '2027-05-20T04:30:00.000Z');
    expect(fmtSl('2027-05-20T04:30:00.000Z'), '20 May 2027, 10:00 am');
  });

  testWidgets('sign in, then the first-run flow creates a wedding and shows the next step', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final server = FakeServer();
    final state = AppState(Api(baseUrl: 'http://test', client: MockClient(server.handle)));
    await state.init();
    await tester.pumpWidget(WeddingApp(state: state));
    await tester.pumpAndSettle();

    // Sign in with an email code.
    await tester.enterText(find.byKey(const Key('address')), 'nimal@example.com');
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Development code: 123456'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    // What are you planning → Easy Mode → names and date.
    expect(find.text('What are you planning?'), findsOneWidget);
    await tester.tap(find.text('Wedding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start simple'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('p1')), 'Nimal');
    await tester.enterText(find.byKey(const Key('p2')), 'Kumari');
    await tester.tap(find.byKey(const Key('create')));
    await tester.pumpAndSettle();
    expect(find.text('Please add both names and the date.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('venue')), 'Cinnamon Grand');
    await tester.ensureVisible(find.byKey(const Key('create')));
    await tester.tap(find.byKey(const Key('create')));
    await tester.pumpAndSettle();

    // Easy Mode home: one clear next step, four tabs, no Plan tab.
    expect(server.calls, contains('POST /api/weddings'));
    expect(find.text('Choose an invitation design'), findsOneWidget);
    expect(find.text('Nimal & Kumari'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });
}
