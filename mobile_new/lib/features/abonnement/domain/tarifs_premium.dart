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
  static const mensuelCodeDefaut   = 4200;
  static const annuelCodeDefaut    = 37800;

  static const promoCodeDefaut  = 'PRONOWIN2025';
  static const plateformesDefaut = ['1xbet', 'melbet', 'betwinner'];

  static const delaiDirectDefaut = '30 minutes ouvrables';
  static const delaiCodeDefaut   = '2 heures ouvrables';

  final int mensuelDirect;
  final int annuelDirect;
  final int mensuelCode;
  final int annuelCode;

  final String promoCode;
  final List<String> plateformes;
  final String delaiDirect;
  final String delaiCode;

  /// Numéros de réception publiés par le serveur. **Peut être vide** — et dans
  /// ce cas l'écran doit le dire, pas inventer un numéro.
  final List<Map<String, dynamic>> moyensPaiement;

  const TarifsPremium({
    required this.mensuelDirect,
    required this.annuelDirect,
    required this.mensuelCode,
    required this.annuelCode,
    required this.promoCode,
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
      mensuelDirect: entier('premium_price_monthly_fcfa',      mensuelDirectDefaut),
      annuelDirect:  entier('premium_price_annual_fcfa',       annuelDirectDefaut),
      mensuelCode:   entier('premium_price_monthly_code_fcfa', mensuelCodeDefaut),
      annuelCode:    entier('premium_price_annual_code_fcfa',  annuelCodeDefaut),
      promoCode:     texte('promo_code',          promoCodeDefaut),
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

  /// Prix à collecter pour une combinaison durée × méthode.
  int prix({required bool annuel, required bool avecCode}) => avecCode
      ? (annuel ? annuelCode : mensuelCode)
      : (annuel ? annuelDirect : mensuelDirect);

  /// Le plus bas coût mensuel réellement atteignable, toutes formules
  /// confondues — l'annuel est ramené au mois pour être comparable.
  ///
  /// C'est ce que « à partir de » doit annoncer. L'écrire à la main, c'était
  /// s'engager à le corriger à chaque changement de tarif ; personne ne l'a
  /// fait, et le chiffre affiché ne correspondait plus à rien.
  int get minMensuel {
    final candidats = [
      mensuelDirect, mensuelCode,
      (annuelDirect / 12).round(), (annuelCode / 12).round(),
    ];
    return candidats.reduce((a, b) => a < b ? a : b);
  }

  /// « À partir de 3 150 FCFA », prêt à afficher.
  String get minMensuelFormate => montantExact(minMensuel);

  /// Remise du code promo, en pourcentage entier, **calculée**.
  ///
  /// Le `-30 %` était écrit en dur à trois endroits. Il se trouve être juste
  /// aujourd'hui (4 200 ÷ 6 000) ; il devenait faux au premier changement de
  /// tarif côté serveur, sur l'argument commercial principal de l'écran.
  int get remisePourcent {
    if (mensuelDirect <= 0) return 0;
    final r = ((1 - mensuelCode / mensuelDirect) * 100).round();
    return r.clamp(0, 100);
  }

  /// Y a-t-il un numéro à afficher ? Sinon l'écran doit annoncer
  /// l'indisponibilité plutôt que de servir une constante compilée.
  bool get paiementDisponible => moyensPaiement.isNotEmpty;

  /// Les opérateurs réellement proposés — « Orange Money · Wave ».
  ///
  /// L'écran d'accroche annonçait quatre opérateurs en dur pendant que le
  /// serveur n'en publiait qu'un : la page suivante démentait la précédente.
  String get libelleOperateurs => moyensPaiement
      .map((m) => (m['label'] ?? '').toString())
      .where((l) => l.isNotEmpty)
      .join('  ·  ');
}
