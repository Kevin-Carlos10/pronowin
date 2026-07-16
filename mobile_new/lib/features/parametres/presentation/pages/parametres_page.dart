import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/security_provider.dart';

class ParametresPage extends ConsumerWidget {
  const ParametresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings     = ref.watch(settingsProvider);
    final bioAvailable = ref.watch(bioAvailableProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Paramètres'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [

          // ─── APPARENCE ────────────────────────────────────────────────
          _SectionHeader('Apparence')
            .animate().fadeIn(duration: 300.ms, delay: 50.ms),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.dark_mode_rounded, iconColor: const Color(0xFF818CF8),
              title: 'Thème', trailing: settings.themeName,
              onTap: () => _showThemePicker(context, ref, settings.themeMode),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.language_rounded, iconColor: AppColors.info,
              title: 'Langue', trailing: settings.langName,
              onTap: () => _showLangPicker(context, ref, settings.lang),
            ),
          ]).animate(delay: 80.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── NOTIFICATIONS ────────────────────────────────────────────
          _SectionHeader('Notifications')
            .animate().fadeIn(duration: 300.ms, delay: 100.ms),
          _SettingsCard(children: [
            _SwitchTile(
              icon: Icons.sports_soccer_rounded, iconColor: AppColors.success,
              title: 'Alertes matchs', subtitle: '1h avant chaque pronostic',
              value: settings.notifMatch,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('match'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.local_offer_rounded, iconColor: AppColors.primaryLight,
              title: 'Offres & Promotions', subtitle: 'Codes promo et offres spéciales',
              value: settings.notifPromo,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('promo'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.people_rounded, iconColor: const Color(0xFFA78BFA),
              title: 'Parrainage', subtitle: 'Quand un filleul s\'abonne',
              value: settings.notifReferral,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('referral'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.account_balance_wallet_rounded, iconColor: AppColors.warning,
              title: 'Paiements', subtitle: 'Dépôts et retraits',
              value: settings.notifPayment,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('payment'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.workspace_premium_rounded, iconColor: AppColors.info,
              title: 'Abonnement Premium', subtitle: 'Expiration et renouvellement',
              value: settings.notifPremium,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('premium'),
            ),
          ]).animate(delay: 130.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── SÉCURITÉ ─────────────────────────────────────────────────
          _SectionHeader('Sécurité')
            .animate().fadeIn(duration: 300.ms, delay: 150.ms),
          _SettingsCard(children: [

            // Code PIN
            _SwitchTile(
              icon: Icons.pin_rounded, iconColor: AppColors.warning,
              title: 'Code PIN',
              subtitle: settings.pinEnabled
                ? 'Actif — l\'app se verrouille à la fermeture'
                : 'Protéger l\'app avec un code à 4 chiffres',
              value: settings.pinEnabled,
              onChanged: (v) async {
                if (v) {
                  await context.push('/parametres/pin');
                } else {
                  _showDisablePinSheet(context, ref);
                }
              },
            ),
            const _Divider(),

            // Biométrie
            bioAvailable.when(
              data: (available) => _SwitchTile(
                icon: Icons.fingerprint_rounded, iconColor: AppColors.success,
                title: 'Biométrie',
                subtitle: available
                  ? (settings.bioEnabled
                      ? 'Actif — déverrouillage par empreinte'
                      : 'Déverrouiller avec empreinte / Face ID')
                  : 'Non disponible sur cet appareil',
                value: settings.bioEnabled && available,
                onChanged: available ? (v) async {
                  if (v) {
                    final auth = LocalAuthentication();
                    try {
                      final ok = await auth.authenticate(
                        localizedReason: 'Confirmez pour activer la biométrie',
                        options: const AuthenticationOptions(
                          biometricOnly: false, stickyAuth: true),
                      );
                      if (ok) {
                        await ref.read(settingsProvider.notifier).setBioEnabled(true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('✅ Biométrie activée !'),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Erreur biométrie : $e'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    }
                  } else {
                    await ref.read(settingsProvider.notifier).setBioEnabled(false);
                  }
                } : null,
              ),
              loading: () => _SwitchTile(
                icon: Icons.fingerprint_rounded, iconColor: context.cl.textM,
                title: 'Biométrie', subtitle: 'Vérification en cours...',
                value: false, onChanged: null,
              ),
              error: (_, _) => _SwitchTile(
                icon: Icons.fingerprint_rounded, iconColor: context.cl.textM,
                title: 'Biométrie', subtitle: 'Non disponible sur cet appareil',
                value: false, onChanged: null,
              ),
            ),
            const _Divider(),

            // Changer le PIN (si activé)
            if (settings.pinEnabled) ...[
              _NavTile(
                icon: Icons.edit_rounded, iconColor: AppColors.info,
                title: 'Changer le code PIN',
                subtitle: 'Modifier ton code de sécurité',
                onTap: () => context.push('/parametres/pin'),
              ),
              const _Divider(),
            ],

            _NavTile(
              icon: Icons.devices_rounded, iconColor: AppColors.info,
              title: 'Sessions actives',
              subtitle: 'Voir et gérer tes connexions',
              onTap: () => _showSessionsSheet(context),
            ),
          ]).animate(delay: 180.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── COMPTE ───────────────────────────────────────────────────
          _SectionHeader('Mon compte')
            .animate().fadeIn(duration: 300.ms, delay: 200.ms),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.edit_rounded, iconColor: AppColors.primary,
              title: 'Modifier le profil', subtitle: 'Pseudo, email, avatar',
              onTap: () => context.push('/compte/edit'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.storage_rounded, iconColor: context.cl.textS,
              title: 'Vider le cache', subtitle: 'Libérer l\'espace de stockage',
              onTap: () => _showClearCacheSheet(context, ref),
            ),
          ]).animate(delay: 230.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── LÉGAL ────────────────────────────────────────────────────
          _SectionHeader('Informations légales')
            .animate().fadeIn(duration: 300.ms, delay: 250.ms),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.description_rounded, iconColor: context.cl.textM,
              title: 'Conditions d\'utilisation',
              onTap: () => context.push('/parametres/cgu'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.privacy_tip_rounded, iconColor: context.cl.textM,
              title: 'Politique de confidentialité',
              onTap: () => context.push('/parametres/confidentialite'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.casino_rounded, iconColor: AppColors.warning,
              title: 'Jeu responsable', subtitle: 'Ressources et aide',
              onTap: () => context.push('/parametres/jeu-responsable'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.info_outline_rounded, iconColor: context.cl.textM,
              title: 'À propos', trailing: 'v1.0.0',
              onTap: () => _showAboutSheet(context),
            ),
          ]).animate(delay: 280.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'PronoWin v1.0.0\n© 2026 PronoWin. Tous droits réservés.',
              style: TextStyle(color: context.cl.textM, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ).animate(delay: 330.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  // ─── Bottom sheet : désactiver le PIN ────────────────────────────────────────
  void _showDisablePinSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        icon: Icons.lock_reset_rounded,
        iconColor: AppColors.warning,
        title: 'Désactiver le PIN ?',
        body: 'L\'application ne sera plus protégée par un code PIN.\nTa sécurité sera réduite.',
        confirmLabel: 'Désactiver',
        confirmColor: AppColors.warning,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).setPinEnabled(false);
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Code PIN désactivé'),
              behavior: SnackBarBehavior.floating,
            ));
          }
        },
      ),
    );
  }

  // ─── Bottom sheet : Thème ─────────────────────────────────────────────────────
  void _showThemePicker(BuildContext ctx, WidgetRef ref, ThemeMode current) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: ctx.cl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: ctx.cl.borderS, borderRadius: BorderRadius.circular(2))),
          Text('Choisir le thème',
              style: TextStyle(
                  color: ctx.cl.textP,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _ThemeOption(
            icon: Icons.dark_mode_rounded, label: 'Sombre',
            selected: current == ThemeMode.dark,
            onTap: () {
              ref.read(settingsProvider.notifier).setTheme(ThemeMode.dark);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            icon: Icons.light_mode_rounded, label: 'Clair',
            selected: current == ThemeMode.light,
            onTap: () {
              ref.read(settingsProvider.notifier).setTheme(ThemeMode.light);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            icon: Icons.brightness_auto_rounded, label: 'Système',
            selected: current == ThemeMode.system,
            onTap: () {
              ref.read(settingsProvider.notifier).setTheme(ThemeMode.system);
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }

  // ─── Bottom sheet : Langue ────────────────────────────────────────────────────
  void _showLangPicker(BuildContext ctx, WidgetRef ref, String current) {
    showModalBottomSheet(
      context: ctx, backgroundColor: ctx.cl.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: ctx.cl.borderS, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text('Choisir la langue', style: TextStyle(
            color: ctx.cl.textP, fontSize: 16, fontWeight: FontWeight.w600))),
        _LangOption(flag: '🇫🇷', label: 'Français', code: 'fr', selected: current == 'fr',
          onTap: () { ref.read(settingsProvider.notifier).setLang('fr'); Navigator.pop(ctx); }),
        _LangOptionSoon(flag: '🇬🇧', label: 'English'),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ─── Bottom sheet : Vider le cache ────────────────────────────────────────────
  void _showClearCacheSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        icon: Icons.storage_rounded,
        iconColor: context.cl.textS,
        title: 'Vider le cache ?',
        body: 'Les données temporaires seront supprimées.\nTes paramètres et ta session seront conservés.',
        confirmLabel: 'Vider le cache',
        confirmColor: AppColors.primary,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).clearCache();
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Cache vidé ✅'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ));
          }
        },
      ),
    );
  }

  // ─── Bottom sheet : Sessions actives ──────────────────────────────────────────
  void _showSessionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.devices_rounded, color: AppColors.info, size: 22)),
            const SizedBox(width: 14),
            Text('Sessions actives', style: TextStyle(
              color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.25))),
            child: Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phone_android_rounded, color: AppColors.success, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Android · Cet appareil', style: TextStyle(
                  color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Connecté maintenant', style: TextStyle(
                  color: context.cl.textM, fontSize: 11)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
                child: const Text('Actif', style: TextStyle(
                  color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            'Pour sécuriser ton compte, déconnecte-toi si tu reconnais une session suspecte.',
            style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cl.textP,
                side: BorderSide(color: context.cl.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Fermer'),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Bottom sheet : À propos ──────────────────────────────────────────────────
  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20, offset: const Offset(0, 8))]),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 38),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          RichText(text: TextSpan(
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: 'Prono', style: TextStyle(color: context.cl.textP)),
              const TextSpan(text: 'Win', style: TextStyle(color: AppColors.primaryLight)),
            ],
          )),
          const SizedBox(height: 6),
          Text('Version 1.0.0', style: TextStyle(color: context.cl.textS, fontSize: 13)),
          const SizedBox(height: 4),
          Text('© 2026 PronoWin. Tous droits réservés.',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _AboutChip(icon: Icons.sports_soccer_rounded, label: 'Pronostics', color: AppColors.success),
            const SizedBox(width: 8),
            _AboutChip(icon: Icons.workspace_premium_rounded, label: 'Premium', color: AppColors.warning),
            const SizedBox(width: 8),
            _AboutChip(icon: Icons.people_rounded, label: 'Parrainage', color: const Color(0xFFA78BFA)),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cl.textP,
                side: BorderSide(color: context.cl.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Fermer'),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Bottom sheet : Supprimer le compte ───────────────────────────────────────
  void _showDeleteAccountSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteAccountSheet(ref: ref),
    );
  }
}

