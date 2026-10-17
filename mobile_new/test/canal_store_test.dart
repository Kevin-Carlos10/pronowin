import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/parametres/presentation/pages/legal_page.dart';

/// Ce qu'un build publié sur les stores n'a pas le droit de contenir.
///
/// `distribution_channel.dart` énumère ce que le canal gouverne : paiement
/// Mobile Money, tarif, **renvoi vers le bookmaker**, offre « code promo »,
/// chemin de mise à jour. C'était une promesse en commentaire — et l'une
/// d'elles n'était pas tenue.
///
/// La barre `BookmakerCotes` de l'onglet Cotes, un lien d'affiliation cliquable
/// vers un opérateur de paris, partait dans le paquet soumis à Google et Apple.
/// Seule la fenêtre de mise appliquait la règle.
///
/// Rien ne pouvait le voir : l'écran rendait parfaitement, l'analyseur ne
/// signalait rien, et le drapeau existait bel et bien — il n'était simplement
/// pas consulté à cet endroit. D'où ce garde-fou textuel : il porte sur la
/// structure du code, seule chose vérifiable sans exécuter les deux builds.
void main() {
  /// Surfaces qui exposent un opérateur de paris ou un paiement hors store,
  /// avec le fichier où elles sont montées.
  const surfaces = <String, ({String fichier, String motif})>{
    'barre d\'affiliation bookmaker': (
      fichier: 'lib/features/pronostics/presentation/pages/match_detail_page.dart',
      motif:   'BookmakerCotes(',
    ),
    // Le motif vise le **point de montage**, pas une mention : la fonction
    // utilitaire qui construit le lien vit plus haut dans le fichier et n'a
    // rien a etre conditionnee.
    'renvoi bookmaker depuis la mise': (
      fichier: 'lib/features/bankroll/presentation/widgets/miser_dialog.dart',
      motif:   'onTap: _ouvrirPartenaire',
    ),
    // Le retrait des récompenses de parrainage en argent réel.
    //
    // Le parrainage lui-même ne pose pas de problème, et offrir des jours
    // Premium revient à offrir son propre produit. C'est la combinaison qui
    // expose : une application de pronostics sportifs, où l'on accumule un
    // solde, que l'on peut faire sortir en espèces. Séparément anodins,
    // ensemble ils dessinent ce qu'un examinateur cherche quand il évalue la
    // catégorie « jeux d'argent réel ».
    //
    // Sur Play, la récompense se convertit en jours Premium. Le retrait reste
    // entier sur le canal direct.
    'retrait des récompenses de parrainage': (
      fichier: 'lib/features/parrainage/presentation/pages/parrainage_page.dart',
      // Le motif vise la navigation vers l'écran de retrait, pas la ligne qui
      // porte la garde : celle-ci est en ligne sur `canWithdraw`, donc elle ne
      // *précède* pas un motif posé sur elle-même. Viser le `push` place la
      // garde avant, et cible d'ailleurs ce qui compte — l'accès à l'écran.
      motif:   "onWithdraw: () => context.push('/parrainage/retrait'",
    ),
  };

  String lire(String chemin) {
    final f = File(chemin);
    if (!f.existsSync()) fail('Fichier introuvable : $chemin');
    return f.readAsStringSync();
  }

  group('le canal store masque les surfaces de jeu d\'argent', () {
    for (final e in surfaces.entries) {
      test('${e.key} est conditionnée au canal', () {
        final source = lire(e.value.fichier);
        final index  = source.indexOf(e.value.motif);
        expect(index, greaterThan(-1),
          reason: 'motif « ${e.value.motif} » absent : le test ne prouve plus rien');

        // Le garde doit précéder le montage, à portée raisonnable — un
        // `if (!isStoreBuild)` posé 400 lignes plus haut ne gouverne pas ce
        // widget-ci.
        final avant = source.substring(
          index > 600 ? index - 600 : 0, index);
        // Le drapeau peut etre lu dans une locale (`final estStore = ...`)
        // plutot qu'en ligne : l'alias est accepte, a condition que le
        // fichier le lie bien au provider — verifie juste apres.
        expect(
          avant.contains('isStoreBuildProvider') || avant.contains('estStore'),
          isTrue,
          reason: '${e.key} : montée sans consulter le canal de distribution. '
                  'Elle partirait dans le paquet soumis aux stores.');

        // Un alias accepté sans vérifier d'où il vient rendrait ce contrôle
        // trivial à contourner : `final estStore = false;` le satisferait.
        if (!avant.contains('isStoreBuildProvider')) {
          expect(
            RegExp(r'estStore\s*=\s*ref\.watch\(isStoreBuildProvider\)')
                .hasMatch(source),
            isTrue,
            reason: '${e.key} : « estStore » n\'est pas lié au canal de '
                    'distribution — l\'alias ne prouve rien.');
        }
      });
    }
  });

  group('le paiement hors store reste hors du paquet publié', () {
    final paywall = lire(
      'lib/features/abonnement/presentation/pages/activer_premium_page.dart');

    test('le formulaire Mobile Money n\'est atteignable qu\'en canal direct', () {
      // `_goToForm` est le seul chemin vers les onglets de paiement. Son
      // déclencheur doit vivre dans la branche non-store.
      final cta = paywall.indexOf('_PaywallCTA(');
      expect(cta, greaterThan(-1));
      final iap = paywall.indexOf('if (iapMode)');
      expect(iap, greaterThan(-1),
        reason: 'la bascule achat intégré / Mobile Money a disparu');
      expect(iap, lessThan(cta),
        reason: 'le bouton qui mène au formulaire doit être dans la branche '
                'non-store, après la bascule');
    });

    test('la FAQ Mobile Money ne s\'affiche pas en achat intégré', () {
      expect(paywall.contains('iapMode'), isTrue);
      // Apple 3.1.1 interdit de mentionner un moyen de paiement externe.
      final faq = paywall.indexOf('class _PaywallFaq');
      expect(faq, greaterThan(-1));
      expect(paywall.substring(faq, faq + 900).contains('iapMode'), isTrue,
        reason: 'la FAQ doit connaître le canal : elle décrit sinon un '
                'paiement Mobile Money dans une application publiée');
    });
  });

  // ── Le vocabulaire, pas seulement les boutons ──────────────────────────
  //
  // Les tests ci-dessus vérifient qu'une *action* est conditionnée au canal.
  // Ils ont laissé passer le défaut inverse, trouvé en lançant le build store
  // sur l'émulateur : l'onglet Parrainage affichait « 0 / 2000 FCFA avant de
  // pouvoir retirer », un barème « 500 FCFA par filleul direct » et un bouton
  // « Retirer mes gains ». Le bouton de l'autre écran était bien masqué — mais
  // l'écran que l'application ouvre réellement est celui du Compte, et il
  // n'était pas couvert.
  //
  // Pire : la garde y était posée en forçant `canWithdraw` à faux, ce qui
  // affichait le *texte de repli* — celui du seuil de retrait en francs.
  // Éteindre la permission n'efface pas la promesse.
  //
  // Un examinateur lit l'écran. Ce contrôle lit donc les chaînes affichées :
  // tout mot d'argent ou de retrait doit se trouver dans une expression qui
  // consulte le canal.
  group('le canal store ne parle jamais d\'argent dans le parrainage', () {
    /// Les mots qui décrivent un versement, tels qu'ils s'affichent.
    const motsArgent = ['FCFA', 'retirer', 'Retirer', 'retrait', 'Retrait'];

    /// Retire les lignes de commentaire : elles citent le défaut pour
    /// l'expliquer, et un contrôle qui accuse ses propres explications finit
    /// par être désactivé.
    String sansCommentaires(String s) => s
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    /// Corps d'une classe, de sa déclaration à la classe suivante.
    ///
    /// `compte_page.dart` porte cinq onglets ; le Bankroll y affiche des FCFA
    /// en toute légitimité. Seul l'onglet Parrainage est concerné.
    String corpsDeClasse(String source, String declaration) {
      final debut = source.indexOf(declaration);
      if (debut < 0) fail('classe introuvable : $declaration');
      final suivante = source.indexOf('\nclass ', debut + declaration.length);
      return source.substring(debut, suivante < 0 ? source.length : suivante);
    }

    /// Portée du contrôle, en lignes.
    ///
    /// Une fenêtre en caractères ne sert à rien ici : les branches sont
    /// écrites sur plusieurs lignes, et 600 caractères en arrière finissent
    /// par attraper un `estStore` qui gouverne un *autre* widget. Le défaut
    /// d'origine aurait alors passé le contrôle.
    ///
    /// Huit lignes couvrent un ternaire imbriqué tel qu'il s'écrit ici, et
    /// pas la ligne d'à côté.
    const portee = 8;

    void verifier(String etiquette, String code, List<String> mots) {
      final lignes = code.split('\n');

      /// Le mot est-il sous un entête qui consulte le canal ?
      bool gouverne(int noLigne) {
        final debut = noLigne - portee < 0 ? 0 : noLigne - portee;
        for (var l = noLigne; l >= debut; l--) {
          if (lignes[l].contains('estStore') ||
              lignes[l].contains('isStoreBuildProvider')) {
            return true;
          }
        }
        return false;
      }

      for (var n = 0; n < lignes.length; n++) {
        for (final mot in mots) {
          if (!lignes[n].contains(mot)) continue;
          // `context.push('/parrainage/retrait')` est un chemin de route, pas
          // une phrase lue par un utilisateur.
          if (lignes[n].contains('parrainage/retrait')) continue;
          expect(gouverne(n), isTrue,
            reason: '$etiquette, ligne ${n + 1} : « $mot » s\'affiche sans '
                    'qu\'aucun entête à $portee lignes ne consulte le canal.\n'
                    '  ${lignes[n].trim()}\n'
                    'Le build publié sur Play décrirait un versement en argent.');
        }
      }
    }

    test('écran Parrainage de l\'onglet Compte', () {
      verifier(
        'compte_page.dart / _ParrainageTab',
        sansCommentaires(corpsDeClasse(
          lire('lib/features/compte/presentation/pages/compte_page.dart'),
          'class _ParrainageTab')),
        motsArgent,
      );
    });

    test('page Parrainage complète', () {
      verifier(
        'parrainage_page.dart',
        sansCommentaires(
          lire('lib/features/parrainage/presentation/pages/parrainage_page.dart')),
        motsArgent,
      );
    });

  });

  // ── Les textes légaux, vérifiés sur le résultat et non sur la source ─────
  //
  // L'interface masquait l'offre d'activation par code partenaire ; les
  // conditions d'utilisation lui consacraient encore un article entier, avec
  // le nom de l'opérateur, la capture d'écran de vérification et le délai de
  // traitement. C'est la page qu'un examinateur ouvre pour savoir ce que
  // l'application propose vraiment — et elle le lui disait.
  //
  // La règle de proximité utilisée plus haut n'y suffisait pas : retirer la
  // garde de cet article ne la faisait pas échouer, parce que l'article
  // précédent contenait un `estStore` à deux lignes de là. Le banc
  // d'injection l'a montré — sans lui, ce contrôle serait resté vert et faux.
  //
  // `sectionsLegales` étant une fonction pure, on l'appelle simplement avec le
  // canal store et on lit ce qu'elle rend. Plus d'heuristique.
  test('les textes légaux du canal store ne nomment aucun opérateur', () {
    const interdits = ['1xBet', 'Mobile Money', 'Orange Money', 'Moov'];

    for (final type in LegalType.values) {
      final sections = sectionsLegales(type, estStore: true);
      expect(sections, isNotEmpty,
        reason: '$type ne rend aucune section : le test ne prouve plus rien');

      final texte = sections.map((s) => '${s.title}\n${s.content}').join('\n');
      for (final mot in interdits) {
        expect(texte.contains(mot), isFalse,
          reason: '$type : « $mot » apparaît dans les textes légaux du build '
                  'publié sur les stores.');
      }
    }
  });

  test('le canal store ne déclare pas collecter ce qu\'il ne peut pas recevoir', () {
    // La politique de confidentialité annonçait, sans condition de canal,
    // collecter « une preuve de paiement d'abonnement » et « une capture
    // d'écran pour l'activation par code partenaire ».
    //
    // Aucun des deux flux n'existe dans le build publié : le paiement y passe
    // par l'achat intégré, et l'activation partenaire en est absente. La page
    // conditionnait déjà six autres passages au canal — celui-ci avait été
    // oublié, et c'est le seul qui décrit ce que l'application *reçoit* de
    // l'utilisateur.
    //
    // Sur-déclarer n'est pas prudent : cela décrit une collecte qui n'a pas
    // lieu, contredit le formulaire de sécurité des données, et attire
    // précisément la question que le reste du travail cherche à éviter.
    //
    // Le contrôle ne cherche pas de nom d'opérateur — le texte n'en portait
    // pas. C'est pour cela que la garde voisine ne le voyait pas.
    const interdits = [
      'preuve de paiement',
      'code partenaire',
      'capture d\'écran',
    ];

    for (final type in LegalType.values) {
      final sections = sectionsLegales(type, estStore: true);
      expect(sections, isNotEmpty,
        reason: '$type ne rend aucune section : le test ne prouve plus rien');

      final texte = sections
          .map((s) => '${s.title}\n${s.content}')
          .join('\n')
          .toLowerCase();

      for (final mot in interdits) {
        expect(texte.contains(mot.toLowerCase()), isFalse,
          reason: '$type : « $mot » — le build publié déclare une collecte '
                  'qui n\'y est pas possible');
      }
    }

    // Et le canal direct, lui, doit continuer de la déclarer : c'est là que
    // ces justificatifs sont réellement demandés. Sans cette moitié, vider la
    // clause des deux côtés passerait pour un succès.
    final direct = sectionsLegales(LegalType.confidentialite, estStore: false)
        .map((s) => s.content)
        .join('\n')
        .toLowerCase();
    expect(direct.contains('preuve de paiement'), isTrue,
      reason: 'le canal direct collecte bien ces justificatifs : les taire '
              'serait l\'erreur inverse');
  });

  test('les articles numérotés se renumérotent seuls', () {
    // Le numéro affiché vient du rang. S'il redevenait une chaîne écrite à la
    // main, retirer l'article partenaire décalerait toute la suite : des CGU
    // qui sautent du 7 au 9 se remarquent, et se corrigent mal.
    for (final type in [LegalType.cgu, LegalType.confidentialite]) {
      for (final estStore in [true, false]) {
        final badges = sectionsLegales(type, estStore: estStore)
            .map((s) => s.badge)
            .toSet();
        expect(badges, {null},
          reason: '$type : une pastille est écrite en dur au lieu de suivre '
                  'le rang — la numérotation se décalera.');
      }
    }
  });

  test('le canal store laisse une issue aux récompenses', () {
    // Le premier verrou renvoyait un écran d'explication et rien d'autre : il
    // fermait le versement en argent *et* la conversion en jours Premium,
    // celle-là même que son texte annonçait. Les récompenses s'accumulaient
    // sans aucune sortie, et l'écran affirmait le contraire.
    //
    // Une garde qui rend fausse la phrase d'à côté n'est pas une garde.
    final page = lire(
      'lib/features/parrainage/presentation/pages/retrait_parrainage_page.dart');

    final garde  = page.indexOf('if (ref.watch(isStoreBuildProvider))');
    final espece = page.indexOf('_buildMobileMoneyTab(');
    expect(garde,  greaterThan(-1), reason: 'le verrou du canal a disparu');
    expect(espece, greaterThan(-1));
    expect(garde, lessThan(espece),
      reason: 'le versement Mobile Money doit être derrière le verrou');

    // Et la branche store doit rendre la conversion, pas un cul-de-sac.
    final branche = page.substring(garde, espece);
    expect(branche.contains('_buildCreditTab('), isTrue,
      reason: 'le canal store ferme le versement sans ouvrir la conversion : '
              'les récompenses n\'auraient plus aucune issue');
  });

  test('la conversion en jours Premium n\'est écrite qu\'une fois', () {
    // Le taux vivait en trois exemplaires : `(earnings / 5000) * 30` dans la
    // page de retrait, le libellé « 1 000 FCFA = 6 jours » juste en dessous,
    // et rien du tout dans l'écran Compte, qui n'affichait donc que des francs.
    // Trois écritures d'un même rapport : deux peuvent vieillir en silence.
    for (final f in [
      'lib/features/parrainage/presentation/pages/retrait_parrainage_page.dart',
      'lib/features/compte/presentation/pages/compte_page.dart',
      'lib/features/parrainage/presentation/pages/parrainage_page.dart',
    ]) {
      expect(RegExp(r'/\s*5000').hasMatch(lire(f)), isFalse,
        reason: '$f recalcule le taux à la main : il doit passer par '
                'joursPremiumPour()');
    }
  });

  test('le défaut du canal penche du côté store', () {
    final canal = lire('lib/core/config/distribution_channel.dart');
    // Un drapeau oublié doit produire un build « store » — cassé et visible —
    // plutôt qu'un build « direct » envoyé sur Play, qui serait un motif de
    // retrait d'application.
    // La règle réelle : **seul un « false » explicite ouvre le canal direct**.
    // Valeur absente, vide ou mal orthographiée retombent sur « store ».
    expect(
      RegExp(r"_drapeau\s*==\s*'false'\s*\?\s*CanalDistribution\.direct")
          .hasMatch(canal),
      isTrue,
      reason: 'seul un « false » explicite doit ouvrir le canal direct : un '
              'drapeau oublié produit alors un build store — cassé et visible '
              '— jamais un APK d\'affiliation envoyé sur Play',
    );
    // iOS n'a pas de canal direct : pas de chargement latéral.
    expect(canal.contains('Platform.isIOS'), isTrue);
  });

  test('les écrans de bankroll ne nomment aucun guichet de paris', () {
    // « Ne mise jamais plus sur le bookmaker » et « Mise exactement X sur le
    // bookmaker » s'affichaient dans le build publié. Ce sont des conseils de
    // discipline, pas de l'incitation — mais ils désignaient un guichet de
    // paris, sur des écrans que rien ne conditionne au canal.
    //
    // Le conseil est resté, la mention est partie : PronoWin calcule une mise
    // et en tient le registre, il ne la place nulle part.
    //
    // Ces deux fichiers ne sont pas gardés par `isStoreBuildProvider` : ils
    // s'affichent dans les deux canaux. C'est pourquoi le contrôle les vise
    // nommément, et non `bookmaker_cotes.dart`, dont le widget entier est
    // conditionné et où le mot est légitime.
    const ecrans = <String>[
      'lib/features/bankroll/presentation/pages/bankroll_page.dart',
      'lib/features/bankroll/presentation/widgets/miser_dialog.dart',
    ];

    for (final chemin in ecrans) {
      final lignes = File(chemin).readAsLinesSync();
      final fautes = <String>[];

      for (var i = 0; i < lignes.length; i++) {
        final ligne = lignes[i];

        // Le premier jet cherchait le mot sans distinction de casse et
        // accusait `BookmakerAffiliation` — un identifiant, dans un bloc que
        // `isStoreBuildProvider` conditionne déjà. Un contrôle qui désigne du
        // code correct finit désarmé plutôt que corrigé.
        //
        // Ce qui est interdit, c'est le mot dans une phrase montrée à
        // l'utilisateur. En Dart, la prose est en minuscules et les
        // identifiants portent une capitale : la casse suffit à les séparer.
        if (ligne.trimLeft().startsWith('//')) continue;   // les commentaires citent le mot
        if (ligne.trimLeft().startsWith('import')) continue;  // chemin de fichier
        if (ligne.contains('bookmaker')) {
          fautes.add('$chemin:${i + 1} ${ligne.trim()}');
        }
      }

      expect(fautes, isEmpty,
        reason: 'un écran de bankroll nomme un guichet de paris dans le '
                'build publié');
    }
  });
}
