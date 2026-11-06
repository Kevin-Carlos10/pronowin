import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/secure_storage.dart';

/// Rangement du code PIN de verrouillage.
///
/// Il était écrit en clair dans `SharedPreferences` sous la clé `pin_code` :
/// un fichier XML dans le répertoire de l'app, lisible sur un appareil rooté et
/// susceptible de partir dans une sauvegarde cloud. Pour une fonctionnalité
/// dont l'unique raison d'être est la sécurité, c'était le mauvais tiroir —
/// d'autant que `flutter_secure_storage` (Keystore Android / Keychain iOS) est
/// déjà une dépendance du projet, utilisée ailleurs.
///
/// Deux changements, et une migration silencieuse :
///
///  1. le secret part dans le stockage chiffré de la plateforme ;
///  2. on n'y range pas le code mais son empreinte salée — un PIN à 4 chiffres
///     ne compte que 10 000 possibilités, donc l'empreinte ne protège pas d'une
///     recherche exhaustive : le chiffrement de la plateforme s'en charge. Elle
///     évite en revanche que le code **lui-même** se retrouve lisible quelque
///     part, ce qui compte parce que les gens réutilisent leur PIN — celui de
///     PronoWin est souvent celui du téléphone ou de la carte bancaire ;
///  3. tout `pin_code` en clair déjà présent est converti au premier accès puis
///     effacé, pour que les comptes existants ne perdent pas leur verrou.
class PinStore {
  PinStore(this._secure);

  final SecureStorageService _secure;

  /// Clé historique, en clair, dans `SharedPreferences`.
  static const _cleHeritee = 'pin_code';

  /// Clés du stockage chiffré.
  static const _cleEmpreinte = 'pin_hash';
  static const _cleSel       = 'pin_salt';

  /// Empreinte d'un code pour un sel donné.
  ///
  /// Le sel est tiré une fois par installation : sans lui, deux appareils
  /// portant le même PIN donneraient la même empreinte, et une table
  /// pré-calculée de 10 000 entrées suffirait à retrouver le code.
  static String _empreinte(String pin, String sel) =>
      sha256.convert(utf8.encode('$sel|$pin')).toString();

  static String _nouveauSel() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// Convertit un code hérité en clair, puis efface l'original.
  ///
  /// Sans cette étape, la mise à jour de l'app déverrouillerait d'elle-même les
  /// comptes qui avaient un PIN : `hasPin()` répondrait « non », et l'écran de
  /// verrouillage serait purement et simplement sauté.
  Future<void> _migrerSiNecessaire() async {
    final p       = await SharedPreferences.getInstance();
    final enClair = p.getString(_cleHeritee);
    if (enClair == null || enClair.isEmpty) return;

    // On n'efface l'ancienne valeur qu'une fois la nouvelle écrite : une
    // coupure au milieu doit laisser un verrou intact, pas un compte ouvert.
    await save(enClair);
    await p.remove(_cleHeritee);
    debugPrint('[PIN] Code migré vers le stockage chiffré.');
  }

  /// Enregistre un nouveau code.
  Future<void> save(String pin) async {
    final sel = _nouveauSel();
    await _secure.write(_cleSel, sel);
    await _secure.write(_cleEmpreinte, _empreinte(pin, sel));
  }

  /// Un code est-il défini ?
  Future<bool> hasPin() async {
    await _migrerSiNecessaire();
    final h = await _secure.read(_cleEmpreinte);
    return h != null && h.isNotEmpty;
  }

  /// Le code saisi est-il le bon ?
  ///
  /// La comparaison est à durée constante. Le gain est théorique sur un clavier
  /// à quatre chiffres, mais c'est la forme correcte et elle ne coûte rien.
  Future<bool> verify(String pin) async {
    await _migrerSiNecessaire();
    final sel = await _secure.read(_cleSel);
    final ref = await _secure.read(_cleEmpreinte);
    if (sel == null || ref == null || ref.isEmpty) return false;
    return _egaliteConstante(_empreinte(pin, sel), ref);
  }

  /// Supprime le code.
  Future<void> clear() async {
    await _secure.delete(_cleEmpreinte);
    await _secure.delete(_cleSel);
    final p = await SharedPreferences.getInstance();
    await p.remove(_cleHeritee);
  }

  static bool _egaliteConstante(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

final pinStoreProvider = Provider<PinStore>(
  (ref) => PinStore(ref.read(secureStorageProvider)),
);
