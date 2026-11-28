import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/services/review_service.dart';

/// Refus Apple du 2 novembre 2026 (règle 5.6.3) : la note était demandée au
/// lancement. Elle ne l'est plus qu'après une vraie utilisation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('dev.britannio.in_app_review');
  late List<String> appels;

  setUp(() {
    appels = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      appels.add(c.method);
      return c.method == 'isAvailable' ? true : null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(canal, null));

  int ilYA(int jours) => DateTime.now().subtract(Duration(days: jours)).millisecondsSinceEpoch;
  bool aDemande() => appels.contains('requestReview');

  test('au lancement : jamais, même après des dizaines d\'ouvertures', () async {
    SharedPreferences.setMockInitialValues({'review_first_session_ms': ilYA(60), 'review_session_count': 40,
      'review_meaningful_engagement_count': 10});
    for (var i = 0; i < 5; i++) {
      await ReviewService.onSessionStart();
    }
    expect(appels, isEmpty);
    expect((await SharedPreferences.getInstance()).getInt('review_session_count'), 45);
  });

  test('première ouverture : la date est notée, une seule fois', () async {
    SharedPreferences.setMockInitialValues({});
    await ReviewService.onSessionStart();
    final prefs = await SharedPreferences.getInstance();
    final premiere = prefs.getInt('review_first_session_ms');
    expect(premiere, isNotNull);
    await ReviewService.onSessionStart();
    expect(prefs.getInt('review_first_session_ms'), premiere);
  });

  test('fiche lue après une vraie utilisation : la note est demandée, puis plus pendant 30 jours', () async {
    SharedPreferences.setMockInitialValues({'review_first_session_ms': ilYA(8), 'review_session_count': 5,
      'review_meaningful_engagement_count': 2});
    await ReviewService.consultationReelle();
    expect(aDemande(), isTrue);
    appels.clear();
    for (var i = 0; i < 4; i++) {
      await ReviewService.consultationReelle();
    }
    expect(aDemande(), isFalse);
  });

  test('trop tôt : moins de 7 jours, de 5 ouvertures ou de 3 fiches lues', () async {
    for (final etat in [
      {'review_first_session_ms': ilYA(6), 'review_session_count': 20, 'review_meaningful_engagement_count': 9},
      {'review_first_session_ms': ilYA(30), 'review_session_count': 4, 'review_meaningful_engagement_count': 9},
      {'review_first_session_ms': ilYA(30), 'review_session_count': 20, 'review_meaningful_engagement_count': 1},
      {'review_session_count': 20, 'review_meaningful_engagement_count': 9},
    ]) {
      SharedPreferences.setMockInitialValues(etat);
      await ReviewService.consultationReelle();
      expect(aDemande(), isFalse, reason: '$etat');
    }
  });

  test('demandée il y a moins de 30 jours (ancienne version comprise) : pas de nouveau', () async {
    SharedPreferences.setMockInitialValues({'review_first_session_ms': ilYA(90), 'review_session_count': 50,
      'review_meaningful_engagement_count': 9, 'review_last_asked_ms': ilYA(29)});
    await ReviewService.consultationReelle();
    expect(aDemande(), isFalse);
  });
}
