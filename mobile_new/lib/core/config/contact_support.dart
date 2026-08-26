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
  static const telegram = 'https://t.me/carlospronost';

  /// Canal WhatsApp. Il vivait en dur dans l'écran Paramètres, à côté d'un
  /// Telegram déjà regroupé ici — deux liens de même nature, à deux endroits.
  static const whatsapp = 'https://whatsapp.com/channel/0029Vb88L8BKAwEppGPhXQ1T';

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
}
