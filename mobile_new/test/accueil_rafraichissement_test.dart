import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';

import 'aides/code_seul.dart';

/// Quand l'accueil a-t-il le droit de redemander les pronostics du jour ?
///
/// ── Le defaut ─────────────────────────────────────────────────────────────
///
/// Le minuteur ne posait qu'une question : y a-t-il un match en direct ? Il
/// ignorait deux choses que l'utilisateur, lui, voit tres bien :
///
///   · `AccueilPage` reste vivante quand on passe a un autre onglet ;
///   · un `Timer` Dart continue quand l'application part en arriere-plan.
///
/// Un match en cours pendant que le telephone est dans une poche, c'etait donc
/// une requete toutes les 45 secondes — 80 par heure — pour un ecran que
/// personne ne regardait. Sur un forfait de donnees compte et une batterie
/// modeste, ce sont deux couts reels pour un benefice nul.
///
/// ── Ce que ce banc tient ──────────────────────────────────────────────────
///
/// Que les trois conditions restent liees. Chacune prise seule laisse passer
/// exactement le gaspillage que les deux autres evitent, et une regle qui n'en
/// verifie que deux se relacherait sans que rien ne le dise.
void main() {
  group('les trois conditions doivent tenir ensemble', () {
    test('en direct, onglet regarde, application au premier plan', () {
      expect(
        doitRafraichirEnDirect(
          enDirect:      true,
          ongletVisible: true,
          cycle:         AppLifecycleState.resumed,
        ),
        isTrue,
        reason: "c'est le seul cas ou le rafraichissement sert a quelque chose",
      );
    });

    test('rien en direct : il n y a rien a suivre', () {
      expect(
        doitRafraichirEnDirect(
          enDirect:      false,
          ongletVisible: true,
          cycle:         AppLifecycleState.resumed,
        ),
        isFalse,
      );
    });

    test('onglet cache : la page est vivante mais personne ne la voit', () {
      expect(
        doitRafraichirEnDirect(
          enDirect:      true,
          ongletVisible: false,
          cycle:         AppLifecycleState.resumed,
        ),
        isFalse,
        reason: 'la pile garde les onglets deja ouverts en vie — leurs '
            'minuteurs doivent se taire, pas leur etat disparaitre',
      );
    });
  });

  group('hors du premier plan, rien ne part', () {
    for (final etat in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ]) {
      test('${etat.name} ne declenche aucune requete', () {
        expect(
          doitRafraichirEnDirect(
            enDirect:      true,
            ongletVisible: true,
            cycle:         etat,
          ),
          isFalse,
          reason: 'seul `resumed` designe une application reellement affichee ; '
              'traiter `inactive` comme visible rallumerait le minuteur a '
              "chaque appel entrant ou volet de reglages tire",
        );
      });
    }
  });

  group('le mecanisme est reellement branche', () {
    test('la pile paresseuse remplace IndexedStack dans la barre', () {
      // Une protection qu on ecrit sans la brancher ne protege rien : c est
      // exactement le defaut que ce projet traque ailleurs. Filtre par
      // `codeSeul`, sinon le commentaire d en face — qui doit nommer
      // IndexedStack pour expliquer ce qu il coutait — validerait le banc
      // tout seul.
      final code = File('lib/shared/widgets/main_scaffold.dart')
          .readAsStringSync()
          .pipeCodeSeul();

      expect(code, contains('PileOngletsParesseuse('),
          reason: 'la barre doit passer par la pile paresseuse');
      expect(code, isNot(contains('IndexedStack(')),
          reason: "sinon les cinq onglets repartent en meme temps et l'on a "
              'ecrit la pile pour rien');
    });

    test('l accueil lit sa visibilite et le cycle de vie', () {
      final code = File('lib/features/accueil/presentation/pages/accueil_page.dart')
          .readAsStringSync()
          .pipeCodeSeul();

      expect(code, contains('OngletVisible.de(context)'),
          reason: 'sans cette lecture, `ongletVisible` resterait a sa valeur '
              'initiale et la condition serait toujours vraie');
      expect(code, contains('WidgetsBindingObserver'),
          reason: 'sans observateur, `cycle` ne changerait jamais');
      expect(code, contains('removeObserver'),
          reason: 'un observateur ajoute et jamais retire fuit a chaque '
              'ouverture de la page');
      expect(code, contains('doitRafraichirEnDirect('),
          reason: 'la decision testee ici doit etre celle que le minuteur '
              'appelle, pas une copie parallele');
    });
  });
}
