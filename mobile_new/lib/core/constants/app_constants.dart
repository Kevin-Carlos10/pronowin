class AppConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const String accessTokenKey  = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey         = 'user_data';
  static const int otpLength          = 6;
  static const int otpResendDelay     = 60;
  static const String appName         = 'PronoWin';
  static const int pageSize      = 20;
  static const int weekPageSize  = 200; // Toute la semaine en une requête

  /// Domaine public — **source unique**.
  ///
  /// Il etait ecrit en dur a trois endroits, et il nommait `pronowin.app` : un
  /// domaine qui n'existe pas. Verifie depuis le serveur lui-meme, injoignable
  /// en racine comme en API. Chaque partage envoyait donc les gens dans le
  /// vide — sur le canal de croissance le plus naturel de cette application.
  ///
  /// Un lien partage vit pour toujours dans une conversation. C'est le seul
  /// endroit de l'app ou changer d'avis coute cher : il vit ici, une fois.
  static const String domaine = 'pronowin.space';
  static const String siteUrl = 'https://$domaine';

  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.pronowin.app';
  static const String appStoreUrl  = 'https://apps.apple.com/app/pronowin/id0000000000'; // ← remplacer l'ID réel
}

class ApiEndpoints {
  static const String sendOtp        = '/auth/send-otp';
  static const String verifyOtp     = '/auth/verify-otp';
  static const String sendEmailOtp  = '/auth/send-email-otp';
  static const String googleLogin    = '/auth/google';
  static const String verifyEmailOtp= '/auth/verify-email-otp';
  static const String refreshToken  = '/auth/refresh';
  static const String logout        = '/auth/logout';
  // Le backend expose la suppression sur DELETE /profile (droit à l'oubli
  // RGPD, profile.routes.ts). '/auth/delete-account' n'a jamais existé : la
  // suppression aurait échoué en 404 — invisible jusqu'ici, l'écran qui
  // l'appelle n'ayant jamais été branché.
  static const String deleteAccount = '/profile';
  static const String profile       = '/auth/profile';
  static const String acceptTerms   = '/auth/accept-terms';

  static const String pronostics   = '/pronostics';
  // `subscribe`, `plans` et `promoCode` retirés : jamais référencés, et
  // /subscriptions/subscribe comme /subscriptions/promo n'existent pas côté
  // backend. Le paiement passe par /subscriptions/submit-proof.
  //
  // `referral` et `notifications` retirés pour la même raison : zéro
  // référence. Les deux chemins sont appelés en clair là où on s'en sert, si
  // bien que modifier la constante n'aurait rien changé — une déclaration qui
  // paraît gouverner un appel sans le gouverner finit par diverger de lui.
  static const String tutorials    = '/tutorials';
  // Les ligues sont servies sous le préfixe /pronostics — '/leagues' seul
  // renvoyait 404, donc le filtre par championnat n'a jamais rien chargé.
  static const String leagues = '/pronostics/leagues';
}
