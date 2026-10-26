import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../providers/sessions_provider.dart';

class SessionsSheet extends ConsumerWidget {
  const SessionsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsAppareilsProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.devices_rounded, color: context.cl.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, "Appareils connectés"),
                    style: TextStyle(
                      color: context.cl.textP,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, "Actualiser"),
                  onPressed: sessions.isLoading
                      ? null
                      : () => ref.invalidate(sessionsAppareilsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: sessions.when(
                skipLoadingOnRefresh: false,
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => SingleChildScrollView(
                  child: ErreurChargement(
                    erreur: e,
                    quoi: tr(context, "les appareils connectés"),
                    onRetry: () => ref.invalidate(sessionsAppareilsProvider),
                  ),
                ),
                data: (liste) => liste.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(tr(context, "Aucune session ouverte.")),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: liste.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _SessionTile(session: liste[i]),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, "Fermer")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final SessionAppareil session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final nom = switch (s.plateforme) {
      'ios' => tr(context, "Appareil iOS"),
      'android' => tr(context, "Appareil Android"),
      'web' => tr(context, "Navigateur web"),
      _ => tr(context, "Appareil non identifié"),
    };
    final icone = switch (s.plateforme) {
      'ios' => Icons.phone_iphone_rounded,
      'android' => Icons.phone_android_rounded,
      'web' => Icons.language_rounded,
      _ => Icons.devices_other_rounded,
    };
    String date(DateTime d) => DateFormat.yMMMd(
      AppStrings.of(context).locale.languageCode,
    ).add_Hm().format(d);
    return Container(
      key: ValueKey(s.id),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.actuelle
            ? context.cl.success.withValues(alpha: 0.06)
            : context.cl.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: s.actuelle
              ? context.cl.success.withValues(alpha: 0.3)
              : context.cl.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icone,
            color: s.actuelle ? context.cl.success : context.cl.textS,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  style: TextStyle(
                    color: context.cl.textP,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, s.actuelle ? "Cet appareil" : "Session ouverte"),
                  style: TextStyle(
                    color: s.actuelle ? context.cl.success : context.cl.textS,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.derniereActivite == null
                      ? tr(context, "Dernière activité inconnue")
                      : tr(context, "Dernière activité : {arg0}", [
                          date(s.derniereActivite!),
                        ]),
                  style: TextStyle(color: context.cl.textS, fontSize: 11),
                ),
                if (s.debut != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    tr(context, "Connexion le {arg0}", [date(s.debut!)]),
                    style: TextStyle(color: context.cl.textM, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
