import 'package:pronowin/l10n/app_strings.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../../../core/config/contact_support.dart';
import '../../../../shared/widgets/logo_marque.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../compte/presentation/pages/compte_page.dart' show rafraichirDonneesCompte;
import '../providers/settings_provider.dart';
import '../providers/security_provider.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../core/config/pages_legales.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../../../shared/utils/messages.dart';

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/compte';


/// L'année du copyright était figée à 2026 dans deux textes distincts.
final _copyrightYear = DateTime.now().year;

class ParametresPage extends ConsumerWidget {
  const ParametresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings     = ref.watch(settingsProvider);
    final bioAvailable = ref.watch(bioAvailableProvider);
    // La version était écrite en dur à trois endroits (ligne « À propos »,
    // pied de page, feuille À propos) : trois vérités à maintenir en phase.
    final appVersion   = ref.watch(appVersionProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => retourOuAller(context, repli: _repli),
        ),
        title:  Text(tr(context, "Paramètres")),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [

          // ─── APPARENCE ────────────────────────────────────────────────
          _SectionHeader(tr(context, "Apparence"))
            .animate().fadeIn(duration: 300.ms, delay: 50.ms),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.dark_mode_rounded, iconColor: const Color(0xFF818CF8),
              title: tr(context, "Thème"), trailing: settings.themeName,
              onTap: () => _showThemePicker(context, ref, settings.themeMode),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.language_rounded, iconColor: context.cl.info,
              title: tr(context, "Langue"), trailing: settings.langName,
              onTap: () => _showLangPicker(context, ref, settings.lang),
            ),
          ]).animate(delay: 80.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── NOTIFICATIONS ────────────────────────────────────────────
          _SectionHeader(tr(context, "Notifications"))
            .animate().fadeIn(duration: 300.ms, delay: 100.ms),
          _SettingsCard(children: [
            _SwitchTile(
              icon: Icons.sports_soccer_rounded, iconColor: context.cl.info,
              title: tr(context, "Alertes matchs"), subtitle: tr(context, "1h avant chaque pronostic"),
              value: settings.notifMatch,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('match'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.local_offer_rounded, iconColor: AppColors.primary,
              title: tr(context, "Offres & Promotions"), subtitle: tr(context, "Codes promo et offres spéciales"),
              value: settings.notifPromo,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('promo'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.people_rounded, iconColor: AppColors.primary,
              title: tr(context, "Parrainage"), subtitle: tr(context, "Quand un filleul s'abonne"),
              value: settings.notifReferral,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('referral'),
            ),
            const _Divider(),
            _SwitchTile(
              icon: Icons.workspace_premium_rounded, iconColor: AppColors.primary,
              title: tr(context, "Abonnement Premium"), subtitle: tr(context, "Expiration et renouvellement"),
              value: settings.notifPremium,
              onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotif('premium'),
            ),
          ]).animate(delay: 130.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── SÉCURITÉ ─────────────────────────────────────────────────
          _SectionHeader(tr(context, "Sécurité"))
            .animate().fadeIn(duration: 300.ms, delay: 150.ms),
          _SettingsCard(children: [

            // Code PIN
            _SwitchTile(
              icon: Icons.pin_rounded, iconColor: context.cl.success,
              title: tr(context, "Code PIN"),
              subtitle: settings.pinEnabled
                ? tr(context, "Actif — l'app se verrouille à la fermeture")
                : tr(context, "Protéger l'app avec un code à 4 chiffres"),
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
                icon: Icons.fingerprint_rounded, iconColor: context.cl.success,
                title: tr(context, "Biométrie"),
                subtitle: available
                  ? (settings.bioEnabled
                      ? tr(context, "Actif — déverrouillage par empreinte")
                      : tr(context, "Déverrouiller avec empreinte / Face ID"))
                  : tr(context, "Non disponible sur cet appareil"),
                value: settings.bioEnabled && available,
                unavailable: !available,
                onChanged: available ? (v) async {
                  if (v) {
                    final auth = LocalAuthentication();
                    try {
                      final ok = await auth.authenticate(
                        localizedReason: tr(context, "Confirmez pour activer la biométrie"),
                        options: const AuthenticationOptions(
                          biometricOnly: false, stickyAuth: true),
                      );
                      if (ok) {
                        await ref.read(settingsProvider.notifier).setBioEnabled(true);
                        if (context.mounted) {
                          afficherMessage(context, tr(context, "Biométrie activée"), type: TypeMessage.succes);
                        }
                      }
                    } catch (e) {
                      debugPrint('[Bio] Activation refusée : $e');
                      if (context.mounted) {
                        afficherMessage(context, messageErreurBio(e), type: TypeMessage.erreur);
                      }
                    }
                  } else {
                    await ref.read(settingsProvider.notifier).setBioEnabled(false);
                  }
                } : null,
              ),
              loading: () => _SwitchTile(
                icon: Icons.fingerprint_rounded, iconColor: context.cl.textM,
                title: tr(context, "Biométrie"), subtitle: tr(context, "Vérification en cours..."),
                value: false, onChanged: null,
              ),
              error: (_, _) => _SwitchTile(
                icon: Icons.fingerprint_rounded, iconColor: context.cl.textM,
                title: tr(context, "Biométrie"), subtitle: tr(context, "Non disponible sur cet appareil"),
                value: false, onChanged: null, unavailable: true,
              ),
            ),
            const _Divider(),

            // Changer le PIN (si activé)
            if (settings.pinEnabled) ...[
              _NavTile(
                icon: Icons.edit_rounded, iconColor: context.cl.info,
                title: tr(context, "Changer le code PIN"),
                subtitle: tr(context, "Modifier ton code de sécurité"),
                onTap: () => context.push('/parametres/pin'),
              ),
              const _Divider(),
            ],

            _NavTile(
              icon: Icons.devices_rounded, iconColor: context.cl.info,
              title: tr(context, "Sessions actives"),
              subtitle: tr(context, "Voir et gérer tes connexions"),
              onTap: () => _showSessionsSheet(context),
            ),
          ]).animate(delay: 180.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── COMPTE ───────────────────────────────────────────────────
          _SectionHeader(tr(context, "Mon compte"))
            .animate().fadeIn(duration: 300.ms, delay: 200.ms),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.edit_rounded, iconColor: AppColors.primary,
              title: tr(context, "Modifier le profil"), subtitle: tr(context, "Pseudo, email, avatar"),
              onTap: () => context.push('/compte/edit'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.block_rounded, iconColor: context.cl.error,
              title: tr(context, "Membres bloqués"), subtitle: tr(context, "Ceux dont tu ne vois plus les commentaires"),
              onTap: () => context.push('/parametres/bloques'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.storage_rounded, iconColor: context.cl.textS,
              title: tr(context, "Vider le cache"), subtitle: tr(context, "Libérer l'espace de stockage"),
              onTap: () => _showClearCacheSheet(context, ref),
            ),
          ]).animate(delay: 230.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── LÉGAL ────────────────────────────────────────────────────
          _SectionHeader(tr(context, "Informations légales"))
            .animate().fadeIn(duration: 300.ms, delay: 250.ms),
          _SettingsCard(children: [
            // Les trois textes publics vivent sur le site, et l'application
            // y renvoie — comme les mentions légales le faisaient déjà seules.
            // Ce sont les documents qu'on cite, qu'un examinateur ouvre, et
            // qu'un utilisateur doit pouvoir lire sans avoir l'application
            // sous la main. Les recopier ici créerait un second original.
            //
            // « Jeu responsable » reste embarqué : le site n'en a pas de page,
            // et ces ressources doivent rester atteignables même hors ligne.
            _NavTile(
              icon: Icons.description_rounded, iconColor: context.cl.textM,
              title: tr(context, "Conditions d'utilisation"),
              onTap: () => PagesLegales.ouvrir(
                context,
                PagesLegales.cgu(estStore: ref.read(isStoreBuildProvider)),
                titre: PagesLegales.titreCgu),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.privacy_tip_rounded, iconColor: context.cl.textM,
              title: tr(context, "Politique de confidentialité"),
              onTap: () => PagesLegales.ouvrir(
                context, PagesLegales.confidentialite,
                titre: PagesLegales.titreConfidentialite),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.casino_rounded, iconColor: context.cl.warning,
              title: tr(context, "Jeu responsable"), subtitle: tr(context, "Ressources et aide"),
              onTap: () => context.push('/parametres/jeu-responsable'),
            ),
            const _Divider(),
            // Les mentions légales vivent sur le site, pas ici — c'est une
            // obligation du site, et elles portent l'identité de l'éditeur.
            // La dupliquer dans l'application créerait un second endroit où ce
            // nom et cette adresse devraient rester à jour, et l'un des deux
            // finirait par mentir. On y renvoie, on ne la recopie pas.
            _NavTile(
              icon: Icons.gavel_rounded, iconColor: context.cl.textM,
              title: tr(context, "Mentions légales"), subtitle: tr(context, "Éditeur et hébergeur"),
              onTap: () => PagesLegales.ouvrir(
                context, PagesLegales.mentionsLegales,
                titre: tr(context, "Mentions légales")),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.info_outline_rounded, iconColor: context.cl.textM,
              title: tr(context, "À propos"), trailing: appVersion,
              onTap: () => _showAboutSheet(context, appVersion),
            ),
          ]).animate(delay: 280.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),

          // ─── ZONE DE DANGER ───────────────────────────────────────────
          // La suppression de compte était entièrement codée (feuille de
          // confirmation, provider, endpoint) mais n'apparaissait nulle part
          // dans l'app. Apple (5.1.1(v)) et Google Play l'exigent dès lors
          // qu'on permet la création d'un compte.
          _SectionHeader(tr(context, "Zone de danger"))
            .animate().fadeIn(duration: 300.ms, delay: 300.ms),
          _SettingsCard(children: [
            _DangerNavTile(
              icon: Icons.delete_forever_rounded,
              // Disait « Effacer définitivement tes données ». Le serveur
              // anonymise : il vide les champs personnels et garde la ligne,
              // l'historique et la bankroll. Promettre un effacement définitif
              // sur le bouton qui ne l'exécute pas est la pire place pour
              // cette inexactitude — c'est celle que l'on cite pour exercer un
              // droit à l'effacement.
              subtitle: tr(context, "Fermer ton compte et effacer tes informations"),
              onTap: () => _showDeleteAccountSheet(context, ref),
            ),
          ]).animate(delay: 320.ms).fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 12),

          Center(
            child: Text(
              tr(context, "© {arg0} PronoWin. Tous droits réservés.", [_copyrightYear]),
              style: TextStyle(color: context.cl.textM, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ).animate(delay: 360.ms).fadeIn(duration: 400.ms),
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
        iconColor: context.cl.warning,
        title: tr(context, "Désactiver le PIN ?"),
        body: tr(context, "L'application ne sera plus protégée par un code PIN.\nTa sécurité sera réduite."),
        confirmLabel: tr(context, "Désactiver"),
        confirmColor: context.cl.warning,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).setPinEnabled(false);
          if (context.mounted) {
            Navigator.pop(context);
            afficherMessage(context, tr(context, "Code PIN désactivé"));
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
          Text(tr(ctx, "Choisir le thème"),
              style: TextStyle(
                  color: ctx.cl.textP,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _ThemeOption(
            icon: Icons.dark_mode_rounded, label: tr(ctx, "Sombre"),
            selected: current == ThemeMode.dark,
            onTap: () {
              ref.read(settingsProvider.notifier).setTheme(ThemeMode.dark);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            icon: Icons.light_mode_rounded, label: tr(ctx, "Clair"),
            selected: current == ThemeMode.light,
            onTap: () {
              ref.read(settingsProvider.notifier).setTheme(ThemeMode.light);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            icon: Icons.brightness_auto_rounded, label: tr(ctx, "Système"),
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
          child: Text(tr(ctx, "Choisir la langue"), style: TextStyle(
            color: ctx.cl.textP, fontSize: 16, fontWeight: FontWeight.w600))),
        _LangOption(flag: '🇫🇷', label: tr(ctx, "Français"), code: 'fr', selected: current == 'fr',
          onTap: () { ref.read(settingsProvider.notifier).setLang('fr'); Navigator.pop(ctx); }),
        _LangOption(flag: '🇬🇧', label: 'English', code: 'en', selected: current == 'en',
          onTap: () { ref.read(settingsProvider.notifier).setLang('en'); Navigator.pop(ctx); }),
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
        title: tr(context, "Vider le cache ?"),
        body: tr(context, "Les données temporaires seront supprimées.\nTes paramètres et ta session seront conservés."),
        confirmLabel: tr(context, "Vider le cache"),
        confirmColor: AppColors.primary,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).clearCache();
          if (context.mounted) {
            Navigator.pop(context);
            afficherMessage(context, tr(context, "Cache vidé"), type: TypeMessage.succes);
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
                color: context.cl.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.devices_rounded, color: context.cl.info, size: 22)),
            const SizedBox(width: 14),
            Text(tr(context, "Sessions actives"), style: TextStyle(
              color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cl.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.success.withValues(alpha: 0.25))),
            child: Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  color: context.cl.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(Platform.isIOS ? Icons.phone_iphone_rounded : Icons.phone_android_rounded, color: context.cl.success, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, "{arg0} · Cet appareil", [Platform.isIOS ? 'iPhone' : 'Android']), style: TextStyle(
                  color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(tr(context, "Connecté maintenant"), style: TextStyle(
                  color: context.cl.textM, fontSize: 11)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.cl.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
                child:  Text(tr(context, "Actif"), style: TextStyle(
                  color: context.cl.success, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            tr(context, "Pour sécuriser ton compte, déconnecte-toi si tu reconnais une session suspecte."),
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
              child:  Text(tr(context, "Fermer")),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Bottom sheet : À propos ──────────────────────────────────────────────────
  void _showAboutSheet(BuildContext context, String version) {
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
                colors: AppColors.degradeMarque,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20, offset: const Offset(0, 8))]),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 38),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          const LogotypePronoWin(taille: 26),
          const SizedBox(height: 6),
          Text(tr(context, "Version {arg0}", [version.replaceFirst('v', '')]),
            style: TextStyle(color: context.cl.textS, fontSize: 13)),
          const SizedBox(height: 4),
          Text(tr(context, "© {arg0} PronoWin. Tous droits réservés.", [_copyrightYear]),
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            _AboutChip(
              icon: Icons.star_rounded, label: tr(context, "Noter l'application"), color: context.cl.warning,
              onTap: () => InAppReview.instance.openStoreListing().catchError((_) {}),
            ),
            _AboutChip(
              icon: Icons.mail_outline_rounded, label: tr(context, "Nous contacter"), color: context.cl.info,
              onTap: () => ContactSupport.ouvrirEmail(),
            ),
            _AboutChip(
              marque: Marque.telegram, label: 'Telegram', color: Marque.telegram.couleur,
              onTap: () => ContactSupport.ouvrirTelegram(),
            ),
            _AboutChip(
              marque: Marque.whatsapp, label: 'WhatsApp', color: Marque.whatsapp.couleur,
              onTap: () => ContactSupport.ouvrirWhatsapp(),
            ),
            _AboutChip(
              icon: Icons.facebook_rounded, label: 'Facebook', color: const Color(0xFF1877F2),
              onTap: () => ContactSupport.ouvrirFacebook(),
            ),
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
              child:  Text(tr(context, "Fermer")),
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
          color: context.cl.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: context.cl.error.withValues(alpha: 0.3), width: 1.5)),
        child: Icon(Icons.delete_forever_rounded, color: context.cl.error, size: 36)),
      const SizedBox(height: 16),

      Text(tr(context, "Supprimer le compte"), style: TextStyle(
        color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      // Annonçait « Toutes tes données, ton historique et ton abonnement
      // seront définitivement supprimés ». Aucune des trois affirmations
      // n'était exacte : le serveur anonymise le compte — il vide les champs
      // personnels, met `isActive` à faux et conserve la ligne, l'historique
      // et la bankroll —, et il ne touche jamais à l'abonnement.
      Text(
        tr(context, "Cette action est irréversible. Tes informations personnelles sont effacées et tu perds l'accès à ton compte."),
        style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 20),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cl.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cl.error.withValues(alpha: 0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // « Ton abonnement Premium sera annulé » était faux, et
          // dangereusement : la suppression ne touche ni `subscriptionPlan`
          // ni `subscriptionExpiresAt`, et aucune résiliation n'est appelée
          // nulle part. En facturation Google Play, seul Google peut résilier.
          //
          // Quelqu'un qui supprime son compte pour cesser de payer continuait
          // donc d'être débité tous les mois, après avoir lu le contraire sur
          // l'écran qui le lui demandait. C'est l'avertissement qui devait le
          // protéger qui causait le prélèvement.
          //
          // Et la boutique est celle du téléphone : l'iPhone affichait « depuis
          // le Play Store » (vidéo du 3 octobre 2026).
          _DeleteWarning(!widget.ref.read(isStoreBuildProvider)
              ? tr(context, "Ton abonnement n'est ni résilié ni remboursé")
              : Platform.isIOS
                ? tr(context, "Ton abonnement n'est pas résilié : fais-le depuis l'App Store (Réglages, puis ton nom, puis Abonnements)")
                : tr(context, "Ton abonnement n'est pas résilié : fais-le depuis le Play Store")),
          const SizedBox(height: 6),
          _DeleteWarning(tr(context, "Tu perds l'accès à tes gains de parrainage")),
          const SizedBox(height: 6),
          // Anonymisé, pas effacé — c'est ce que fait `deleteAccount`. Une
          // information, pas une perte : la croix rouge la rangeait avec ce
          // qu'on perd (vidéo du 5 octobre 2026).
          _DeleteWarning(tr(context, "Ton historique est conservé sous forme anonyme"), neutre: true),
        ]),
      ),
      const SizedBox(height: 20),

      Align(
        alignment: Alignment.centerLeft,
        child: Text(tr(context, "Tape SUPPRIMER pour confirmer"),
          style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      TextField(
        controller: _ctrl,
        onChanged: (v) => setState(() => _input = v),
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600, letterSpacing: 1),
        // Pas d'indication « SUPPRIMER » dans le champ : en capitales grasses,
        // elle passait pour un texte déjà saisi, et le bouton restait grisé
        // sans qu'on comprenne pourquoi. La consigne est juste au-dessus.
        decoration: InputDecoration(
          filled: true,
          fillColor: context.cl.surfaceD,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.cl.borderS)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.cl.error, width: 1.5)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _confirmed ? context.cl.error.withValues(alpha: 0.5) : context.cl.borderS,
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
          child:  Text(tr(context, "Annuler")),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: (_confirmed && !_loading) ? _deleteAccount : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.fondErreur,
            foregroundColor: Colors.white,
            disabledBackgroundColor: context.cl.error.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            :  Text(tr(context, "Supprimer"), style: TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ]),
  );

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    HapticFeedback.heavyImpact();
    try {
      await widget.ref.read(authProvider.notifier).deleteAccount();
      // Comme à la déconnexion : ce qui a été lu pour le compte supprimé
      // repart, et l'état de connexion avec. La déconnexion le faisait, pas la
      // suppression — la connexion suivante partait d'un « connecté » périmé.
      rafraichirDonneesCompte(widget.ref);
      widget.ref.invalidate(isLoggedInProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        afficherMessage(context, tr(context, "Erreur : {arg0}", [e]), type: TypeMessage.erreur);
      }
    }
  }
}

class _DeleteWarning extends StatelessWidget {
  final String text;
  /// Une information (ce qui est conservé), et non une perte.
  final bool neutre;
  const _DeleteWarning(this.text, {this.neutre = false});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      neutre
        ? Icon(Icons.info_outline_rounded, color: context.cl.textM, size: 14)
        : Icon(Icons.close_rounded, color: context.cl.error, size: 14),
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
          child:  Text(tr(context, "Annuler")),
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
            color: selected ? context.cl.accent : context.cl.textP,
            fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
        if (selected) const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
      ]),
    ),
  );
}