// ─── _DeleteAccountSheet ──────────────────────────────────────────────────────
class _DeleteAccountSheet extends StatefulWidget {
  final WidgetRef ref;
  const _DeleteAccountSheet({required this.ref});
  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String _input = '';

  bool get _confirmed => _input.trim().toUpperCase() == 'SUPPRIMER';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),

      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3), width: 1.5)),
        child: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 36)),
      const SizedBox(height: 16),

      Text('Supprimer le compte', style: TextStyle(
        color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        'Cette action est irréversible. Toutes tes données, ton historique et ton abonnement seront définitivement supprimés.',
        style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 20),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _DeleteWarning('Ton abonnement Premium sera annulé'),
          const SizedBox(height: 6),
          _DeleteWarning('Tes gains de parrainage seront perdus'),
          const SizedBox(height: 6),
          _DeleteWarning('Ton historique sera effacé définitivement'),
        ]),
      ),
      const SizedBox(height: 20),

      Align(
        alignment: Alignment.centerLeft,
        child: Text('Tapez SUPPRIMER pour confirmer',
          style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      TextField(
        controller: _ctrl,
        onChanged: (v) => setState(() => _input = v),
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600, letterSpacing: 1),
        decoration: InputDecoration(
          hintText: 'SUPPRIMER',
          hintStyle: TextStyle(color: context.cl.textM, letterSpacing: 1),
          filled: true,
          fillColor: context.cl.surfaceD,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.cl.borderS)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _confirmed ? AppColors.error.withValues(alpha: 0.5) : context.cl.borderS,
              width: _confirmed ? 1.5 : 0.5)),
        ),
      ),
      const SizedBox(height: 20),

      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cl.textP,
            side: BorderSide(color: context.cl.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Annuler'),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: (_confirmed && !_loading) ? _deleteAccount : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.error.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ]),
  );

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    HapticFeedback.heavyImpact();
    try {
      await widget.ref.read(authProvider.notifier).deleteAccount();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}

