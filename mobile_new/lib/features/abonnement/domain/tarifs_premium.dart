import '../../../shared/utils/montant.dart';

/// Tout ce qu'un écran doit savoir sur l'offre Premium — **source unique**.
///
/// Ces valeurs vivaient à trois endroits qui ne se contrôlaient pas :
/// `_kSubFallback` dans le fournisseur, huit `?? 6000` dans l'écran
/// d'abonnement, et — le plus coûteux — un `'5 000 FCFA'` écrit en dur dans la
/// feuille qui décide l'utilisateur à payer. Ce dernier ne correspondait à
/// **aucun** tarif du système : ni 6 000 (mensuel direct), ni 4 200 (avec
/// code), ni 4 500 (annuel ramené au mois), ni 3 150 (annuel avec code). La
/// feuille annonçait donc un prix inventé, et l'écran suivant en affichait un
/// autre — sans qu'aucune erreur, aucun test ni aucun type ne s'en aperçoive.
///
/// Le serveur reste la vérité ; les valeurs ci-dessous ne servent que si sa
/// réponse manque à l'appel (première installation, hors ligne). Elles sont
/// écrites **une fois**, ici.
class TarifsPremium {
  // ─── Replis, source unique ──────────────────────────────────────────────
  static const mensuelDirectDefaut = 6000;
  static const annuelDirectDefaut  = 54000;

  /// Durée offerte par le parcours « code promo ».
  ///
  /// Ce parcours donnait −30 % sur l'abonnement ; il donne désormais le
  /// **premier mois** gratuit, contre l'ouverture d'un compte partenaire avec
  /// notre code et la preuve du dépôt initial. Il n'y a donc plus de tarif
  /// « code » : ni mensuel, ni annuel, ni remise à calculer.
  static const joursOffreCodeDefaut = 30;

  static const plateformesDefaut = ['1xbet', 'melbet', 'betwinner'];

  static const delaiDirectDefaut = '30 minutes ouvrables';
  static const delaiCodeDefaut   = '2 heures ouvrables';

  final int mensuelDirect;
  final int annuelDirect;

  /// Jours offerts par le parcours « code promo », publiés par le serveur.
  final int joursOffreCode;

  final String promoCode;

  /// Code propre a une plateforme, quand un partenaire exige le sien.
  ///
  /// L'ecran laisse choisir entre trois enseignes mais n'affichait qu'un code.
  /// Si elles n'attribuent pas le meme, deux utilisateurs sur trois ouvraient
  /// un compte avec un code qui ne credite personne — et reclamaient malgre
  /// tout leur mois offert.
  final Map<String, String> codesParPlateforme;
  final List<String> plateformes;
  final String delaiDirect;
  final String delaiCode;

  /// Numéros de réception publiés par le serveur. **Peut être vide** — et dans
  /// ce cas l'écran doit le dire, pas inventer un numéro.
  final List<Map<String, dynamic>> moyensPaiement;

  const TarifsPremium({
    required this.mensuelDirect,
    required this.annuelDirect,
    required this.joursOffreCode,
    required this.promoCode,
    required this.codesParPlateforme,
    required this.plateformes,
    required this.delaiDirect,
    required this.delaiCode,
    required this.moyensPaiement,
  });

