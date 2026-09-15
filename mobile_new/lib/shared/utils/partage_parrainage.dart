import '../../core/constants/app_constants.dart';

/// Le message qu'un parrain envoie à ses filleuls.
///
/// ── Il vivait en deux exemplaires ─────────────────────────────────────────
///
/// L'onglet Compte et la page Parrainage en portaient chacun une copie,
/// recopiée à la main — le commentaire de la première disait d'ailleurs
/// « identique à celui de ParrainagePage ». Les deux ont donc vieilli
/// ensemble, avec la même erreur :
///
///     👉 Télécharge l'app : pronowin.com/download
///
/// Trois défauts dans cette ligne. Le domaine n'est pas le nôtre — c'est
/// `.space`, pas `.com`. Le chemin `/download` répond 404 sur le vrai site.
/// Et sans schéma, aucune messagerie n'en fait un lien cliquable : le filleul
/// devait recopier une adresse qui, de toute façon, ne menait nulle part.
///
/// Un message de parrainage est le canal de croissance le plus direct de cette
/// application, et il vit pour toujours dans une conversation. Il vit donc ici,
/// une fois, et il prend son adresse de [AppConstants.apkDownloadUrl].
String messageParrainage(String code) =>
    '🏆 Rejoins PronoWin et gagne avec les meilleurs pronostics !\n'
    'Utilise mon code de parrainage : *$code*\n'
    '👉 Télécharge l\'app : ${AppConstants.apkDownloadUrl}\n'
    '💰 Tu m\'aides aussi à gagner des commissions !';
