import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';

import 'aides/banc_ecran.dart';

/// Les équipes et ligues suivies, connues du serveur pour leurs alertes
/// (15 novembre 2026) : elles ne vivaient que sur le téléphone.
class _Serveur implements HttpClientAdapter {
  Map<String, dynamic> suivis;
  final envois = <Map<String, dynamic>>[];
  bool enPanne = false;
  _Serveur(this.suivis);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    Object? corps;
    if (!enPanne) {
      if (o.path == '/favorites') {
        corps = <Object>[];
      } else if (o.path == '/favorites/suivis' && o.method == 'GET') {
        corps = suivis;
      } else if (o.path == '/favorites/suivis' && o.method == 'PUT') {
        final d = Map<String, dynamic>.from(o.data as Map);
        envois.add(d);
        suivis = {...suivis, ...d};
        corps = suivis;
      }
    }
    return ResponseBody.fromString(jsonEncode(corps ?? {'message': 'absent'}), corps == null ? 503 : 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => preparerBanc());

  const bayern = EquipeSuivie(id: 157, nom: 'Bayern München', logo: 'b.png', competition: 'BL1');
  const arsenal = EquipeSuivie(id: 42, nom: 'Arsenal', logo: 'a.png');

  ProviderContainer conteneur(_Serveur serveur) {
    final c = ProviderContainer(overrides: [
      ...donneesCommunes(favoris: FavorisNotifier.new),
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur),
    ]);
    addTearDown(c.dispose);
    // Écouté, comme par un écran : un fournisseur que personne n'écoute ne
    // se reconstruit pas quand les réglages changent au démarrage.
    c.listen(favorisProvider, (_, _) {});
    return c;
  }

  test('premier passage : ce que le téléphone suivait s\'ajoute à ce que le serveur connaît', () async {
    SharedPreferences.setMockInitialValues({
      cleFavorisLigues('u1'): ['Serie A', 'La Liga'],
      cleFavorisEquipes('u1'): [jsonEncode(bayern.toJson())],
    });
    final serveur = _Serveur({'ligues': ['La Liga'], 'equipes': [arsenal.toJson()]});
    final etat = await conteneur(serveur).read(favorisProvider.future);
    expect(etat.ligues, {'La Liga', 'Serie A'});
    expect(etat.equipes.map((e) => e.id), [42, 157]);
    expect(serveur.envois, hasLength(1));
    expect(serveur.envois.single['ligues'], unorderedEquals(['La Liga', 'Serie A']));
    expect((serveur.envois.single['equipes'] as List).map((e) => (e as Map)['id']), [42, 157]);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(cleFavorisSuivisSynchro('u1')), isTrue);
    expect(p.getStringList(cleFavorisEquipes('u1')), hasLength(2));
  });

  test('ensuite, le serveur fait foi : un retrait sur un autre appareil vaut ici aussi', () async {
    SharedPreferences.setMockInitialValues({
      cleFavorisLigues('u1'): ['Serie A', 'La Liga'],
      cleFavorisSuivisSynchro('u1'): true,
    });
    final serveur = _Serveur({'ligues': ['La Liga'], 'equipes': <Object>[]});
    final etat = await conteneur(serveur).read(favorisProvider.future);
    expect(etat.ligues, {'La Liga'});
    expect(serveur.envois, isEmpty);
    expect((await SharedPreferences.getInstance()).getStringList(cleFavorisLigues('u1')), ['La Liga']);
  });

  test('suivre ou ne plus suivre : le serveur suit', () async {
    SharedPreferences.setMockInitialValues({});
    final serveur = _Serveur({'ligues': <Object>[], 'equipes': <Object>[]});
    final c = conteneur(serveur);
    await c.read(favorisProvider.future);
    await c.read(favorisProvider.notifier).basculerLigue('Premier League');
    await c.read(favorisProvider.notifier).basculerEquipe(arsenal);
    expect(serveur.envois, [
      {'ligues': ['Premier League']},
      {'equipes': [arsenal.toJson()]},
    ]);
    await c.read(favorisProvider.notifier).basculerLigue('Premier League');
    expect(serveur.envois.last, {'ligues': <String>[]});
  });

  test('serveur injoignable : la copie locale, et rien n\'est envoyé avant le premier passage', () async {
    SharedPreferences.setMockInitialValues({cleFavorisLigues('u1'): ['Serie A']});
    final serveur = _Serveur({})..enPanne = true;
    final c = conteneur(serveur);
    final etat = await c.read(favorisProvider.future);
    expect(etat.ligues, {'Serie A'});
    await c.read(favorisProvider.notifier).basculerLigue('La Liga');
    expect(c.read(favorisProvider).value!.ligues, {'Serie A', 'La Liga'});
    expect(serveur.envois, isEmpty);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(cleFavorisSuivisSynchro('u1')), isNull);
  });

  test('la déconnexion efface aussi la trace du premier passage', () async {
    SharedPreferences.setMockInitialValues({cleFavorisSuivisSynchro('u1'): true});
    await effacerFavorisLocaux(resilierSujets: false);
    expect((await SharedPreferences.getInstance()).getBool(cleFavorisSuivisSynchro('u1')), isNull);
  });
}
