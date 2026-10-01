import 'package:pronowin/l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../pronostics/presentation/widgets/moderation_commentaire.dart';

/// Les membres que l'on a bloqués depuis les commentaires, et le moyen de
/// revenir sur ce choix.
class MembresBloquesPage extends ConsumerWidget {
  const MembresBloquesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bloques = ref.watch(membresBloquesProvider);
    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        title: Text(tr(context, "Membres bloqués"),
          style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: bloques.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(messageRefus(context, e), textAlign: TextAlign.center,
              style: TextStyle(color: context.cl.textS, fontSize: 14)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(membresBloquesProvider),
              child: Text(tr(context, "Réessayer"))),
          ]),
        )),
        data: (liste) => liste.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                tr(context, "Aucun membre bloqué. Pour bloquer un membre, ouvre le menu « ⋯ » d'un de ses commentaires."),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.5)),
            ))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: liste.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: context.cl.border),
              itemBuilder: (_, i) {
                final m = liste[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(m.pseudo.isEmpty ? '?' : m.pseudo[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                  title: Text(m.pseudo, style: TextStyle(color: context.cl.textP)),
                  trailing: TextButton(
                    onPressed: () async {
                      final messager = ScaffoldMessenger.of(context);
                      final message = tr(context, "{arg0} est débloqué.", [m.pseudo]);
                      try {
                        await debloquerMembre(ref.read(dioProvider), m.userId);
                        ref.invalidate(membresBloquesProvider);
                        messager.showSnackBar(SnackBar(
                          content: Text(message), behavior: SnackBarBehavior.floating));
                      } catch (e) {
                        if (context.mounted) {
                          messager.showSnackBar(SnackBar(
                            content: Text(messageRefus(context, e)), behavior: SnackBarBehavior.floating));
                        }
                      }
                    },
                    child: Text(tr(context, "Débloquer")),
                  ),
                );
              },
            ),
      ),
    );
  }
}