  factory TarifsPremium.depuis(Map<String, dynamic>? d) {
    int entier(String cle, int defaut) =>
        (d?[cle] as num?)?.toInt() ?? defaut;

    String texte(String cle, String defaut) {
      final v = d?[cle];
      return (v is String && v.trim().isNotEmpty) ? v : defaut;
    }

    return TarifsPremium(
      mensuelDirect:  entier('premium_price_monthly_fcfa', mensuelDirectDefaut),
      annuelDirect:   entier('premium_price_annual_fcfa',  annuelDirectDefaut),
      joursOffreCode: entier('code_offer_days',            joursOffreCodeDefaut),
      // Aucun repli : un code d'affiliation invente ne vaut rien.
      //
      // La constante valait `PRONOWIN2025` alors que le code en service est
      // `PRONOWIN2026`. Hors ligne, ou le temps d'un hoquet du serveur, l'ecran
      // affichait donc celui de l'an dernier — l'utilisateur le recopiait chez
      // le bookmaker, nous n'etions jamais credites, et son mois offert
      // n'avait plus de justification.
      //
      // Vide, l'ecran doit le dire. C'est la meme regle que pour les numeros
      // de paiement, et pour la meme raison.
      promoCode:     texte('promo_code', ''),
      codesParPlateforme: ((d?['promo_codes'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString()))
        ..removeWhere((_, v) => v.trim().isEmpty),
      delaiDirect:   texte('review_delay_direct', delaiDirectDefaut),
      delaiCode:     texte('review_delay_code',   delaiCodeDefaut),
      plateformes: (d?['betting_platforms'] as List?)
              ?.map((e) => e.toString()).toList() ??
          plateformesDefaut,
      moyensPaiement: (d?['payment_methods'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              // Un moyen sans numéro n'est pas un moyen : le serveur les filtre
              // déjà, on ne laisse pas une entrée vide repasser par ici.
              .where((m) => (m['phone'] ?? '').toString().trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }

  /// Prix à collecter pour une durée.
  ///
  /// Il n'y a plus de dimension « méthode » : le parcours « code promo » ne
  /// facture rien, il offre le premier mois. Garder un paramètre `avecCode`
  /// aurait laissé croire à un tarif qui n'existe plus.
  int prix({required bool annuel}) => annuel ? annuelDirect : mensuelDirect;

  /// Le plus bas coût mensuel réellement payable — l'annuel est ramené au mois
  /// pour être comparable.
  ///
  /// C'est ce que « à partir de » doit annoncer. L'écrire à la main, c'était
  /// s'engager à le corriger à chaque changement de tarif ; personne ne l'a
  /// fait, et le chiffre affiché ne correspondait plus à rien.
  ///
  /// Le mois offert n'entre pas dans ce calcul : ce n'est pas un tarif, c'est
  /// une entrée en matière qui ne se reconduit pas. L'annoncer comme un prix
  /// « à partir de 0 FCFA » décrirait mal ce que coûte l'abonnement.
  int get minMensuel {
    final candidats = [mensuelDirect, (annuelDirect / 12).round()];
    return candidats.reduce((a, b) => a < b ? a : b);
  }

  /// « À partir de 4 500 FCFA », prêt à afficher.
  String get minMensuelFormate => montantExact(minMensuel);

  /// « 1 mois offert » ou « 15 jours offerts », selon ce que publie le serveur.
  String get libelleOffreCode {
    if (joursOffreCode % 30 == 0 && joursOffreCode >= 30) {
      final mois = joursOffreCode ~/ 30;
      return mois == 1 ? '1 mois offert' : '$mois mois offerts';
    }
    return '$joursOffreCode jours offerts';
  }

  /// Y a-t-il un numéro à afficher ? Sinon l'écran doit annoncer
  /// l'indisponibilité plutôt que de servir une constante compilée.
  bool get paiementDisponible => moyensPaiement.isNotEmpty;

  /// Y a-t-il un code d'affiliation a proposer ? Sinon l'ecran annonce que
  /// l'offre est momentanement indisponible, plutot que d'en inventer un.
  bool get offreCodeDisponible =>
      promoCode.trim().isNotEmpty || codesParPlateforme.isNotEmpty;

  /// Code a afficher pour la plateforme choisie : le sien s'il en a un, le
  /// code general sinon.
  String codePour(String plateforme) {
    final propre = codesParPlateforme[plateforme]?.trim() ?? '';
    return propre.isNotEmpty ? propre : promoCode.trim();
  }

  /// Les opérateurs réellement proposés — « Orange Money · Wave ».
  ///
  /// L'écran d'accroche annonçait quatre opérateurs en dur pendant que le
  /// serveur n'en publiait qu'un : la page suivante démentait la précédente.
  String get libelleOperateurs => moyensPaiement
      .map((m) => (m['label'] ?? '').toString())
      .where((l) => l.isNotEmpty)
      .join('  ·  ');
}