class _DeleteWarning extends StatelessWidget {
  final String text;
  const _DeleteWarning(this.text);
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.close_rounded, color: AppColors.error, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
        color: context.cl.textS, fontSize: 12, height: 1.4))),
    ],
  );
}

// ─── _ConfirmSheet ────────────────────────────────────────────────────────────
class _ConfirmSheet extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title, body, confirmLabel;
  final Color confirmColor;
  final Future<void> Function() onConfirm;
  const _ConfirmSheet({
    required this.icon, required this.iconColor,
    required this.title, required this.body,
    required this.confirmLabel, required this.confirmColor,
    required this.onConfirm,
  });
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}
class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _loading = false;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: widget.iconColor.withValues(alpha: 0.12),
          shape: BoxShape.circle),
        child: Icon(widget.icon, color: widget.iconColor, size: 32)),
      const SizedBox(height: 16),
      Text(widget.title, style: TextStyle(
        color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(widget.body, style: TextStyle(
        color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cl.textP,
            side: BorderSide(color: context.cl.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Annuler'),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: _loading ? null : () async {
            setState(() => _loading = true);
            await widget.onConfirm();
            if (mounted) setState(() => _loading = false);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(widget.confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ]),
  );
}

// ─── _ThemeOption ─────────────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.1) : context.cl.surfaceD,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? AppColors.primary.withValues(alpha: 0.4) : context.cl.border,
            width: selected ? 1 : 0.5)),
      child: Row(children: [
        Icon(icon, color: selected ? AppColors.primary : context.cl.textS, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(
            color: selected ? AppColors.primary : context.cl.textP,
            fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
        if (selected) const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
      ]),
    ),
  );
}

