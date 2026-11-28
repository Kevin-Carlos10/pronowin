import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/messages.dart';
import '../../../../shared/utils/retour.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// « Donne-nous ton avis » (8 novembre 2026), comme Sofascore : un message,
/// une capture d'écran facultative. La version de l'application et le
/// système partent avec, pour ne pas avoir à les demander. L'équipe les lit
/// dans l'administration (page « Avis des utilisateurs »).
class AvisPage extends ConsumerStatefulWidget {
  const AvisPage({super.key});

  /// Choix de la capture : remplaçable pour les tests.
  @visibleForTesting
  static Future<XFile?> Function() choisirCapture = () => ImagePicker().pickImage(
      source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);

  /// Version complète (« 1.0.35 (51) ») : remplaçable pour les tests.
  @visibleForTesting
  static Future<String?> Function() lireVersion = () async {
    try {
      final i = await PackageInfo.fromPlatform();
      return '${i.version} (${i.buildNumber})';
    } catch (_) {
      return null;
    }
  };

  @override
  ConsumerState<AvisPage> createState() => _AvisPageState();
}

const _messageMin = 10;
const _messageMax = 2000;
final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

class _AvisPageState extends ConsumerState<AvisPage> {
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  Uint8List? _apercu;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final etat = ref.read(authProvider);
    final compte = etat is AuthAuthenticated ? etat.user : null;
    _emailCtrl.text = compte?.email ?? '';
    _emailCtrl.addListener(_rafraichir);
    _messageCtrl.addListener(_rafraichir);
  }

  void _rafraichir() => setState(() {});

  @override
  void dispose() {
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _connecte => ref.read(authProvider) is AuthAuthenticated;

  bool get _emailValide {
    final e = _emailCtrl.text.trim();
    // Connecté : le compte a déjà une adresse, le champ peut rester vide.
    if (e.isEmpty) return _connecte;
    return _email.hasMatch(e);
  }

  bool get _pret => _messageCtrl.text.trim().length >= _messageMin && _emailValide && !_envoi;

  Future<void> _choisir() async {
    final f = await AvisPage.choisirCapture();
    if (f == null || !mounted) return;
    final octets = await f.readAsBytes();
    if (mounted) setState(() => _apercu = octets);
  }

  Future<void> _envoyer() async {
    if (!_pret) return;
    FocusScope.of(context).unfocus();
    setState(() => _envoi = true);
    final merci = tr(context, "Merci ! Ton message est bien arrivé : on te répond par e-mail si besoin.");
    final echec = tr(context, "L'envoi n'a pas abouti. Vérifie ta connexion et réessaie.");
    try {
      final octets = _apercu;
      await ref.read(dioProvider).post('/support/avis', data: {
        'message': _messageCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (octets != null) 'image_base64': 'data:image/jpeg;base64,${base64Encode(octets)}',
        'plateforme': switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'ios',
          TargetPlatform.android => 'android',
          _ => 'autre',
        },
        'version_app': await AvisPage.lireVersion(),
      });
      if (!mounted) return;
      afficherMessage(context, merci, type: TypeMessage.succes);
      retourOuAller(context, repli: '/parametres');
    } on DioException catch (e) {
      if (!mounted) return;
      final message = e.response?.data is Map ? (e.response!.data as Map)['message'] as String? : null;
      afficherMessage(context, message ?? echec, type: TypeMessage.erreur);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  InputDecoration _champ(BuildContext context, String indice) => InputDecoration(
    hintText: indice,
    filled: true,
    fillColor: context.cl.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.cl.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.cl.border)),
  );

  @override
  Widget build(BuildContext context) {
    final longueur = _messageCtrl.text.trim().length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr(context, "Retour"),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => retourOuAller(context, repli: '/parametres'),
        ),
        title: Text(tr(context, "Donne-nous ton avis")),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(tr(context, "Un bug, une idée, une compétition qui manque : dis-nous comment améliorer PronoWin."),
            style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.4)),
          const SizedBox(height: 18),
          TextField(
            key: const Key('avis-email'),
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _champ(context, _connecte ? tr(context, "Ton e-mail (facultatif)") : tr(context, "Ton e-mail *")),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              _connecte
                  ? tr(context, "Laissé vide, on te répond à l'adresse de ton compte.")
                  : tr(context, "Obligatoire, pour qu'on puisse te répondre."),
              style: TextStyle(color: context.cl.textM, fontSize: 12)),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('avis-message'),
            controller: _messageCtrl,
            minLines: 5,
            maxLines: 10,
            maxLength: _messageMax,
            textCapitalization: TextCapitalization.sentences,
            decoration: _champ(context, tr(context, "Décris ton problème ou ta suggestion")),
          ),
          if (longueur > 0 && longueur < _messageMin)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(tr(context, "Encore {arg0} caractères au moins.", [_messageMin - longueur]),
                style: TextStyle(color: context.cl.warning, fontSize: 12)),
            ),
          const SizedBox(height: 6),
          if (_apercu == null)
            OutlinedButton.icon(
              key: const Key('avis-capture'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: context.cl.textP,
                side: BorderSide(color: context.cl.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _envoi ? null : _choisir,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tr(context, "Joindre une capture d'écran (facultatif)")),
            )
          else
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_apercu!, width: 72, height: 128, fit: BoxFit.cover,
                  semanticLabel: tr(context, "Capture jointe"))),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(context, "Capture jointe"),
                style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600))),
              IconButton(
                key: const Key('avis-retirer-capture'),
                tooltip: tr(context, "Retirer la capture"),
                onPressed: _envoi ? null : () => setState(() => _apercu = null),
                icon: Icon(Icons.close_rounded, color: context.cl.textS)),
            ]),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              key: const Key('avis-envoyer'),
              onPressed: _pret ? _envoyer : null,
              child: _envoi
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(tr(context, "Envoyer"), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
