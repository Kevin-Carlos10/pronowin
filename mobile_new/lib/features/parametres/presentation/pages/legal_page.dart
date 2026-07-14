import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/pages/terms_page.dart';

enum LegalType { cgu, confidentialite, jeuResponsable }

class LegalPage extends StatelessWidget {
  final LegalType type;
  const LegalPage({super.key, required this.type});

  String get _title => switch (type) {
    LegalType.cgu              => 'Conditions d\'utilisation',
    LegalType.confidentialite  => 'Politique de confidentialité',
    LegalType.jeuResponsable   => 'Jeu responsable',
  };

  List<_LegalSection> get _sections => switch (type) {
    LegalType.cgu => [
      _LegalSection('1. Acceptation des conditions',
        'En utilisant PronoWin, vous acceptez les présentes conditions d\'utilisation. Si vous n\'acceptez pas ces conditions, veuillez ne pas utiliser l\'application.'),
      _LegalSection('2. Description du service',
        'PronoWin est une application mobile de pronostics sportifs à titre informatif et de divertissement. Les pronostics fournis ne constituent en aucun cas des conseils financiers.'),
      _LegalSection('3. Compte utilisateur',
        'Vous êtes responsable de la confidentialité de vos identifiants. Toute activité réalisée depuis votre compte est sous votre responsabilité. Vous devez avoir au moins 18 ans pour utiliser ce service.'),
      _LegalSection('4. Utilisation acceptable',
        'Vous vous engagez à ne pas utiliser PronoWin à des fins illégales, à ne pas tenter de pirater ou compromettre la sécurité de l\'application, et à respecter les autres utilisateurs.'),
      _LegalSection('5. Propriété intellectuelle',
        'Tout le contenu de PronoWin (analyses, pronostics, interface) est protégé par les droits d\'auteur. Toute reproduction sans autorisation est interdite.'),
      _LegalSection('6. Limitation de responsabilité',
        'PronoWin ne peut être tenu responsable des pertes financières résultant de l\'utilisation de nos pronostics. Les paris sportifs comportent des risques financiers importants.'),
      _LegalSection('7. Modifications',
        'Nous nous réservons le droit de modifier ces conditions à tout moment. Les modifications entrent en vigueur dès leur publication dans l\'application.'),
      _LegalSection('8. Contact',
        'Pour toute question concernant ces conditions, contactez-nous à : support@pronowin.com'),
    ],
    LegalType.confidentialite => [
      _LegalSection('1. Données collectées',
        'Nous collectons : votre numéro de téléphone (authentification), vos préférences de navigation, votre token FCM (notifications push), et vos transactions sur la plateforme.'),
      _LegalSection('2. Utilisation des données',
        'Vos données sont utilisées pour : vous authentifier, vous envoyer des notifications pertinentes, améliorer nos services, et traiter vos transactions financières.'),
      _LegalSection('3. Partage des données',
        'Nous ne vendons jamais vos données personnelles. Elles peuvent être partagées avec nos prestataires techniques (hébergement, SMS) dans le strict cadre de la prestation de service.'),
      _LegalSection('4. Sécurité',
        'Vos données sont chiffrées en transit (HTTPS) et au repos. Vos tokens JWT expirent après 15 minutes et sont automatiquement renouvelés.'),
      _LegalSection('5. Conservation',
        'Vos données sont conservées tant que votre compte est actif. En cas de suppression de compte, vos données personnelles sont anonymisées sous 30 jours.'),
      _LegalSection('6. Vos droits',
        'Conformément au RGPD, vous avez le droit d\'accéder à vos données, de les rectifier, de les supprimer, et de vous opposer à leur traitement. Contactez-nous à : privacy@pronowin.com'),
      _LegalSection('7. Cookies',
        'L\'application mobile n\'utilise pas de cookies. Nous utilisons SharedPreferences pour stocker vos préférences localement sur votre appareil.'),
    ],
    LegalType.jeuResponsable => [
      _LegalSection('⚠️ Avertissement important',
        'Les paris sportifs peuvent être addictifs et entraîner des pertes financières importantes. PronoWin est une plateforme d\'information et ne saurait être tenu responsable des pertes liées aux paris.'),
      _LegalSection('🎯 Principes du jeu responsable',
        '• Ne pariez jamais plus que ce que vous pouvez vous permettre de perdre\n• Fixez-vous un budget et respectez-le\n• Ne cherchez jamais à vous refaire après une perte\n• Le jeu ne doit pas interférer avec votre vie personnelle ou professionnelle\n• Les pronostics sont des analyses, pas des certitudes'),
      _LegalSection('🔢 Gestion du bankroll',
        'Un bankroll sain ne représente jamais plus de 2-5% par pari. PronoWin recommande le flat betting : miser toujours le même montant, indépendamment de la confiance dans le pronostic.'),
      _LegalSection('🚨 Signes d\'alerte',
        'Consultez un professionnel si vous :\n• Pariez avec de l\'argent destiné aux dépenses essentielles\n• Mentez sur vos habitudes de jeu\n• Ressentez de l\'anxiété ou de la dépression liée aux paris\n• Essayez constamment de récupérer vos pertes'),
      _LegalSection('📞 Ressources d\'aide',
        'Si vous pensez avoir un problème avec le jeu :\n\n🇧🇫 Burkina Faso : Consultez un médecin ou un psychologue\n🌍 SOS Joueurs (France) : 09 74 75 13 13\n🌐 Gamblers Anonymous : www.gamblersanonymous.org\n\nN\'hésitez pas à contacter notre support pour désactiver votre compte temporairement.'),
      _LegalSection('✅ Engagement PronoWin',
        'PronoWin s\'engage à :\n• Afficher des avertissements clairs sur les risques\n• Ne pas cibler les joueurs vulnérables\n• Proposer un outil d\'auto-exclusion sur demande\n• Vérifier l\'âge des utilisateurs (18+ requis)'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(_title),
      ),
      body: type == LegalType.cgu
          ? const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 40),
              child: CguContent())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              itemCount: _sections.length,
              itemBuilder: (_, i) => _SectionWidget(_sections[i]),
            ),
    );
  }
}

class _LegalSection {
  final String title, content;
  const _LegalSection(this.title, this.content);
}

class _SectionWidget extends StatelessWidget {
  final _LegalSection section;
  const _SectionWidget(this.section);
  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 16),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(section.title, style: TextStyle(
        color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
      SizedBox(height: 8),
      Text(section.content, style: TextStyle(
        color: context.cl.textS, fontSize: 13, height: 1.6)),
    ]),
  );
}
