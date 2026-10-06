import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../../../shared/utils/retour.dart';

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/parametres';


enum LegalType { cgu, confidentialite, jeuResponsable }

/// Les textes légaux affichés dans l'application.
///
/// Ils décrivaient le service tel qu'il existe sur le canal direct — y compris
/// un article entier consacré à l'activation Premium contre l'ouverture d'un
/// compte chez un opérateur de paris partenaire. L'interface masquait bien
/// l'offre dans le build store ; les conditions d'utilisation, elles, la
/// détaillaient encore. C'est pourtant la page qu'un examinateur ouvre en
/// premier lorsqu'il cherche ce que l'application propose vraiment.
class LegalPage extends ConsumerWidget {
  final LegalType type;
  const LegalPage({super.key, required this.type});

  String get _title => switch (type) {
    LegalType.cgu              => trCurrent("Conditions d'utilisation"),
    LegalType.confidentialite  => trCurrent("Politique de confidentialité"),
    LegalType.jeuResponsable   => trCurrent("Jeu responsable"),
  };

  IconData get _headerIcon => switch (type) {
    LegalType.cgu              => Icons.gavel_rounded,
    LegalType.confidentialite  => Icons.privacy_tip_rounded,
    LegalType.jeuResponsable   => Icons.health_and_safety_rounded,
  };

  String get _headerSubtitle => switch (type) {
    LegalType.cgu              => trCurrent("Le cadre légal d'utilisation de PronoWin"),
    LegalType.confidentialite  => trCurrent("Comment vos données sont collectées et protégées"),
    LegalType.jeuResponsable   => trCurrent("Ressources et bonnes pratiques"),
  };

  /// Date de révision, par document.
  ///
  /// Une seule date servait les trois. Modifier les conditions générales
  /// faisait donc vieillir la politique de confidentialité, dont la date doit
  /// rester celle publiée sur le site — c'est l'URL déclarée à Google, et deux
  /// dates différentes pour un même texte sont la première chose qu'on
  /// remarque en comparant les deux.
  ///
  /// Un document juridique dont la date de révision bouge sans que son texte
  /// change ne dit plus rien de sa dernière révision.
  String get _lastUpdated => switch (type) {
    LegalType.cgu             => trCurrent("1er octobre 2026"),
    LegalType.confidentialite => trCurrent("2 octobre 2026"),
    LegalType.jeuResponsable  => trCurrent("Septembre 2026"),
  };

