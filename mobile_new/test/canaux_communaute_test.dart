import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/contact_support.dart';

/// Les canaux Telegram et WhatsApp existaient — dans une modale, dans les
/// Paramètres, sous « À propos ». Personne ne les trouvait.
///
/// Ils apparaissent désormais là où la section « Avis de la communauté » n'a
/// rien à lire : envoyer ailleurs vaut mieux qu'un vide, et quand des
/// commentaires existent, la section n'a pas à pousser l'utilisateur dehors.
void main() {
  final section = File(
    'lib/features/pronostics/presentation/widgets/comments_section.dart',
  ).readAsStringSync();

  final code = section
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');

  test('les canaux sont regroupés en un seul endroit', () {
    expect(ContactSupport.telegram.isNotEmpty, isTrue);
    expect(ContactSupport.whatsapp.isNotEmpty, isTrue);
    // Un lien recopié dans un écran finit par diverger de l'autre.
    expect(code.contains('whatsapp.com/channel'), isFalse,
      reason: 'le lien appartient à ContactSupport, pas à l\'écran');
    expect(code.contains('t.me/'), isFalse);
  });

  test('les canaux vivent dans un seul widget, hors des deux verrous', () {
    final debut = code.indexOf('class _CanauxCommunaute');
    expect(debut, greaterThan(-1), reason: 'le bloc doit être extrait');

    // Les liens ne sont ouverts que depuis ce widget. S'ils réapparaissaient
    // dans `_EmptyComments`, l'utilisateur Premium les verrait deux fois ; s'ils
    // étaient posés dans `_CommentsPremiumLocked` ou `_CommentsGuestLocked`,
    // ils se disputeraient le tap avec la surface cliquable de ces cartes.
    final avant = code.substring(0, debut);
    expect(avant.contains('ouvrirTelegram'), isFalse);
    expect(avant.contains('ouvrirWhatsapp'), isFalse);

    for (final verrou in ['_CommentsPremiumLockedState', '_CommentsGuestLocked']) {
      final d = code.indexOf('class $verrou');
      expect(d, greaterThan(-1), reason: '$verrou doit exister');
      final fin = code.indexOf('\nclass ', d + 1);
      final corps = code.substring(d, fin == -1 ? code.length : fin);
      expect(corps.contains('ouvrirTelegram'), isFalse,
        reason: '$verrou capte le tap sur toute sa surface');
    }
  });

  test('un compte gratuit et un invité voient les canaux', () {
    // Le défaut corrigé : les canaux ne s'affichaient que dans `_EmptyComments`,
    // atteint uniquement par la branche `data`. Un invité reçoit 401, un compte
    // gratuit 403 — aucun des deux n'y arrivait, donc aucun des deux ne voyait
    // le lien censé faire grandir la communauté.
    expect(code.contains('final rienALire        = isGated || aucunCommentaire;'),
      isTrue, reason: 'la condition porte sur ce qu\'il y a à lire, pas sur '
                      'le statut de l\'utilisateur');
    expect(code.contains('if (rienALire) const _CanauxCommunaute(),'), isTrue);

    // Et le contre-exemple : la condition ne doit pas se restreindre aux
    // comptes qui reçoivent une réponse.
    expect(code.contains('if (aucunCommentaire) const _CanauxCommunaute()'),
      isFalse);
  });

  test('une section qui a des commentaires ne pousse personne dehors', () {
    // `rienALire` est faux dès qu'un commentaire existe : le bloc disparaît.
    expect(code.contains('commentsAsync.valueOrNull?.comments.isEmpty ?? false'),
      isTrue,
      reason: 'sans commentaire chargé, la valeur par défaut doit être false — '
              'un `?? true` afficherait les canaux pendant le chargement');
  });

  test('quitter l\'application est annoncé', () {
    final d = code.indexOf('class _BoutonCanal');
    expect(d, greaterThan(-1));
    final corps = code.substring(d);
    expect(corps.contains('Semantics('), isTrue);
    expect(corps.contains('ouvre \$libelle'), isTrue,
      reason: 'un lecteur d\'écran doit savoir que le bouton bascule vers une '
              'autre application');
  });
}
