import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/distribution_channel.dart';

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
    LegalType.cgu              => 'Conditions d\'utilisation',
    LegalType.confidentialite  => 'Politique de confidentialité',
    LegalType.jeuResponsable   => 'Jeu responsable',
  };

  IconData get _headerIcon => switch (type) {
    LegalType.cgu              => Icons.gavel_rounded,
    LegalType.confidentialite  => Icons.privacy_tip_rounded,
    LegalType.jeuResponsable   => Icons.health_and_safety_rounded,
  };

  String get _headerSubtitle => switch (type) {
    LegalType.cgu              => 'Le cadre légal d\'utilisation de PronoWin',
    LegalType.confidentialite  => 'Comment vos données sont collectées et protégées',
    LegalType.jeuResponsable   => 'Ressources et bonnes pratiques',
  };

  /// Date alignée sur la politique de confidentialité publiée sur le site :
  /// deux dates différentes pour un même texte, c'est la première chose qu'on
  /// remarque quand on compare les deux.
  static const String _lastUpdated = 'Septembre 2026';

  List<LegalSection> _sections(bool estStore) =>
      sectionsLegales(type, estStore: estStore);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
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
List<LegalSection> sectionsLegales(LegalType type, {required bool estStore}) =>
    switch (type) {
    LegalType.cgu => [
      LegalSection(null, 'Objet et présentation de PronoWin',
        'Les présentes Conditions Générales d\'Utilisation (« CGU ») régissent l\'accès et l\'utilisation de l\'application mobile PronoWin (« l\'Application », « le Service »). PronoWin propose des analyses, statistiques et pronostics sportifs à titre informatif et éducatif. PronoWin n\'est ni un opérateur de paris sportifs, ni un établissement de jeux d\'argent : aucune mise réelle, aucun dépôt et aucun retrait d\'argent ne transitent par l\'Application. L\'accès à PronoWin implique l\'acceptation pleine et entière des présentes CGU.'),
      LegalSection(null, 'Acceptation et modification des CGU',
        'En créant un compte ou en utilisant l\'Application, vous déclarez avoir lu, compris et accepté sans réserve les présentes CGU. PronoWin se réserve le droit de modifier ces conditions à tout moment, notamment pour refléter une évolution du Service ou de la réglementation applicable. En cas de modification substantielle, vous en serez informé et invité à accepter la nouvelle version lors de votre prochaine connexion ; la poursuite de l\'utilisation du Service après notification vaut acceptation.'),
      LegalSection(null, 'Conditions d\'accès et éligibilité',
        'L\'utilisation de PronoWin est strictement réservée aux personnes majeures (18 ans ou plus, ou l\'âge légal de majorité en vigueur dans votre pays de résidence si celui-ci est supérieur). En créant un compte, vous certifiez sur l\'honneur remplir cette condition d\'âge et disposer de la pleine capacité juridique pour contracter. PronoWin se réserve le droit de demander une preuve d\'âge et de suspendre tout compte pour lequel un doute raisonnable existerait quant à la majorité de son titulaire.'),
      LegalSection(null, 'Création et gestion du compte',
        'La création d\'un compte nécessite la fourniture d\'informations exactes, à jour et complètes (notamment un numéro de téléphone ou une adresse e-mail valide). Vous êtes seul responsable de la confidentialité de vos identifiants et de toute activité réalisée depuis votre compte. Vous vous engagez à informer immédiatement PronoWin de toute utilisation non autorisée de votre compte. Un utilisateur ne peut détenir qu\'un seul compte actif ; la création de comptes multiples peut entraîner leur suspension.'),
      LegalSection(null, 'Description des services',
        'PronoWin met à disposition : des pronostics et analyses sportives (gratuits et Premium), des outils d\'aide à la décision (analyse par intelligence artificielle, statistiques, historiques de confrontations), un suivi de bankroll personnel, des tutoriels pédagogiques sur les paris sportifs, ainsi qu\'un programme de parrainage. La disponibilité, le contenu et la présentation de ces services peuvent évoluer sans préavis, notamment pour les améliorer.'),
      LegalSection(null, 'Pronostics — caractère purement informatif',
        'Les pronostics, analyses et scores de confiance publiés sur PronoWin sont établis à partir de données statistiques et d\'algorithmes d\'analyse ; ils sont fournis à titre purement indicatif et ne constituent en aucun cas une garantie de résultat, un conseil financier ou une incitation à parier. Le sport comportant une part d\'aléa intrinsèque, aucun pronostic ne peut être certain. Toute décision de pari, ainsi que ses conséquences financières, relève de la seule et entière responsabilité de l\'utilisateur qui la prend, sur la plateforme de son choix.'),
      LegalSection(null, 'Abonnement Premium',
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
        'L\'abonnement Premium donne accès à des fonctionnalités additionnelles (pronostics VIP, analyses statistiques avancées). Il est proposé sur une base mensuelle ou annuelle selon la formule choisie, dont le tarif est affiché avant toute validation. ${estStore ? "Le paiement s'effectue par l'achat intégré de la boutique d'applications, selon les modalités affichées avant validation." : "Le paiement peut s'effectuer par preuve de transaction (paiement mobile, virement) ou via l'activation gratuite par code promotionnel 1xBet, selon les modalités décrites dans l'Application."} Sauf disposition légale contraire applicable dans votre juridiction, l\'abonnement n\'est pas remboursable une fois activé. PronoWin se réserve le droit de modifier ses tarifs, moyennant un préavis minimum de 30 jours pour les abonnements en cours, qui ne s\'appliquera qu\'au renouvellement suivant.'),
      // L'article que le canal store ne publie pas : il décrit une offre qui
      // n'existe pas dans ce build, et c'est précisément celle qui ferait
      // classer l'application dans la catégorie qu'on cherche à éviter.
      //
      // Les articles suivants se renumérotent seuls — leur numéro vient du
      // rang, plus d'une chaîne écrite à la main.
      if (!estStore)
        LegalSection(null, 'Activation par code 1xBet',
          'PronoWin propose une voie d\'activation Premium gratuite pour les utilisateurs disposant d\'un compte actif chez le partenaire 1xBet, sous réserve de remplir les conditions affichées dans l\'Application (code promotionnel, capture d\'écran de vérification). Chaque demande fait l\'objet d\'une vérification manuelle par notre équipe, généralement sous 24 heures ouvrées. Toute tentative de fraude (faux comptes, documents falsifiés, contournement des conditions du partenaire) entraîne le rejet de la demande et peut entraîner la suspension définitive du compte PronoWin concerné.'),
      LegalSection(null, 'Programme de parrainage',
        'PronoWin propose un programme de parrainage permettant à un utilisateur (« le parrain ») d\'inviter de nouveaux utilisateurs (« les filleuls ») et de percevoir une récompense selon les règles affichées dans l\'Application. Les récompenses ne sont créditées qu\'après validation des conditions d\'éligibilité (ex. activation d\'un abonnement par le filleul). Toute fraude avérée (auto-parrainage, comptes fictifs, manipulation du système) entraîne l\'annulation des récompenses concernées et peut donner lieu à la suspension des comptes impliqués.'),
      LegalSection(null, 'Usages interdits',
        'Il est interdit d\'utiliser PronoWin à des fins illégales, de tenter d\'accéder de manière non autorisée à ses systèmes, de perturber son fonctionnement (y compris par des moyens automatisés type robots ou scripts), de reproduire ou d\'extraire son contenu à des fins commerciales sans autorisation, ou d\'usurper l\'identité d\'un tiers. Tout manquement peut entraîner la suspension ou la suppression du compte concerné, sans préjudice d\'éventuelles poursuites.'),
      LegalSection(null, 'Propriété intellectuelle',
        'L\'ensemble des éléments composant PronoWin — textes, analyses, logos, interface, algorithmes, bases de données et code source — sont protégés par le droit de la propriété intellectuelle et demeurent la propriété exclusive de PronoWin ou de ses concédants. Toute reproduction, représentation, modification ou diffusion, totale ou partielle, sans autorisation écrite préalable est strictement interdite.'),
      LegalSection(null, 'Protection des données personnelles',
        'Le traitement de vos données personnelles est décrit en détail dans notre Politique de confidentialité, accessible depuis les Paramètres de l\'Application, qui fait partie intégrante des présentes CGU.'),
      LegalSection(null, 'Jeu responsable',
        'PronoWin, bien que n\'étant pas un opérateur de jeux d\'argent, reconnaît sa proximité thématique avec l\'univers des paris sportifs et s\'engage à promouvoir une pratique responsable. Les principes et ressources d\'aide sont détaillés dans notre page dédiée « Jeu responsable », accessible depuis les Paramètres.'),
      LegalSection(null, 'Limitation de responsabilité',
        'PronoWin met tout en œuvre pour assurer l\'exactitude de ses analyses et la disponibilité de son Service, mais ne peut garantir l\'absence d\'erreur, d\'interruption ou de dysfonctionnement technique. Dans la mesure permise par la loi applicable, PronoWin ne pourra être tenu responsable des pertes financières résultant de paris placés par l\'utilisateur sur toute plateforme tierce, ni des dommages indirects liés à l\'utilisation ou à l\'impossibilité d\'utiliser le Service. L\'Application est fournie « en l\'état », sans garantie de disponibilité permanente.'),
      LegalSection(null, 'Suspension et résiliation',
        'PronoWin peut suspendre ou résilier, temporairement ou définitivement, l\'accès d\'un utilisateur en cas de manquement aux présentes CGU, de fraude avérée, ou sur demande légale. L\'utilisateur peut à tout moment demander la clôture de son compte depuis les Paramètres ou en contactant le support ; cette demande entraîne la suppression de ses données personnelles conformément à notre Politique de confidentialité.'),
      LegalSection(null, 'Droit applicable et litiges',
        'Les présentes CGU sont soumises à la loi applicable dans votre pays de résidence en matière de protection du consommateur, sans préjudice des dispositions d\'ordre public locales. En cas de litige, l\'utilisateur est invité à contacter en priorité le support de PronoWin afin de rechercher une résolution amiable avant toute action contentieuse.'),
      LegalSection(null, 'Contact',
        'Pour toute question relative aux présentes CGU, réclamation ou demande d\'assistance : pronowin2026@gmail.com'),
    ],
    LegalType.confidentialite => [
      LegalSection(null, 'Responsable du traitement',
        'PronoWin est responsable du traitement des données personnelles collectées via l\'Application. Pour toute question relative à cette politique ou à l\'exercice de vos droits, vous pouvez nous contacter à : pronowin2026@gmail.com.'),
      LegalSection(null, 'Données collectées',
        'Nous collectons, selon votre usage de l\'Application : des données d\'identification (numéro de téléphone et/ou e-mail, pseudonyme, date de naissance pour vérifier votre majorité) ; des données de compte (pronostics suivis, favoris, historique, statistiques de bankroll saisies par vous) ; des données techniques (identifiant d\'appareil, token de notification push FCM, version de l\'application, journaux de connexion)${estStore ? "" : " ; et, le cas échéant, des justificatifs transmis volontairement (preuve de paiement d'abonnement, capture d'écran pour l'activation par code partenaire)"}.'),
      LegalSection(null, 'Finalités du traitement',
        'Vos données sont traitées pour : créer et sécuriser votre compte (authentification) ; fournir et personnaliser le Service (pronostics, statistiques, recommandations) ; traiter vos demandes d\'abonnement et de parrainage ; vous envoyer des notifications pertinentes que vous avez autorisées ; assurer la sécurité de l\'Application et prévenir la fraude ; répondre à nos obligations légales ; et améliorer nos services à partir de statistiques d\'usage agrégées.'),
      LegalSection(null, 'Base légale des traitements',
        'Selon les cas, ces traitements reposent sur : l\'exécution du contrat qui vous lie à PronoWin (fourniture du Service) ; votre consentement (notifications${estStore ? "" : ", activation par code partenaire"}) ; l\'intérêt légitime de PronoWin (sécurité, prévention de la fraude, amélioration du Service) ; ou le respect d\'une obligation légale.'),
      LegalSection(null, 'Partage et destinataires des données',
        'Vos données personnelles ne sont jamais vendues à des tiers. Elles peuvent être partagées, dans la stricte mesure nécessaire, avec : nos prestataires techniques (hébergement, envoi de SMS ou d\'e-mails, services de notification push) agissant sur nos instructions ;${estStore ? "" : " nos partenaires (ex. vérification d'une activation via code 1xBet, avec votre consentement explicite) ;"} ou les autorités compétentes lorsque la loi l\'exige.'),
      LegalSection(null, 'Sécurité des données',
        'Vos données sont chiffrées en transit (HTTPS/TLS) et protégées au repos. L\'accès à votre compte repose sur des jetons d\'authentification (JWT) à durée de vie limitée, automatiquement renouvelés, ainsi que, si vous l\'activez, un code PIN ou une authentification biométrique locale à votre appareil. Nous mettons en œuvre des mesures techniques et organisationnelles raisonnables pour prévenir tout accès non autorisé, perte ou divulgation de vos données.'),
      LegalSection(null, 'Durée de conservation',
        'Vos données sont conservées pendant toute la durée de vie de votre compte. En cas de suppression de compte, vos données personnelles identifiantes sont supprimées ou anonymisées dans un délai de 30 jours, sous réserve des durées de conservation plus longues imposées par une obligation légale (ex. données comptables liées à un abonnement).'),
      LegalSection(null, 'Vos droits',
        'Conformément au Règlement Général sur la Protection des Données (RGPD) et aux lois locales applicables, vous disposez d\'un droit d\'accès, de rectification, d\'effacement, de limitation et d\'opposition au traitement de vos données, ainsi que d\'un droit à la portabilité. Vous pouvez exercer ces droits directement depuis les Paramètres de l\'Application (modification du profil, suppression du compte) ou en nous contactant à pronowin2026@gmail.com. Si vous résidez dans l\'Union européenne, vous disposez également du droit d\'introduire une réclamation auprès de l\'autorité de contrôle compétente (en France, la CNIL).'),
      LegalSection(null, 'Cookies et traceurs',
        'L\'application mobile PronoWin n\'utilise pas de cookies au sens web du terme. Certaines préférences (thème, langue, filtres) sont stockées localement sur votre appareil via un mécanisme de stockage local (SharedPreferences), sans transmission à des tiers à des fins publicitaires.'),
      LegalSection(null, 'Transferts de données',
        'Vos données sont hébergées et traitées par des prestataires susceptibles d\'opérer depuis différents pays. Lorsqu\'un transfert hors de votre région implique un niveau de protection différent, nous veillons à ce que des garanties appropriées soient mises en place, conformément à la réglementation applicable.'),
      LegalSection(null, 'Mineurs',
        'PronoWin n\'est pas destiné aux personnes mineures. Nous ne collectons pas sciemment de données concernant des mineurs. Si vous pensez qu\'un compte a été créé par une personne mineure, merci de nous le signaler à pronowin2026@gmail.com afin que nous puissions procéder à sa suppression.'),
      LegalSection(null, 'Modification de cette politique',
        'Cette politique de confidentialité peut être mise à jour pour refléter une évolution de nos pratiques ou de la réglementation. La date de dernière mise à jour est indiquée en haut de cette page ; en cas de modification substantielle, vous en serez informé au sein de l\'Application.'),
    ],
    LegalType.jeuResponsable => [
      LegalSection('⚠️', 'Avertissement important',
        'PronoWin est une plateforme d\'information et d\'analyse sportive : elle n\'accepte ni ne place aucun pari et n\'est pas un opérateur de jeux d\'argent. Les paris sportifs, proposés par des tiers, peuvent néanmoins être addictifs et entraîner des pertes financières importantes. PronoWin ne saurait être tenu responsable des décisions de pari prises par ses utilisateurs sur des plateformes tierces ni de leurs conséquences.'),
      LegalSection('🎯', 'Principes du jeu responsable',
        '• Ne pariez jamais plus que ce que vous pouvez vous permettre de perdre\n• Fixez-vous un budget dédié aux paris et respectez-le strictement, indépendamment de vos gains ou pertes\n• Ne cherchez jamais à « se refaire » après une perte en augmentant vos mises\n• Le jeu doit rester un loisir occasionnel : il ne doit jamais interférer avec votre vie personnelle, familiale ou professionnelle\n• Un pronostic, même bien argumenté, reste une analyse probabiliste — jamais une certitude\n• Évitez de parier sous l\'effet de l\'alcool, de la fatigue ou d\'une émotion forte'),
      LegalSection('🔢', 'Gestion saine du bankroll',
        'Une gestion de bankroll prudente ne consacre jamais plus de 2 à 5 % de son capital total à un seul pari. PronoWin recommande une approche de type « flat betting » (miser un montant fixe et identique à chaque pari, indépendamment du niveau de confiance affiché) plutôt que d\'augmenter ses mises après une perte ou un gain. L\'outil de suivi de bankroll intégré à l\'Application vous aide à visualiser votre exposition réelle dans le temps.'),
      LegalSection('🚨', 'Reconnaître les signes d\'alerte',
        'Le jeu peut devenir problématique de façon progressive. Soyez attentif si vous :\n• Pariez avec de l\'argent destiné à des dépenses essentielles (loyer, factures, nourriture)\n• Empruntez de l\'argent pour parier ou pour rembourser des dettes de jeu\n• Mentez à vos proches sur vos habitudes ou vos pertes de jeu\n• Ressentez de l\'anxiété, de l\'irritabilité ou de la culpabilité liées au jeu\n• Essayez, sans succès répété, de réduire ou d\'arrêter de parier\n• Passez un temps croissant à penser aux paris ou à en parler\n\nSi plusieurs de ces situations vous concernent, il est recommandé de solliciter l\'aide d\'un professionnel.'),
      LegalSection('🛡️', 'Outils de protection disponibles',
        'De nombreux opérateurs de paris sportifs${estStore ? "" : ", dont 1xBet,"} proposent des outils de jeu responsable directement sur leur plateforme : fixation de limites de dépôt ou de mise, plafonnement de session, auto-exclusion temporaire ou définitive. PronoWin vous encourage à activer ces outils directement auprès de l\'opérateur avec lequel vous pariez. Depuis l\'Application, vous pouvez également mettre votre compte PronoWin en pause à tout moment en contactant notre support.'),
      LegalSection('📞', 'Ressources d\'aide',
        'Si vous pensez, pour vous-même ou pour un proche, avoir un problème avec le jeu, n\'hésitez pas à solliciter une aide professionnelle et confidentielle :\n\n🇫🇷 France — Joueurs Info Service : 09 74 75 13 13 (appel non surtaxé, anonyme et gratuit)\n🌐 Gamblers Anonymous (international) : www.gamblersanonymous.org\n🌍 Hors France : rapprochez-vous d\'un professionnel de santé, d\'une structure d\'écoute locale ou de l\'autorité de régulation des jeux de votre pays\n\nVous pouvez également contacter notre support depuis l\'Application pour mettre votre compte PronoWin en pause ou le clôturer temporairement.'),
      LegalSection('✅', 'Engagement de PronoWin',
        'PronoWin s\'engage à :\n• Afficher des messages clairs sur le caractère informatif de ses pronostics et sur les risques liés aux paris sportifs\n• Ne jamais cibler ou solliciter des utilisateurs identifiés comme vulnérables\n• Vérifier l\'âge de ses utilisateurs (18 ans ou plus requis) à la création de compte\n• Fournir un outil de suivi de bankroll pour aider à une gestion responsable\n• Permettre la mise en pause ou la clôture d\'un compte sur simple demande, sans condition'),
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
            colors: [AppColors.primary, AppColors.primaryLight],
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
          child: Text('Dernière mise à jour : $lastUpdated', style: TextStyle(
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
        child: Text(section.badge ?? '$rang', style: const TextStyle(
          color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.w800)),
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