  List<LegalSection> _sections(bool estStore) => sectionsLegales(type,
      estStore: estStore, estIOS: defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => retourOuAller(context, repli: _repli),
        ),
        title: Text(_title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _HeaderCard(icon: _headerIcon, subtitle: _headerSubtitle, lastUpdated: _lastUpdated)
            .animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0),
          const SizedBox(height: 20),
          for (final (i, s) in _sections(ref.watch(isStoreBuildProvider)).indexed)
            _SectionWidget(s, i + 1)
              .animate(delay: (60 + i * 40).ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.03, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

/// Les sections d'une page légale, pour un canal de distribution donné.
///
/// Fonction publique et pure — pas de widget, pas de contexte. Le contrôle du
/// canal portait sur le texte source, avec une règle de proximité : « le mot
/// interdit doit avoir un `estStore` à moins de huit lignes ». Retirer la
/// garde de l'article partenaire ne faisait pas échouer ce contrôle, parce que
/// l'article précédent en contenait un. Une garde qu'on peut supprimer sans
/// que rien ne bronche ne garde rien.
///
/// Sur cette liste, la vérification n'a plus rien d'approximatif : on l'appelle
/// avec `estStore: true` et on lit ce qu'elle contient.
///
/// [estIOS] désigne la boutique qui encaisse l'abonnement du canal store :
/// Apple sur iPhone, Google Play sur Android. La politique de confidentialité
/// nommait Google Play partout — y compris sur iPhone, où l'abonnement passe
/// par l'achat intégré de l'App Store. Par défaut, Android : c'est aussi le
/// seul système du canal direct.
List<LegalSection> sectionsLegales(LegalType type,
        {required bool estStore, bool estIOS = false}) =>
    switch (type) {
    LegalType.cgu => [
      LegalSection(null, trCurrent("Objet et présentation de PronoWin"),
        trCurrent("Les présentes Conditions Générales d'Utilisation (« CGU ») régissent l'accès et l'utilisation de l'application mobile PronoWin (« l'Application », « le Service »). PronoWin propose des analyses, statistiques et pronostics sportifs à titre informatif et éducatif. PronoWin n'est ni un opérateur de paris sportifs, ni un établissement de jeux d'argent : aucune mise réelle, aucun dépôt et aucun retrait d'argent ne transitent par l'Application. L'accès à PronoWin implique l'acceptation pleine et entière des présentes CGU.")),
      LegalSection(null, trCurrent("Acceptation et modification des CGU"),
        trCurrent("En créant un compte ou en utilisant l'Application, vous déclarez avoir lu, compris et accepté sans réserve les présentes CGU. PronoWin se réserve le droit de modifier ces conditions à tout moment, notamment pour refléter une évolution du Service ou de la réglementation applicable. En cas de modification substantielle, vous en serez informé et invité à accepter la nouvelle version lors de votre prochaine connexion ; la poursuite de l'utilisation du Service après notification vaut acceptation.")),
      LegalSection(null, trCurrent("Conditions d'accès et éligibilité"),
        trCurrent("L'utilisation de PronoWin est strictement réservée aux personnes majeures (18 ans ou plus, ou l'âge légal de majorité en vigueur dans votre pays de résidence si celui-ci est supérieur). En créant un compte, vous certifiez sur l'honneur remplir cette condition d'âge et disposer de la pleine capacité juridique pour contracter. PronoWin se réserve le droit de demander une preuve d'âge et de suspendre tout compte pour lequel un doute raisonnable existerait quant à la majorité de son titulaire.")),
      LegalSection(null, trCurrent("Création et gestion du compte"),
        trCurrent("La création d'un compte nécessite la fourniture d'informations exactes, à jour et complètes (notamment un numéro de téléphone ou une adresse e-mail valide). Vous êtes seul responsable de la confidentialité de vos identifiants et de toute activité réalisée depuis votre compte. Vous vous engagez à informer immédiatement PronoWin de toute utilisation non autorisée de votre compte. Un utilisateur ne peut détenir qu'un seul compte actif ; la création de comptes multiples peut entraîner leur suspension.")),
      LegalSection(null, trCurrent("Description des services"),
        trCurrent("PronoWin met à disposition : des pronostics et analyses sportives (gratuits et Premium), des outils d'aide à la décision (modèle statistique, historiques de confrontations, indicateurs de forme), un suivi de bankroll personnel, des tutoriels pédagogiques sur les paris sportifs, ainsi qu'un programme de parrainage. La disponibilité, le contenu et la présentation de ces services peuvent évoluer sans préavis, notamment pour les améliorer.")),
      LegalSection(null, trCurrent("Pronostics — caractère purement informatif"),
        trCurrent("Les pronostics, analyses et scores de confiance publiés sur PronoWin sont établis à partir de données statistiques et d'algorithmes d'analyse ; ils sont fournis à titre purement indicatif et ne constituent en aucun cas une garantie de résultat, un conseil financier ou une incitation à parier. Le sport comportant une part d'aléa intrinsèque, aucun pronostic ne peut être certain. Toute décision de pari, ainsi que ses conséquences financières, relève de la seule et entière responsabilité de l'utilisateur qui la prend, sur la plateforme de son choix.")),
      LegalSection(null, trCurrent("Abonnement Premium"),
        // « tutoriels exclusifs » figurait dans cette liste. Le catalogue est
        // aujourd'hui constitué de vidéos YouTube tierces, toutes en accès
        // libre : l'abonnement ne les achète pas. Une mention légale qui
        // énumère une contrepartie inexistante engage sur du vide, et c'est
        // la page que l'on cite quand un abonné conteste.
        //
        // À RÉTABLIR le jour où des tutoriels produits par PronoWin seront
        // proposés en Premium — la capacité existe toujours dans le code
        // (`isPremium` → `_PremiumLock` dans tutorial_detail_page.dart), seul
        // le catalogue a changé. Cette ligne doit suivre les données, pas
        // l'inverse.
        trCurrent("L'abonnement Premium donne accès à des fonctionnalités additionnelles (pronostics VIP, analyses statistiques avancées). Il est proposé sur une base mensuelle ou annuelle selon la formule choisie, dont le tarif est affiché avant toute validation. {arg0} Sauf disposition légale contraire applicable dans votre juridiction, l'abonnement n'est pas remboursable une fois activé. PronoWin se réserve le droit de modifier ses tarifs, moyennant un préavis minimum de 30 jours pour les abonnements en cours, qui ne s'appliquera qu'au renouvellement suivant.", [estStore ? trCurrent("Le paiement s'effectue par l'achat intégré de la boutique d'applications, selon les modalités affichées avant validation.") : trCurrent("Le paiement peut s'effectuer par preuve de transaction (paiement mobile, virement) ou via l'activation gratuite par code promotionnel 1xBet, selon les modalités décrites dans l'Application.")])),
      // L'article que le canal store ne publie pas : il décrit une offre qui
      // n'existe pas dans ce build, et c'est précisément celle qui ferait
      // classer l'application dans la catégorie qu'on cherche à éviter.
      //
      // Les articles suivants se renumérotent seuls — leur numéro vient du
      // rang, plus d'une chaîne écrite à la main.
      if (!estStore)
        LegalSection(null, trCurrent("Activation par code 1xBet"),
          trCurrent("PronoWin propose une voie d'activation Premium gratuite pour les utilisateurs disposant d'un compte actif chez le partenaire 1xBet, sous réserve de remplir les conditions affichées dans l'Application (code promotionnel, capture d'écran de vérification). Chaque demande fait l'objet d'une vérification manuelle par notre équipe, le délai indicatif de traitement étant affiché au moment de la demande. Toute tentative de fraude (faux comptes, documents falsifiés, contournement des conditions du partenaire) entraîne le rejet de la demande et peut entraîner la suspension définitive du compte PronoWin concerné.")),
      LegalSection(null, trCurrent("Programme de parrainage"),
        trCurrent("PronoWin propose un programme de parrainage permettant à un utilisateur (« le parrain ») d'inviter de nouveaux utilisateurs (« les filleuls ») et de percevoir une récompense selon les règles affichées dans l'Application. Les récompenses ne sont créditées qu'après validation des conditions d'éligibilité (ex. activation d'un abonnement par le filleul). Toute fraude avérée (auto-parrainage, comptes fictifs, manipulation du système) entraîne l'annulation des récompenses concernées et peut donner lieu à la suspension des comptes impliqués.")),
      LegalSection(null, trCurrent("Usages interdits"),
        trCurrent("Il est interdit d'utiliser PronoWin à des fins illégales, de tenter d'accéder de manière non autorisée à ses systèmes, de perturber son fonctionnement (y compris par des moyens automatisés type robots ou scripts), de reproduire ou d'extraire son contenu à des fins commerciales sans autorisation, ou d'usurper l'identité d'un tiers. Tout manquement peut entraîner la suspension ou la suppression du compte concerné, sans préjudice d'éventuelles poursuites.")),
      // Exigé par l'App Store (règle 1.2) et Google Play dès que des membres
      // publient des contenus visibles par d'autres : la tolérance zéro, et les
      // moyens offerts pour la faire respecter.
      LegalSection(null, trCurrent("Contenus publiés par les membres"),
        trCurrent("Les membres peuvent publier des commentaires. PronoWin applique une tolérance zéro envers les contenus répréhensibles et les comportements abusifs : sont interdits les propos injurieux, haineux, discriminatoires, menaçants, à caractère sexuel ou violent, le harcèlement, la publicité, les liens et les numéros de téléphone, ainsi que toute incitation au jeu excessif. Les commentaires sont filtrés à la publication. Chaque membre peut signaler un commentaire et bloquer un autre membre depuis l'Application ; un commentaire signalé à plusieurs reprises est retiré en attendant son examen. PronoWin examine les signalements dans un délai de 24 heures, retire les contenus contraires aux présentes CGU et peut suspendre ou bannir leurs auteurs. Chaque membre reste responsable des contenus qu'il publie.")),
      LegalSection(null, trCurrent("Propriété intellectuelle"),
        trCurrent("L'ensemble des éléments composant PronoWin — textes, analyses, logos, interface, algorithmes, bases de données et code source — sont protégés par le droit de la propriété intellectuelle et demeurent la propriété exclusive de PronoWin ou de ses concédants. Toute reproduction, représentation, modification ou diffusion, totale ou partielle, sans autorisation écrite préalable est strictement interdite.")),
      LegalSection(null, trCurrent("Protection des données personnelles"),
        trCurrent("Le traitement de vos données personnelles est décrit en détail dans notre Politique de confidentialité, accessible depuis les Paramètres de l'Application, qui fait partie intégrante des présentes CGU.")),
      LegalSection(null, trCurrent("Jeu responsable"),
        trCurrent("PronoWin, bien que n'étant pas un opérateur de jeux d'argent, reconnaît sa proximité thématique avec l'univers des paris sportifs et s'engage à promouvoir une pratique responsable. Les principes et ressources d'aide sont détaillés dans notre page dédiée « Jeu responsable », accessible depuis les Paramètres.")),
      LegalSection(null, trCurrent("Limitation de responsabilité"),
        trCurrent("PronoWin met tout en œuvre pour assurer l'exactitude de ses analyses et la disponibilité de son Service, mais ne peut garantir l'absence d'erreur, d'interruption ou de dysfonctionnement technique. Dans la mesure permise par la loi applicable, PronoWin ne pourra être tenu responsable des pertes financières résultant de paris placés par l'utilisateur sur toute plateforme tierce, ni des dommages indirects liés à l'utilisation ou à l'impossibilité d'utiliser le Service. L'Application est fournie « en l'état », sans garantie de disponibilité permanente.")),
      LegalSection(null, trCurrent("Suspension et résiliation"),
        trCurrent("PronoWin peut suspendre ou résilier, temporairement ou définitivement, l'accès d'un utilisateur en cas de manquement aux présentes CGU, de fraude avérée, ou sur demande légale. L'utilisateur peut à tout moment demander la clôture de son compte depuis les Paramètres ou en contactant le support ; cette demande entraîne la suppression de ses données personnelles conformément à notre Politique de confidentialité.")),
      LegalSection(null, trCurrent("Droit applicable et litiges"),
        trCurrent("Les présentes CGU sont soumises à la loi applicable dans votre pays de résidence en matière de protection du consommateur, sans préjudice des dispositions d'ordre public locales. En cas de litige, l'utilisateur est invité à contacter en priorité le support de PronoWin afin de rechercher une résolution amiable avant toute action contentieuse.")),
      LegalSection(null, 'Contact',
        trCurrent("Pour toute question relative aux présentes CGU, réclamation ou demande d'assistance : pronowin2026@gmail.com")),
    ],
    LegalType.confidentialite => [
      LegalSection(null, trCurrent("Responsable du traitement"),
        trCurrent("PronoWin est responsable du traitement des données personnelles collectées via l'Application. Pour toute question relative à cette politique ou à l'exercice de vos droits, vous pouvez nous contacter à : pronowin2026@gmail.com.")),
      // Cette liste doit couvrir ce que le site declare, et l'inverse.
      //
      // Elle annoncait trois categories la ou le site en detaillait cinq. Y
      // manquaient l'empreinte du mot de passe, le prenom et le nom, le pays,
      // la photo de profil, les votes et commentaires, l'etat de l'abonnement,
      // et surtout les rapports de plantage et mesures de performance —
      // Crashlytics et Performance tournent pourtant depuis le premier jour.
      //
      // Sous-declarer est pire que sur-declarer : l'utilisateur lit une page
      // qui lui promet moins que ce qui est reellement collecte, et le
      // formulaire de surete des donnees envoye a Google dit encore autre
      // chose. `confidentialite_coherente_test.dart` compare desormais les deux
      // textes categorie par categorie.
      //
      // Le site s'est enrichi le 2 octobre 2026 de trois declarations que
      // cette liste taisait : la connexion avec Apple (adresse relais
      // comprise), la mesure d'audience d'`analyse_usage.dart`, et le
      // rattachement des rapports de plantage au compte.
      LegalSection(null, trCurrent("Données collectées"),
        trCurrent("Nous collectons, selon votre usage de l'Application :\n\n• Compte et profil : adresse e-mail ou numéro de téléphone, empreinte de votre mot de passe, pseudonyme, prénom et nom, pays, date de naissance (pour vérifier votre majorité) et photo de profil si vous en ajoutez une. Si vous utilisez « Se connecter avec Apple » ou la connexion Google : l'identifiant transmis par ce service, l'adresse e-mail (avec Apple, il peut s'agir d'une adresse relais qui masque la vôtre) et le nom, si vous acceptez de le partager.\n\n• Utilisation du Service : formule d'abonnement, pronostics suivis, favoris, votes, commentaires, historique d'activité, données de bankroll que vous saisissez et informations de parrainage.\n\n• Notifications : jeton de notification propre à votre appareil et préférences d'alerte.\n\n• Diagnostic technique : identifiant d'installation, modèle de l'appareil, version du système et de l'Application, journaux de connexion, rapports de plantage et mesures de performance. Les rapports de plantage sont associés à l'identifiant de votre compte, pour retrouver l'erreur que vous nous signalez.\n\n• Mesure d'audience (Firebase Analytics) : événements d'utilisation associés à l'identifiant d'installation — connexion et inscription, affichage de l'offre Premium et étapes de l'abonnement, ouverture d'un pronostic, pari noté ou confirmé dans la bankroll, ouverture d'une notification. Ni nom, ni adresse e-mail, ni numéro de téléphone, ni montant. Ces mesures servent à améliorer l'Application, jamais à de la publicité.\n\n• Abonnement : état de votre abonnement et informations nécessaires à sa vérification.{arg0}\n\nNous ne collectons pas votre position GPS, vos contacts, vos SMS, vos journaux d'appels ni le contenu de votre appareil. Une image n'est lue que si vous choisissez volontairement une photo pour votre profil.", [
          // Sur iPhone, c'est Apple qui facture : nommer Google Play y
          // décrivait la boutique d'un autre système.
          estStore
            ? (estIOS
                ? trCurrent(" Les informations de paiement sont gérées par Apple, via l'App Store, jamais par PronoWin.")
                : trCurrent(" Les informations de paiement sont gérées par Google Play, jamais par PronoWin."))
            : trCurrent(" Le cas échéant, les justificatifs que vous transmettez volontairement : preuve de paiement d'abonnement, capture d'écran pour l'activation par code partenaire.")])),
      LegalSection(null, trCurrent("Finalités du traitement"),
        trCurrent("Vos données sont traitées pour : créer et sécuriser votre compte (authentification) ; fournir et personnaliser le Service (pronostics, statistiques, recommandations) ; traiter vos demandes d'abonnement et de parrainage ; vous envoyer des notifications pertinentes que vous avez autorisées ; assurer la sécurité de l'Application et prévenir la fraude ; répondre à nos obligations légales ; et améliorer nos services à partir de statistiques d'usage agrégées.")),
      LegalSection(null, trCurrent("Base légale des traitements"),
        trCurrent("Selon les cas, ces traitements reposent sur : l'exécution du contrat qui vous lie à PronoWin (fourniture du Service) ; votre consentement (notifications{arg0}) ; l'intérêt légitime de PronoWin (sécurité, prévention de la fraude, amélioration du Service) ; ou le respect d'une obligation légale.", [estStore ? "" : trCurrent(", activation par code partenaire")])),
      LegalSection(null, trCurrent("Partage et destinataires des données"),
        trCurrent("Vos données personnelles ne sont jamais vendues à des tiers. Elles peuvent être partagées, dans la stricte mesure nécessaire, avec : nos prestataires techniques (hébergement, envoi de SMS ou d'e-mails, notifications push, et Google Firebase pour les rapports de plantage, les mesures de performance et la mesure d'audience) agissant sur nos instructions ; Apple ou Google, si vous choisissez de vous connecter avec leur service ;{arg0} ou les autorités compétentes lorsque la loi l'exige.", [estStore ? "" : trCurrent(" nos partenaires (ex. vérification d'une activation via code 1xBet, avec votre consentement explicite) ;")])),
      LegalSection(null, trCurrent("Sécurité des données"),
        trCurrent("Vos données sont chiffrées en transit (HTTPS/TLS) et protégées au repos. L'accès à votre compte repose sur des jetons d'authentification (JWT) à durée de vie limitée, automatiquement renouvelés, ainsi que, si vous l'activez, un code PIN ou une authentification biométrique locale à votre appareil. Nous mettons en œuvre des mesures techniques et organisationnelles raisonnables pour prévenir tout accès non autorisé, perte ou divulgation de vos données.")),
      LegalSection(null, trCurrent("Durée de conservation"),
        trCurrent("Vos données sont conservées pendant toute la durée de vie de votre compte. En cas de suppression de compte, vos données personnelles identifiantes sont supprimées ou anonymisées dans un délai de 30 jours, sous réserve des durées de conservation plus longues imposées par une obligation légale (ex. données comptables liées à un abonnement).")),
      LegalSection(null, trCurrent("Vos droits"),
        trCurrent("Conformément au Règlement Général sur la Protection des Données (RGPD) et aux lois locales applicables, vous disposez d'un droit d'accès, de rectification, d'effacement, de limitation et d'opposition au traitement de vos données, ainsi que d'un droit à la portabilité. Vous pouvez exercer ces droits directement depuis les Paramètres de l'Application (modification du profil, suppression du compte) ou en nous contactant à pronowin2026@gmail.com. Si vous résidez dans l'Union européenne, vous disposez également du droit d'introduire une réclamation auprès de l'autorité de contrôle compétente (en France, la CNIL).")),
      LegalSection(null, trCurrent("Cookies et traceurs"),
        trCurrent("L'application mobile PronoWin n'utilise pas de cookies au sens web du terme. Certaines préférences (thème, langue, filtres) sont stockées localement sur votre appareil via un mécanisme de stockage local (SharedPreferences), sans transmission à des tiers à des fins publicitaires.")),
      LegalSection(null, trCurrent("Transferts de données"),
        trCurrent("Vos données sont hébergées et traitées par des prestataires susceptibles d'opérer depuis différents pays. Lorsqu'un transfert hors de votre région implique un niveau de protection différent, nous veillons à ce que des garanties appropriées soient mises en place, conformément à la réglementation applicable.")),
      LegalSection(null, trCurrent("Mineurs"),
        trCurrent("PronoWin n'est pas destiné aux personnes mineures. Nous ne collectons pas sciemment de données concernant des mineurs. Si vous pensez qu'un compte a été créé par une personne mineure, merci de nous le signaler à pronowin2026@gmail.com afin que nous puissions procéder à sa suppression.")),
      LegalSection(null, trCurrent("Modification de cette politique"),
        trCurrent("Cette politique de confidentialité peut être mise à jour pour refléter une évolution de nos pratiques ou de la réglementation. La date de dernière mise à jour est indiquée en haut de cette page ; en cas de modification substantielle, vous en serez informé au sein de l'Application.")),
    ],
    LegalType.jeuResponsable => [
      LegalSection('⚠️', trCurrent("Avertissement important"),
        trCurrent("PronoWin est une plateforme d'information et d'analyse sportive : elle n'accepte ni ne place aucun pari et n'est pas un opérateur de jeux d'argent. Les paris sportifs, proposés par des tiers, peuvent néanmoins être addictifs et entraîner des pertes financières importantes. PronoWin ne saurait être tenu responsable des décisions de pari prises par ses utilisateurs sur des plateformes tierces ni de leurs conséquences.")),
      LegalSection('🎯', trCurrent("Principes du jeu responsable"),
        trCurrent("• Ne pariez jamais plus que ce que vous pouvez vous permettre de perdre\n• Fixez-vous un budget dédié aux paris et respectez-le strictement, indépendamment de vos gains ou pertes\n• Ne cherchez jamais à « se refaire » après une perte en augmentant vos mises\n• Le jeu doit rester un loisir occasionnel : il ne doit jamais interférer avec votre vie personnelle, familiale ou professionnelle\n• Un pronostic, même bien argumenté, reste une analyse probabiliste — jamais une certitude\n• Évitez de parier sous l'effet de l'alcool, de la fatigue ou d'une émotion forte")),
      LegalSection('🔢', trCurrent("Gestion saine du bankroll"),
        trCurrent("Une gestion de bankroll prudente ne consacre jamais plus de 2 à 5 % de son capital total à un seul pari. PronoWin recommande une approche de type « flat betting » (miser un montant fixe et identique à chaque pari, indépendamment du niveau de confiance affiché) plutôt que d'augmenter ses mises après une perte ou un gain. L'outil de suivi de bankroll intégré à l'Application vous aide à visualiser votre exposition réelle dans le temps.")),
      LegalSection('🚨', trCurrent("Reconnaître les signes d'alerte"),
        trCurrent("Le jeu peut devenir problématique de façon progressive. Soyez attentif si vous :\n• Pariez avec de l'argent destiné à des dépenses essentielles (loyer, factures, nourriture)\n• Empruntez de l'argent pour parier ou pour rembourser des dettes de jeu\n• Mentez à vos proches sur vos habitudes ou vos pertes de jeu\n• Ressentez de l'anxiété, de l'irritabilité ou de la culpabilité liées au jeu\n• Essayez, sans succès répété, de réduire ou d'arrêter de parier\n• Passez un temps croissant à penser aux paris ou à en parler\n\nSi plusieurs de ces situations vous concernent, il est recommandé de solliciter l'aide d'un professionnel.")),
      LegalSection('🛡️', trCurrent("Outils de protection disponibles"),
        trCurrent("De nombreux opérateurs de paris sportifs{arg0} proposent des outils de jeu responsable directement sur leur plateforme : fixation de limites de dépôt ou de mise, plafonnement de session, auto-exclusion temporaire ou définitive. PronoWin vous encourage à activer ces outils directement auprès de l'opérateur avec lequel vous pariez. Depuis l'Application, vous pouvez également mettre votre compte PronoWin en pause à tout moment en contactant notre support.", [estStore ? "" : trCurrent(", dont 1xBet,")])),
      // L'ordre de cette liste compte autant que son contenu.
      //
      // Elle ouvrait sur « 🇫🇷 France — Joueurs Info Service », suivi d'un
      // « hors France, rapprochez-vous d'un professionnel » sans indication de
      // qui aller voir. Pour la très grande majorité des utilisateurs de cette
      // application, la seule entrée concrète était donc celle qu'ils ne
      // peuvent pas appeler, et la leur se résumait à une phrase vague.
      //
      // Quelqu'un qui ouvre cette page va mal. On lui donne d'abord ce qui
      // marche là où il est, puis les ressources particulières à un pays.
      //
      // Des puces « • » comme dans les autres sections : les émojis (🌍 👥 🌐
      // 📞) faisaient de la page la seule illustrée, sur un sujet qui ne s'y
      // prête pas. Et la ligne française dit à qui elle s'adresse.
      LegalSection('📞', trCurrent("Ressources d'aide"),
        trCurrent("Si vous pensez, pour vous-même ou pour un proche, avoir un problème avec le jeu, une aide existe — et en parler est le premier pas.\n\n• Où que vous soyez : parlez-en à un médecin, à un psychologue, au service de psychiatrie d'un hôpital ou à un centre de santé de votre localité. Ces professionnels sont tenus au secret.\n\n• En parler à quelqu'un de confiance — un proche, un ami — change souvent davantage qu'un numéro. Le silence est ce qui aggrave le plus les choses.\n\n• Gamblers Anonymous, groupes d'entraide présents dans de nombreux pays : www.gamblersanonymous.org\n\n• Si vous résidez en France — Joueurs Info Service : 09 74 75 13 13 (anonyme, gratuit, non surtaxé)\n\nDepuis l'Application, vous pouvez à tout moment demander la mise en pause ou la clôture de votre compte PronoWin en contactant notre support.")),
      LegalSection('✅', trCurrent("Engagement de PronoWin"),
        trCurrent("PronoWin s'engage à :\n• Afficher des messages clairs sur le caractère informatif de ses pronostics et sur les risques liés aux paris sportifs\n• Ne jamais cibler ou solliciter des utilisateurs identifiés comme vulnérables\n• Vérifier l'âge de ses utilisateurs (18 ans ou plus requis) à la création de compte\n• Fournir un outil de suivi de bankroll pour aider à une gestion responsable\n• Permettre la mise en pause ou la clôture d'un compte sur simple demande, sans condition")),
    ],
  };


class _HeaderCard extends StatelessWidget {
  final IconData icon;
  final String   subtitle;
  final String   lastUpdated;
  const _HeaderCard({required this.icon, required this.subtitle, required this.lastUpdated});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.primary.withValues(alpha: 0.14), context.cl.surface],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 0.8),
    ),
    child: Row(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.degradeMarque,
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Colors.white, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle, style: TextStyle(
          color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.cl.surfaceDeep,
            borderRadius: BorderRadius.circular(6)),
          child: Text(tr(context, "Dernière mise à jour : {arg0}", [lastUpdated]), style: TextStyle(
            color: context.cl.textM, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ),
      ])),
    ]),
  );
}

class LegalSection {
  /// Pastille affichée à gauche du titre.
  ///
  /// `null` pour les pages numérotées : le numéro vient alors du rang. Il
  /// était écrit à la main, de « 1 » à « 17 » — une seconde écriture de la
  /// position, qui devient fausse dès qu'une section disparaît. Et une
  /// section disparaît : le canal store ne publie pas l'article consacré à
  /// l'activation par code partenaire.
  final String? badge;
  final String title, content;
  const LegalSection(this.badge, this.title, this.content);
}

class _SectionWidget extends StatelessWidget {
  final LegalSection section;
  final int rang;
  const _SectionWidget(this.section, this.rang);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 28, height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9)),
        child: Text(section.badge ?? '$rang', style: TextStyle(
          color: context.cl.accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(section.title, style: TextStyle(
          color: context.cl.textP, fontSize: 14.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(section.content, style: TextStyle(
          color: context.cl.textS, fontSize: 13, height: 1.6)),
      ])),
    ]),
  );
}