// ─── _AboutChip ───────────────────────────────────────────────────────────────
class _AboutChip extends StatelessWidget {
  final IconData? icon;

  /// Le vrai logo du réseau, à la place d'une icône générique.
  final Marque? marque;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _AboutChip({this.icon, this.marque, required this.label, required this.color, this.onTap})
      : assert(icon != null || marque != null);
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (marque != null) LogoMarque(marque!, taille: 14) else Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
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
  /// Rend l'interrupteur non pertinent (fonction indisponible sur l'appareil) :
  /// on affiche un tiret plutôt qu'un switch mort, qu'on confondait avec un
  /// simple « éteint ».
  final bool unavailable;
  const _SwitchTile({required this.icon, required this.iconColor,
    required this.title, this.subtitle, required this.value,
    required this.onChanged, this.unavailable = false});

  @override
  Widget build(BuildContext context) {
    // Toute la ligne est cliquable, comme sur _NavTile : les deux se
    // ressemblent trait pour trait, mais seul l'interrupteur répondait ici —
    // une cible de ~50×30 px sur une ligne large de 350.
    final row = _buildRow(context);
    if (onChanged == null) return row;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged!(!value);
      },
      borderRadius: BorderRadius.circular(16),
      child: row,
    );
  }

  Widget _buildRow(BuildContext context) => Padding(
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
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
        ),
      ])),
      if (unavailable)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(Icons.do_not_disturb_on_outlined,
            color: context.cl.textM.withValues(alpha: 0.5), size: 20))
      else
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
          if (subtitle != null) Text(subtitle!, style: TextStyle(color: context.cl.textM, fontSize: 12)),
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
  final String? subtitle;
  final VoidCallback onTap;
  // Le paramètre `title` a été retiré : il était requis mais jamais lu, le
  // libellé étant écrit en dur plus bas.
  const _DangerNavTile({required this.icon, this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(
            color: context.cl.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: context.cl.error, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
           Text(tr(context, "Supprimer le compte"), style: TextStyle(
            color: context.cl.error, fontSize: 14, fontWeight: FontWeight.w500)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(
            color: context.cl.error.withValues(alpha: 0.6), fontSize: 12)),
        ])),
        Icon(Icons.chevron_right_rounded, color: context.cl.error.withValues(alpha: 0.5), size: 18),
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
    title: Text(label, style: TextStyle(color: selected ? context.cl.accent : context.cl.textP)),
    trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20) : null,
    onTap: onTap,
  );
}
