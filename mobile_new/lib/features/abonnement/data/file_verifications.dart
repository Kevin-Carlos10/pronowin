import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ce qu'il reste à faire confirmer au serveur après un achat.
///
/// ── Pourquoi une file persistée ────────────────────────────────────────────
///
/// Quand `/subscriptions/iap/verify` échoue — réseau coupé, backend
/// indisponible — l'achat est déjà encaissé par le store. L'application le
/// finalise quand même (`completePurchase`), et elle a raison : une
/// transaction laissée en suspens est resoumise par StoreKit à chaque
/// lancement, indéfiniment.
///
/// Mais finaliser veut dire que le store considère l'affaire close. Il ne
/// rejouera rien. L'écran promettait pourtant :
///
///   « Paiement reçu, activation en attente. Rouvre l'app dans un instant ou
///     touche « Restaurer mes achats ». »
///
/// Rouvrir l'app ne faisait rien : plus aucune transaction n'était rejouée, et
/// rien au démarrage ne reprenait la vérification. Seul le bouton
/// « Restaurer » fonctionnait — à condition que l'acheteur y pense. La moitié
/// de la promesse était fausse, et c'est la moitié sur laquelle quelqu'un qui
/// vient de payer se repose.
///
/// La trace tient donc ici : l'identifiant nécessaire à la vérification reste
/// valable indéfiniment côté store, il suffit de le garder et de réessayer.
typedef ChargeVerification = ({String store, String receipt});

/// Accès au stockage, isolé pour que la logique soit éprouvable sans plugin.
abstract class StockageFile {
  Future<String?> lire();
  Future<void> ecrire(String valeur);
}

/// L'implémentation réelle, sur les préférences partagées.
class StockagePreferences implements StockageFile {
  static const cle = 'iap_verifications_en_attente';

  @override
  Future<String?> lire() async =>
      (await SharedPreferences.getInstance()).getString(cle);

  @override
  Future<void> ecrire(String valeur) async =>
      (await SharedPreferences.getInstance()).setString(cle, valeur);
}

/// Lit une file depuis sa forme stockée.
///
/// Tolérante : une valeur absente, vide ou abîmée rend une file vide plutôt
/// que de lever. Perdre la reprise est fâcheux ; empêcher l'application de
/// démarrer à cause d'une préférence corrompue le serait davantage.
List<ChargeVerification> decoderFile(String? brut) {
  if (brut == null || brut.trim().isEmpty) return const [];
  try {
    final lu = jsonDecode(brut);
    if (lu is! List) return const [];
    return lu
        .whereType<Map<String, dynamic>>()
        .map((m) => (
              store: (m['store'] ?? '').toString(),
              receipt: (m['receipt'] ?? '').toString(),
            ))
        .where((c) => c.store.isNotEmpty && c.receipt.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Écrit une file sous sa forme stockée.
String encoderFile(List<ChargeVerification> elements) => jsonEncode(
      elements.map((c) => {'store': c.store, 'receipt': c.receipt}).toList(),
    );

/// Ajoute une charge, sans jamais la doubler.
///
/// Le même achat peut échouer plusieurs fois de suite — une reprise qui
/// retombe sur la même coupure réseau, par exemple. Sans dédoublonnage, la
/// file grossirait à chaque tentative pour un seul achat.
List<ChargeVerification> ajouterA(
  List<ChargeVerification> actuelles,
  ChargeVerification nouvelle,
) {
  final deja = actuelles.any(
      (c) => c.store == nouvelle.store && c.receipt == nouvelle.receipt);
  return deja ? actuelles : [...actuelles, nouvelle];
}

/// Retire une charge dont la vérification a abouti.
List<ChargeVerification> retirerDe(
  List<ChargeVerification> actuelles,
  ChargeVerification faite,
) =>
    actuelles
        .where((c) => !(c.store == faite.store && c.receipt == faite.receipt))
        .toList(growable: false);

/// La file d'attente, telle que le service d'achat s'en sert.
class FileVerifications {
  FileVerifications(this._stockage);

  final StockageFile _stockage;

  Future<List<ChargeVerification>> lire() async =>
      decoderFile(await _stockage.lire());

  Future<void> ajouter(ChargeVerification charge) async {
    final apres = ajouterA(await lire(), charge);
    await _stockage.ecrire(encoderFile(apres));
  }

  Future<void> retirer(ChargeVerification charge) async {
    final apres = retirerDe(await lire(), charge);
    await _stockage.ecrire(encoderFile(apres));
  }
}