// ─── _AboutChip ───────────────────────────────────────────────────────────────
class _AboutChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _AboutChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ─── Widgets ─────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 3, height: 14,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title.toUpperCase(), style: TextStyle(
        color: context.cl.textS, fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 1)),
    ]),
  );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(children: children),
  );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String title; final String? subtitle;
  final bool value; final ValueChanged<bool>? onChanged;
  const _SwitchTile({required this.icon, required this.iconColor,
    required this.title, this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500)),
        if (subtitle != null) AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child)),
          child: Text(subtitle!, key: ValueKey(subtitle),
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ),
      ])),
      Switch(
        value: value,
        onChanged: onChanged == null ? null : (v) {
          HapticFeedback.selectionClick();
          onChanged!(v);
        },
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return context.cl.textM;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return context.cl.borderS.withValues(alpha: 0.4);
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return context.cl.borderS;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ]),
  );
}

class _NavTile extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String title; final String? subtitle, trailing;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.iconColor,
    required this.title, this.subtitle, this.trailing, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ])),
        if (trailing != null) Text(trailing!, style: TextStyle(color: context.cl.textS, fontSize: 13)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: context.cl.textM, size: 18),
      ]),
    ),
  );
}

class _DangerNavTile extends StatelessWidget {
  final IconData icon;
  final String title; final String? subtitle;
  final VoidCallback onTap;
  const _DangerNavTile({required this.icon, required this.title,
    this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.error, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Supprimer le compte', style: TextStyle(
            color: AppColors.error, fontSize: 14, fontWeight: FontWeight.w500)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(
            color: AppColors.error.withValues(alpha: 0.6), fontSize: 11)),
        ])),
        Icon(Icons.chevron_right_rounded, color: AppColors.error.withValues(alpha: 0.5), size: 18),
      ]),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Divider(color: context.cl.border, height: 1, indent: 64, endIndent: 16);
}

class _LangOption extends StatelessWidget {
  final String flag, label, code; final bool selected; final VoidCallback onTap;
  const _LangOption({required this.flag, required this.label, required this.code, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Text(flag, style: const TextStyle(fontSize: 24)),
    title: Text(label, style: TextStyle(color: selected ? AppColors.primary : context.cl.textP)),
    trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20) : null,
    onTap: onTap,
  );
}

class _LangOptionSoon extends StatelessWidget {
  final String flag, label;
  const _LangOptionSoon({required this.flag, required this.label});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Text(flag, style: const TextStyle(fontSize: 24)),
    title: Text(label, style: TextStyle(color: context.cl.textM)),
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3), width: 0.5),
      ),
      child: const Text('Bientôt', style: TextStyle(
        color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.w600)),
    ),
    enabled: false,
  );
}
