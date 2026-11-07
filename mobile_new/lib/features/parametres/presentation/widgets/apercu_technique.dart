import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/config/distribution_channel.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/messages.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// « Aperçu technique » (7 novembre 2026, repris de 1xBet) : la version, le
/// canal, le système, la langue, le compte et la date d'installation, avec un
/// bouton « Copier » — de quoi décrire un problème au support sans chercher
/// ces informations.
///
/// Rien de privé au-delà de l'identifiant du compte, que le support doit
/// connaître pour aider ; ni position, ni contacts, ni appareil précis.
class ApercuTechnique {
  final String version, build, canal, systeme, langue, compte;
  final DateTime? installation;
  const ApercuTechnique({required this.version, required this.build, required this.canal,
    required this.systeme, required this.langue, required this.compte, this.installation});

  /// Les lignes affichées et copiées : (libellé, valeur).
  List<(String, String)> lignes(BuildContext context) => [
    (tr(context, "Version"), '$version ($build)'),
    (tr(context, "Canal"), canal),
    (tr(context, "Système"), systeme),
    (tr(context, "Langue"), langue),
    (tr(context, "Compte"), compte),
    if (installation != null)
      (tr(context, "Installée le"), DateFormat('dd/MM/yyyy HH:mm').format(installation!.toLocal())),
  ];

  /// Le texte copié : une ligne par information, prêt à coller dans un message.
  String texte(BuildContext context) =>
      ['PronoWin', for (final (l, v) in lignes(context)) '$l : $v'].join('\n');
}

String _canal(CanalDistribution c) => c == CanalDistribution.direct
    ? 'APK direct'
    : (!kIsWeb && Platform.isIOS) ? 'App Store' : 'Google Play';

String _systeme() {
  if (kIsWeb) return 'Web';
  final nom = Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : Platform.operatingSystem;
  return '$nom ${Platform.operatingSystemVersion}';
}

/// Rassemble l'aperçu ; [infos] remplaçable pour les bancs d'essai.
Future<ApercuTechnique> lireApercuTechnique(WidgetRef ref,
    {Future<PackageInfo> Function() infos = PackageInfo.fromPlatform, String? systeme}) async {
  final p = await infos();
  final auth = ref.read(authProvider);
  return ApercuTechnique(
    version: p.version,
    build: p.buildNumber,
    canal: _canal(ref.read(canalDistributionProvider)),
    systeme: systeme ?? _systeme(),
    langue: AppStrings.current.locale.languageCode,
    compte: auth is AuthAuthenticated ? auth.user.id : 'invité',
    installation: p.installTime,
  );
}

/// La fenêtre « Aperçu technique » et son bouton « Copier ».
Future<void> afficherApercuTechnique(BuildContext context, WidgetRef ref,
    {Future<PackageInfo> Function() infos = PackageInfo.fromPlatform, String? systeme}) async {
  final apercu = await lireApercuTechnique(ref, infos: infos, systeme: systeme);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogue) {
      final cl = dialogue.cl;
      return AlertDialog(
        backgroundColor: cl.surface,
        title: Text(tr(dialogue, "Aperçu technique"),
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (libelle, valeur) in apercu.lignes(dialogue))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 92, child: Text(libelle, style: TextStyle(color: cl.textM, fontSize: 12.5))),
                Expanded(child: SelectableText(valeur,
                  style: TextStyle(color: cl.textP, fontSize: 12.5, fontWeight: FontWeight.w600))),
              ]),
            ),
          const SizedBox(height: 8),
          Text(tr(dialogue, "Colle ces informations dans ton message au support."),
            style: TextStyle(color: cl.textM, fontSize: 11.5)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogue), child: Text(tr(dialogue, "Fermer"))),
          FilledButton.icon(
            key: const Key('copier-apercu'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(tr(dialogue, "Copier")),
            onPressed: () async {
              final texte = apercu.texte(dialogue);
              final copie = tr(dialogue, "Informations copiées");
              await Clipboard.setData(ClipboardData(text: texte));
              if (!dialogue.mounted) return;
              Navigator.pop(dialogue);
              if (context.mounted) afficherMessage(context, copie, type: TypeMessage.succes);
            },
          ),
        ],
      );
    },
  );
}
