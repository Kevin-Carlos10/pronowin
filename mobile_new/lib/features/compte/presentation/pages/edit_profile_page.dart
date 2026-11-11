import 'package:pronowin/l10n/app_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/image_distante.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../shared/widgets/country_pill_selector.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../parametres/presentation/widgets/reglages_ui.dart';
import '../providers/compte_provider.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../shared/utils/age.dart';
import '../../../../shared/utils/messages.dart';
import 'package:pronowin/shared/utils/initiale.dart';

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/compte';

/// Une adresse e-mail plausible : quelque chose, une arobase, un domaine avec
/// un point. Le serveur reste juge ; ceci évite un aller-retour pour une
/// faute de frappe.
final _formeEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// « Modifier le profil », refait le 11 novembre 2026 au dessin des
/// Paramètres : avatar rond, champs rangés dans des cartes (Identité,
/// Compte), erreurs sous le champ concerné plutôt qu'en bas de l'écran, et un
/// « Enregistrer » toujours visible, actif seulement s'il y a quelque chose à
/// enregistrer. Quitter avec des changements non enregistrés demande
/// confirmation.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _pseudoCtrl    = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  DateTime? _birthDate;
  Country _country     = deviceDefaultCountry();
  bool _loading       = false;
  bool _avatarLoading = false;
  String? _localAvatarPath; // chemin local après sélection
  /// Une tentative d'enregistrement a eu lieu : toutes les erreurs s'affichent,
  /// même celles des champs que l'on n'a pas touchés.
  bool _tente = false;
  /// Ce que contenait le formulaire à l'ouverture, pour savoir s'il a changé.
  late final String _initial;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile != null) {
      _pseudoCtrl.text    = profile['pseudo']     as String? ?? '';
      _emailCtrl.text     = profile['email']      as String? ?? '';
      _firstNameCtrl.text = profile['first_name'] as String? ?? '';
      _lastNameCtrl.text  = profile['last_name']  as String? ?? '';
      final bd = profile['birth_date'] as String?;
      if (bd != null) _birthDate = DateTime.tryParse(bd);
      // Le pays enregistré fait foi : plusieurs pays partagent le même
      // indicatif (+1 → US, CA, PR…), le déduire du numéro choisirait l'un
      // d'eux au hasard. Et comme le formulaire renvoie désormais
      // `country_code`, partir du défaut « BF » écraserait le vrai pays d'un
      // utilisateur dont le numéro n'a pas de préfixe reconnu.
      final savedCode = profile['country_code'] as String?;
      if (savedCode != null && savedCode.isNotEmpty) {
        final saved = CountryService().findByCode(savedCode);
        if (saved != null) _country = saved;
      }

      final phone = profile['phone_number'] as String?;
      if (phone != null && phone.isNotEmpty) {
        // Retire l'indicatif du champ : celui du pays enregistré en priorité,
        // sinon le plus long préfixe qui corresponde.
        if (phone.startsWith('+${_country.phoneCode}')) {
          _phoneCtrl.text = phone.substring(_country.phoneCode.length + 1);
        } else {
          final candidates = CountryService().getAll()
            .where((c) => phone.startsWith('+${c.phoneCode}'))
            .toList()
            ..sort((a, b) => b.phoneCode.length.compareTo(a.phoneCode.length));
          if (candidates.isNotEmpty) {
            _country = candidates.first;
            _phoneCtrl.text = phone.substring(_country.phoneCode.length + 1);
          }
        }
      }
    }
    _initial = _empreinte();
    for (final c in [_pseudoCtrl, _emailCtrl, _firstNameCtrl, _lastNameCtrl, _phoneCtrl]) {
      c.addListener(_rafraichir);
    }
  }

  void _rafraichir() { if (mounted) setState(() {}); }

  /// Le formulaire résumé en une chaîne : changée, il y a à enregistrer.
  String _empreinte() => [
    _pseudoCtrl.text.trim(), _emailCtrl.text.trim(), _firstNameCtrl.text.trim(),
    _lastNameCtrl.text.trim(), _phoneCtrl.text.trim(), _country.countryCode,
    _birthDate?.toIso8601String().split('T').first ?? '',
  ].join('|');

  bool get _modifie => _empreinte() != _initial;

  @override
  void dispose() {
    _pseudoCtrl.dispose(); _emailCtrl.dispose();
    _firstNameCtrl.dispose(); _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Erreurs, champ par champ ──────────────────────────────────────────────
  /// L'erreur d'un champ ne s'affiche qu'une fois le champ modifié, ou après
  /// une tentative d'enregistrement : pas de rouge à l'ouverture.
  String? _erreur(TextEditingController c, String initiale, String? Function(String) regle) {
    final v = c.text.trim();
    if (!_tente && v == initiale) return null;
    return regle(v);
  }

  String? get _erreurPseudo => _erreur(_pseudoCtrl, _initial.split('|')[0],
      (v) => v.length < 3 ? tr(context, "Minimum 3 caractères") : null);
  String? get _erreurEmail => _erreur(_emailCtrl, _initial.split('|')[1],
      (v) => v.isNotEmpty && !_formeEmail.hasMatch(v) ? tr(context, "Adresse e-mail invalide") : null);
  String? get _erreurPrenom => _erreur(_firstNameCtrl, _initial.split('|')[2],
      (v) => v.isNotEmpty && v.length < 2 ? tr(context, "2 caractères minimum") : null);
  String? get _erreurNom => _erreur(_lastNameCtrl, _initial.split('|')[3],
      (v) => v.isNotEmpty && v.length < 2 ? tr(context, "2 caractères minimum") : null);
  String? get _erreurTelephone => _erreur(_phoneCtrl, _initial.split('|')[4],
      (v) => v.isNotEmpty && v.replaceAll(RegExp(r'\D'), '').length < 7
          ? tr(context, "Numéro trop court") : null);

  bool get _valide {
    final avant = _tente;
    _tente = true;
    final ok = [_erreurPseudo, _erreurEmail, _erreurPrenom, _erreurNom, _erreurTelephone]
        .every((e) => e == null);
    _tente = avant;
    return ok;
  }

  // ── Avatar ────────────────────────────────────────────────────────────────
  Future<void> _pickAvatar(ImageSource source) async {
    Navigator.pop(context); // ferme le bottom sheet
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source, imageQuality: 80, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;

    setState(() { _localAvatarPath = picked.path; _avatarLoading = true; });

    try {
      // Base64 et non multipart : c'est le format qu'attend le backend, et le
      // seul chemin d'upload éprouvé du projet (identique aux preuves
      // d'abonnement). Le multipart envoyé jusqu'ici n'était de toute façon
      // reçu par personne — l'endpoint n'existait pas.
      final bytes = await File(picked.path).readAsBytes();
      await ref.read(dioProvider).patch('/profile/avatar', data: {
        'image_base64': 'data:image/jpeg;base64,${base64Encode(bytes)}',
      });
      ref.invalidate(profileProvider);
      if (mounted) _showSnack(tr(context, "Photo de profil mise à jour ✅"));
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _localAvatarPath = null);
        _showSnack(
          e.response?.data?['message'] as String? ?? tr(context, "Erreur lors de l'upload."),
          isError: true);
      }
    } finally {
      if (mounted) setState(() => _avatarLoading = false);
    }
  }

  void _showAvatarSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(margeEcran, 0, margeEcran, margeEcran),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          decoration: BoxDecoration(
            color: context.cl.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.cl.border, width: 0.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
              decoration: BoxDecoration(
                color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(tr(context, "Changer la photo de profil"),
              style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            CarteReglages([
              LigneReglage(
                key: const Key('photo-appareil'),
                icone: Icons.photo_camera_outlined,
                titre: tr(context, "Prendre une photo"),
                onTap: () => _pickAvatar(ImageSource.camera)),
              LigneReglage(
                key: const Key('photo-galerie'),
                icone: Icons.photo_library_outlined,
                titre: tr(context, "Choisir depuis la galerie"),
                onTap: () => _pickAvatar(ImageSource.gallery)),
            ]),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, "Annuler"),
                style: TextStyle(color: context.cl.textS, fontSize: 15))),
          ]),
        ),
      ),
    );
  }

  // ── Formulaire ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate:   DateTime(1940),
      lastDate:    DateTime(now.year - 18, now.month, now.day),
      helpText:    tr(context, "Date de naissance"),
      cancelText:  tr(context, "Annuler"),
      confirmText: tr(context, "Confirmer"),
      // Le jeu de couleurs du thème courant : il était forcé en sombre, et le
      // calendrier s'ouvrait noir sur une page claire.
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_valide) {
      setState(() => _tente = true);
      _showSnack(tr(context, "Corrige les champs en rouge."), isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).patch('/profile', data: {
        'pseudo': _pseudoCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (_firstNameCtrl.text.trim().isNotEmpty)
          'first_name': _firstNameCtrl.text.trim(),
        if (_lastNameCtrl.text.trim().isNotEmpty)
          'last_name': _lastNameCtrl.text.trim(),
        if (_birthDate != null)
          'birth_date': _birthDate!.toIso8601String().split('T')[0],
        if (_phoneCtrl.text.trim().isNotEmpty)
          'phone_number': '+${_country.phoneCode}${_phoneCtrl.text.trim()}',
        // Même raison qu'à la complétion du profil : le pays doit suivre
        // l'indicatif sélectionné, sinon il reste figé sur l'ancienne valeur.
        'country_code': _country.countryCode,
      });
      ref.invalidate(profileProvider);
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) {
        _showSnack(tr(context, "Profil mis à jour ✅"));
        _enregistre = true;
        retourOuAller(context, repli: _repli);
      }
    } on DioException catch (e) {
      _showSnack(
        e.response?.data?['message'] as String? ?? trCurrent("Erreur de mise à jour."),
        isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Vrai une fois enregistré : la sortie qui suit ne demande rien.
  bool _enregistre = false;

  /// Quitter : sans changement, tout de suite ; sinon, après confirmation.
  Future<void> _quitter() async {
    if (!_modifie || _enregistre) {
      retourOuAller(context, repli: _repli);
      return;
    }
    final abandonner = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, "Abandonner les modifications ?")),
        content: Text(tr(ctx, "Tes changements ne seront pas enregistrés.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, "Continuer"))),
          TextButton(
            key: const Key('abandonner-modifications'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, "Abandonner"), style: TextStyle(color: ctx.cl.error))),
        ],
      ),
    );
    if (abandonner == true && mounted) {
      _enregistre = true;
      retourOuAller(context, repli: _repli);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile    = ref.watch(profileProvider).valueOrNull;
    final avatarUrl  = profile?['avatar_url'] as String?;
    final initiale   = initialeAvatar(prenom: _firstNameCtrl.text, pseudo: _pseudoCtrl.text);
    final pseudo     = _pseudoCtrl.text.trim();
    final pret       = _modifie && !_loading;

    Widget initialeSurDegrade() => Container(
      decoration: const BoxDecoration(gradient: LinearGradient(
        colors: AppColors.degradeMarque, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      alignment: Alignment.center,
      child: Text(initiale, style: const TextStyle(
        color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700)));

    return PopScope(
      canPop: !_modifie || _enregistre,
      onPopInvokedWithResult: (aQuitte, _) { if (!aQuitte) _quitter(); },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          leading: IconButton(
            tooltip: tr(context, "Retour"),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _quitter,
          ),
          title: Text(tr(context, "Modifier le profil"),
            style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(margeEcran, 12, margeEcran, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [

            // ─── Avatar ───────────────────────────────────────────────────
            Center(child: Semantics(
              button: true,
              label: tr(context, "Changer la photo de profil"),
              child: GestureDetector(
                key: const Key('avatar-profil'),
                onTap: _showAvatarSheet,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: context.cl.border, width: 1)),
                    child: ClipOval(
                      child: _avatarLoading
                        ? Container(color: context.cl.surface, alignment: Alignment.center,
                            child: const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                        : _localAvatarPath != null
                          ? Image.file(File(_localAvatarPath!), fit: BoxFit.cover)
                          : avatarUrl != null && avatarUrl.isNotEmpty
                            ? ImageDistante(url: avatarUrl, fit: BoxFit.cover, repli: initialeSurDegrade())
                            : initialeSurDegrade(),
                    ),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: context.cl.surface, shape: BoxShape.circle,
                        border: Border.all(color: context.cl.bg, width: 2)),
                      child: Icon(Icons.photo_camera_outlined, color: context.cl.textP, size: 16)),
                  ),
                ]),
              ),
            )),
            const SizedBox(height: 6),
            Center(child: TextButton(
              onPressed: _showAvatarSheet,
              child: Text(tr(context, "Modifier la photo"),
                style: TextStyle(color: context.cl.accent, fontSize: 14, fontWeight: FontWeight.w600)),
            )),
            if (pseudo.isNotEmpty)
              Center(child: Text('@$pseudo',
                style: TextStyle(color: context.cl.textS, fontSize: 13))),
            const SizedBox(height: 22),

            // ─── Identité ─────────────────────────────────────────────────
            EnTeteReglages(tr(context, "Identité")),
            CarteReglages(retrait: 14, [
              _Champ(
                key: const Key('champ-prenom'),
                libelle: tr(context, "Prénom"), controleur: _firstNameCtrl,
                indice: tr(context, "Ton prénom"), erreur: _erreurPrenom,
                majuscules: TextCapitalization.words,
                autofill: const [AutofillHints.givenName]),
              _Champ(
                key: const Key('champ-nom'),
                libelle: tr(context, "Nom"), controleur: _lastNameCtrl,
                indice: tr(context, "Ton nom"), erreur: _erreurNom,
                majuscules: TextCapitalization.words,
                autofill: const [AutofillHints.familyName]),
              _LigneChampTouche(
                key: const Key('champ-naissance'),
                libelle: tr(context, "Date de naissance"),
                onTap: _pickDate,
                valeur: _birthDate == null
                    ? Text(tr(context, "Sélectionner ta date de naissance"),
                        style: TextStyle(color: context.cl.textM, fontSize: 15))
                    : Row(children: [
                        Text('${_birthDate!.day.toString().padLeft(2, '0')}/'
                             '${_birthDate!.month.toString().padLeft(2, '0')}/'
                             '${_birthDate!.year}',
                          style: TextStyle(color: context.cl.textP, fontSize: 15)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.cl.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                          child: Text(tr(context, "{arg0} ans", [_getAge(_birthDate!)]),
                            style: TextStyle(color: context.cl.success, fontSize: 12, fontWeight: FontWeight.w600))),
                      ]),
                fin: Icon(Icons.calendar_today_outlined, size: 18, color: context.cl.textM),
              ),
              _Champ(
                key: const Key('champ-telephone'),
                libelle: tr(context, "Numéro de téléphone"), controleur: _phoneCtrl,
                indice: '70 00 00 00', erreur: _erreurTelephone,
                clavier: TextInputType.phone,
                autofill: const [AutofillHints.telephoneNumberNational],
                avant: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: CountryPillSelector(
                    country: _country, compact: true,
                    onSelect: (c) => setState(() => _country = c)),
                ),
              ),
            ]),
            // L'avis d'âge, à côté de la date qu'il concerne, en simple
            // indication : encadré en couleur d'alerte, il se lisait comme une
            // erreur adressée à un utilisateur de 20 ans.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                tr(context, "PronoWin est réservé aux personnes de 18 ans et plus."),
                style: TextStyle(color: context.cl.textM, fontSize: 12)),
            ),
            const SizedBox(height: 22),

            // ─── Compte ───────────────────────────────────────────────────
            EnTeteReglages(tr(context, "Compte")),
            CarteReglages(retrait: 14, [
              _Champ(
                key: const Key('champ-pseudo'),
                libelle: tr(context, "Pseudo"), controleur: _pseudoCtrl,
                indice: tr(context, "Ton pseudo"), erreur: _erreurPseudo,
                aide: tr(context, "Visible dans les commentaires et le classement."),
                prefixe: '@',
                autofill: const [AutofillHints.username]),
              _Champ(
                key: const Key('champ-email'),
                libelle: tr(context, "Email (optionnel)"), controleur: _emailCtrl,
                indice: 'exemple@email.com', erreur: _erreurEmail,
                clavier: TextInputType.emailAddress,
                autofill: const [AutofillHints.email]),
            ]),
          ],
        ),
        // Toujours visible, même clavier ouvert ; actif s'il y a quelque
        // chose à enregistrer.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(margeEcran, 8, margeEcran, 8),
            decoration: BoxDecoration(
              color: context.cl.bg,
              border: Border(top: BorderSide(color: context.cl.border, width: 0.5))),
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                key: const Key('enregistrer-profil'),
                onPressed: pret ? _save : null,
                child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_modifie ? tr(context, "Enregistrer") : tr(context, "Aucune modification")),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// L'age affiche sous la date de naissance.
  ///
  /// Cette page portait sa propre division par 365,25 — la troisieme copie du
  /// meme calcul approximatif, apres celle de l'ecran du compte et celle du
  /// serveur. Elle se trompe d'un an le jour de l'anniversaire, et c'est ici
  /// que l'ecart compte le plus : la ligne est verte, elle sert a confirmer
  /// qu'on est majeur.
  int _getAge(DateTime dob) => ageRevolu(dob);

  void _showSnack(String msg, {bool isError = false}) =>
    afficherMessage(context, msg, type: isError ? TypeMessage.erreur : TypeMessage.succes);
}

