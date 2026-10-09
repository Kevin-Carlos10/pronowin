import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';

/// Chaque notification du serveur tombe dans la bonne rubrique.
///
/// L'écran range les notifications en quatre rubriques et lit pour cela le
/// champ `type` envoyé par le serveur. La correspondance se terminait par un
/// repli : tout ce qui n'était pas reconnu partait en « Système ».
///
/// Quatre types y tombaient : `prono_result`, `match_live`, `match_finished`
/// et `premium`. Les trois premiers sont des notifications de match — le
/// filtre « Match » n'en montrait donc qu'une partie. Rien ne pouvait le
/// signaler : un repli silencieux ne se voit qu'en comparant, à la main, ce
/// que le serveur envoie et ce que l'application sait lire.
///
/// C'est exactement ce que fait ce banc, et il le fait à chaque exécution.
/// Un type ajouté demain côté serveur, sans sa ligne ici, fera échouer la
/// suite au lieu de se ranger discrètement en « Système ».
///
/// ── Pourquoi lire le backend plutôt qu'une liste figée ────────────────────
///
/// Une liste écrite à la main dans ce fichier serait une troisième copie, à
/// tenir à jour comme les deux autres — et c'est précisément ce genre de copie
/// qui a produit le défaut. Les deux dépôts vivent ensemble ; on lit la source.
void main() {
  const dossierServices = '../backend/src/services';

  late Set<String> typesDuServeur;
  late String sourceDeLecture;

  setUpAll(() {
    final dossier = Directory(dossierServices);
    // Pas de `skip` si le backend manque : un contrôle qui s'efface quand il
    // ne peut pas travailler finit par ne plus rien garder.
    expect(dossier.existsSync(), isTrue,
        reason: '$dossierServices introuvable — ce contrôle compare '
                'l\'application au serveur, il ne peut rien affirmer sans les '
                'deux');

    // On ne retient que les types passés à un envoi de notification. Le même
    // mot « type » sert ailleurs à des transactions et à des boutons : les
    // ramasser tous ferait échouer ce banc sur des valeurs qui n'atteignent
    // jamais l'écran.
    final envoi = RegExp(r"send(?:ToUser|ToTopic)\(([\s\S]{0,1400}?)\}\s*,?\s*(?:'[a-z]+')?\s*\)");
    final champ = RegExp(r"type:\s*'([a-z_]+)'");

    typesDuServeur = {};
    for (final f in dossier.listSync().whereType<File>()) {
      if (!f.path.endsWith('.ts')) continue;
      final source = f.readAsStringSync();
      for (final appel in envoi.allMatches(source)) {
        final t = champ.firstMatch(appel.group(1)!);
        if (t != null) typesDuServeur.add(t.group(1)!);
      }
    }

    sourceDeLecture = File(
      'lib/features/notifications/presentation/providers/notification_service.dart',
    ).readAsStringSync();
  });

  test('le relevé des types du serveur a bien trouvé quelque chose', () {
    // Contrepartie : une expression qui ne trouverait plus rien ferait passer
    // le contrôle suivant sur un ensemble vide, en n'ayant rien regardé.
    expect(typesDuServeur.length, greaterThan(4),
        reason: 'relevé suspect : ${typesDuServeur.toList()..sort()}');
    // Un seul ancrage nommé, et le plus stable : « payment » est au cœur de
    // cette rubrique. En ancrer davantage ferait échouer ce contrôle-ci sur un
    // simple renommage côté serveur, avec un message qui n'expliquerait rien —
    // alors que le contrôle suivant dit précisément ce qui manque.
    expect(typesDuServeur, contains('payment'));
  });

  test('aucun type du serveur ne tombe dans le repli', () {
    // On lit la correspondance dans la source plutôt que d'appeler la
    // fonction : appelée, elle rend « Système » aussi bien pour un type
    // délibérément rangé là que pour un type oublié. Seule la source
    // distingue les deux.
    final nommes = RegExp(r"'([a-z_]+)'")
        .allMatches(
          sourceDeLecture.substring(
            sourceDeLecture.indexOf('typeFromString'),
            sourceDeLecture.indexOf('_replide(String s)'),
          ),
        )
        .map((m) => m.group(1)!)
        .toSet();

    final oublies = typesDuServeur.difference(nommes);
    expect(oublies, isEmpty,
        reason: 'ces types sont envoyés par le serveur mais ne sont nommés '
                'nulle part dans typeFromString : ils se rangeront en '
                '« Système » sans que rien ne le dise — $oublies');
  });

  test('les notifications de match vont dans Match', () {
    for (final t in ['match', 'match_live', 'match_finished', 'prono_result']) {
      expect(AppNotification.typeFromString(t), NotificationType.match,
          reason: '« $t » est une notification de match');
    }
  });

  test('le versement des gains rejoint Parrainage', () {
    // « Paiement » ne contenait que « Versement effectué » et « Versement
    // refusé » — le paiement des gains de parrainage, qui mène d'ailleurs à
    // `/parrainage`. Sur une application où l'on paie un abonnement, le mot
    // laissait croire à l'historique de ses propres paiements.
    expect(AppNotification.typeFromString('payment'), NotificationType.referral);
    expect(AppNotification.typeFromString('referral'), NotificationType.referral);
  });

  test('le reste va en Système, délibérément', () {
    expect(AppNotification.typeFromString('system'), NotificationType.system);
    expect(AppNotification.typeFromString('premium'), NotificationType.system);
    expect(AppNotification.typeFromString('promo'), NotificationType.promo);
  });

  test('un type inconnu ne fait rien disparaître', () {
    // Le repli reste nécessaire : un serveur plus récent que l'application
    // installée enverra des types qu'elle ne connaît pas, et une notification
    // mal rangée vaut mieux qu'une notification perdue.
    expect(AppNotification.typeFromString('type_invente_en_2027'),
        NotificationType.system);
  });
}
