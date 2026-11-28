import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/compte/presentation/pages/edit_profile_page.dart';
import 'package:pronowin/features/compte/presentation/providers/compte_provider.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// « Modifier le profil », refait le 11 novembre 2026 : cartes, erreurs sous
/// le champ, « Enregistrer » actif seulement s'il y a un changement, et
/// confirmation avant de quitter sans enregistrer.
void main() {
  setUpAll(() async => preparerBanc());

  const profil = {
    'pseudo': 'Awa226', 'email': 'awa@exemple.com', 'first_name': 'Awa', 'last_name': 'Ouédraogo',
    'birth_date': '1999-01-22', 'country_code': 'BF', 'phone_number': '+22670000000',
  };

  Future<_Serveur> monter(WidgetTester t, {double largeur = 390, double echelle = 1}) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = Size(largeur, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final serveur = _Serveur();
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _Moi(ref)),
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur),
        profileProvider.overrideWith((ref) async => Map.of(profil)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/edit', routes: [
          GoRoute(path: '/edit', builder: (_, _) => const _Attendre()),
          GoRoute(path: '/compte', builder: (_, _) => const Scaffold(body: Text('page-compte'))),
        ]),
        theme: AppTheme.dark,
        locale: const Locale('fr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
          child: child!),
      ),
    ));
    await t.pumpAndSettle();
    return serveur;
  }

  Future<void> fin(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  ElevatedButton bouton(WidgetTester t) => t.widget<ElevatedButton>(find.byKey(const Key('enregistrer-profil')));

  testWidgets('à l\'ouverture : rien à enregistrer, pas d\'erreur', (t) async {
    await monter(t);
    expect(find.text('Identité'), findsOneWidget);
    expect(find.text('Compte'), findsOneWidget);
    expect(find.text('@Awa226'), findsOneWidget);
    expect(find.text('Aucune modification'), findsOneWidget);
    expect(bouton(t).onPressed, isNull);
    expect(find.text('Minimum 3 caractères'), findsNothing);
    await fin(t);
  });

  testWidgets('une erreur s\'affiche sous le champ, et rien ne part', (t) async {
    final serveur = await monter(t);
    await t.enterText(find.descendant(of: find.byKey(const Key('champ-pseudo')), matching: find.byType(TextField)), 'ab');
    await t.enterText(find.descendant(of: find.byKey(const Key('champ-email')), matching: find.byType(TextField)), 'awa@');
    await t.pump();
    expect(find.text('Minimum 3 caractères'), findsOneWidget);
    expect(find.text('Adresse e-mail invalide'), findsOneWidget);
    expect(bouton(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('enregistrer-profil')));
    await t.pump();
    expect(find.text('Corrige les champs en rouge.'), findsOneWidget);
    expect(serveur.envois, isEmpty);
    await fin(t);
  });

  testWidgets('un changement valide s\'enregistre et ramène au compte', (t) async {
    final serveur = await monter(t);
    await t.enterText(find.descendant(of: find.byKey(const Key('champ-prenom')), matching: find.byType(TextField)), 'Aïcha');
    await t.pump();
    expect(find.text('Enregistrer'), findsOneWidget);
    await t.tap(find.byKey(const Key('enregistrer-profil')));
    await t.pumpAndSettle();
    final envoi = serveur.envois.singleWhere((e) => e.chemin == '/profile');
    expect(envoi.donnees['first_name'], 'Aïcha');
    expect(envoi.donnees['pseudo'], 'Awa226');
    expect(envoi.donnees['phone_number'], '+22670000000');
    expect(envoi.donnees['country_code'], 'BF');
    expect(find.text('page-compte'), findsOneWidget);
    await fin(t);
  });

  testWidgets('quitter avec des changements demande confirmation', (t) async {
    await monter(t);
    await t.enterText(find.descendant(of: find.byKey(const Key('champ-nom')), matching: find.byType(TextField)), 'Traoré');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await t.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    await t.tap(find.text('Continuer'));
    await t.pumpAndSettle();
    expect(find.text('page-compte'), findsNothing);
    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('abandonner-modifications')));
    await t.pumpAndSettle();
    expect(find.text('page-compte'), findsOneWidget);
    await fin(t);
  });

  testWidgets('sans changement, le retour est immédiat', (t) async {
    await monter(t);
    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await t.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsNothing);
    expect(find.text('page-compte'), findsOneWidget);
    await fin(t);
  });

  testWidgets('petit écran, texte agrandi : rien ne déborde', (t) async {
    await monter(t, largeur: 320, echelle: 1.8);
    for (var i = 0; i < 6; i++) {
      await t.drag(find.byType(ListView).first, const Offset(0, -300));
      await t.pump();
    }
    expect(t.takeException(), isNull);
    await fin(t);
  });
}

/// Un compte connecté dont l'actualisation ne fait rien : le vrai dépôt
/// d'authentification n'a pas sa place dans ce banc.
class _Moi extends AuthNotifier {
  _Moi(Ref ref)
      : super(ref.watch(sendOtpUseCaseProvider), ref.watch(verifyOtpUseCaseProvider),
            ref.watch(authRepositoryProvider)) {
    state = AuthAuthenticated(utilisateurGratuit);
  }
  @override
  Future<void> refreshUser() async {}
}

/// Attend le profil avant de monter la page, qui le lit à l'ouverture.
class _Attendre extends ConsumerWidget {
  const _Attendre();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(profileProvider).hasValue ? const EditProfilePage() : const Scaffold();
}

/// Garde ce que la page envoie ; répond 200 à tout.
class _Serveur implements HttpClientAdapter {
  final envois = <({String chemin, Map<String, dynamic> donnees})>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    if (o.method == 'PATCH') {
      envois.add((chemin: o.path, donnees: Map<String, dynamic>.from(o.data as Map)));
    }
    return ResponseBody.fromString(jsonEncode({}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}