/// Un champ de formulaire dans une carte : le libellé au-dessus, la saisie
/// sans cadre (la carte en tient lieu), l'erreur ou l'aide en dessous.
class _Champ extends StatelessWidget {
  final String libelle;
  final TextEditingController controleur;
  final String? indice, erreur, aide, prefixe;
  final TextInputType? clavier;
  final TextCapitalization majuscules;
  final Iterable<String>? autofill;
  final Widget? avant;
  const _Champ({super.key, required this.libelle, required this.controleur,
    this.indice, this.erreur, this.aide, this.prefixe, this.clavier,
    this.majuscules = TextCapitalization.none, this.autofill, this.avant});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(libelle, style: TextStyle(
        color: erreur != null ? context.cl.error : context.cl.textS,
        fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Row(children: [
        ?avant,
        Expanded(child: TextField(
          controller: controleur,
          keyboardType: clavier,
          textCapitalization: majuscules,
          autofillHints: autofill,
          style: TextStyle(color: context.cl.textP, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            hintText: indice,
            hintStyle: TextStyle(color: context.cl.textM, fontSize: 15),
            prefixText: prefixe,
            prefixStyle: TextStyle(color: context.cl.textM, fontSize: 15),
          ),
        )),
      ]),
      if (erreur != null || aide != null) Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(erreur ?? aide!, style: TextStyle(
          color: erreur != null ? context.cl.error : context.cl.textM, fontSize: 12)),
      ),
    ]),
  );
}

/// Une ligne de la carte qui s'ouvre au toucher (la date de naissance) :
/// même dessin qu'un champ, avec une icône à droite.
class _LigneChampTouche extends StatelessWidget {
  final String libelle;
  final Widget valeur;
  final Widget? fin;
  final VoidCallback onTap;
  const _LigneChampTouche({super.key, required this.libelle, required this.valeur,
    required this.onTap, this.fin});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(libelle, style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          valeur,
        ])),
        ?fin,
      ]),
    ),
  );
}
