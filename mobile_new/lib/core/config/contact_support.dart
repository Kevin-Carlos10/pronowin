import 'package:url_launcher/url_launcher.dart';

/// Où joindre l'équipe — **source unique**.
///
/// L'adresse et le canal Telegram vivaient dans l'écran Paramètres. Le premier
/// écran qui en avait besoin ailleurs — celui où l'utilisateur vient d'envoyer
/// de l'argent et n'a plus sa capture — allait naturellement en recopier une
/// deuxième version. Deux adresses divergentes dans une application, c'est
/// celle qui n'est plus relevée qui reçoit les demandes urgentes.
class ContactSupport {
  static const email    = 'pronowin2026@gmail.com';

  /// Canal Telegram officiel de PronoWin.
  ///
  /// Valait `t.me/carlospronost` — un canal personnel — pendant que le site
  /// vitrine renvoyait vers `t.me/pronowin2026`, celui qui porte la marque, sa
  /// description et son logo. Les deux vitrines de la même application
  /// envoyaient donc les utilisateurs à deux endroits différents, et celui que
  /// l'application désignait n'était pas celui que l'équipe anime.
  ///
  /// La « source unique » que cette classe promet ne l'était que dans
  /// l'application : elle s'arrêtait à la frontière du dépôt.
  static const telegram = 'https://t.me/pronowin2026';

  /// Canal WhatsApp. Il vivait en dur dans l'écran Paramètres, à côté d'un
  /// Telegram déjà regroupé ici — deux liens de même nature, à deux endroits.
  static const whatsapp = 'https://whatsapp.com/channel/0029Vb88L8BKAwEppGPhXQ1T';

  /// Page Facebook. Elle était restée écrite en dur dans l'écran Paramètres,
  /// seule de sa catégorie, pendant que Telegram et WhatsApp étaient regroupés
  /// ici — c'est-à-dire dans la position exacte qu'occupait le Telegram le
  /// jour où il a divergé du site.
  ///
  /// L'adresse n'a pas été vérifiée : elle est reprise telle quelle.
  static const facebook = 'https://www.facebook.com/Carlospronos11/';

  /// Ouvre le client mail, avec un objet déjà rempli quand on en fournit un.
  ///
  /// Le sujet compte plus qu'il n'y paraît : une demande intitulée « Paiement
  /// envoyé — capture manquante » se traite sans échange préalable.
  static Future<void> ouvrirEmail({String? sujet, String? corps}) {
    final params = <String, String>{};
    if (sujet != null) params['subject'] = sujet;
    if (corps != null) params['body']    = corps;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return launchUrl(Uri.parse('mailto:$email${query.isEmpty ? '' : '?$query'}'));
  }

  static Future<void> ouvrirTelegram() =>
      launchUrl(Uri.parse(telegram), mode: LaunchMode.externalApplication);

  static Future<void> ouvrirWhatsapp() =>
      launchUrl(Uri.parse(whatsapp), mode: LaunchMode.externalApplication);

  static Future<void> ouvrirFacebook() =>
      launchUrl(Uri.parse(facebook), mode: LaunchMode.externalApplication);
}
