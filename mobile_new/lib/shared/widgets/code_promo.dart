import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/bookmaker_affiliation.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../utils/messages.dart';

/// Le code promo du partenaire bookmaker (7 novembre 2026), affiché sur toutes
/// les versions de l'application — décision du titulaire du compte, après
/// avertissement sur les règles de l'App Store et de Google Play.
///
/// Trois emplacements, comme Chance 8 : une carte sur l'accueil, un bandeau
/// dans la liste des pronostics et la fiche des matchs, et une page dédiée.
/// Le code, le nom et le lien viennent de `/config` : ils se changent depuis
/// l'administration, sans republier. Code vide : rien ne s'affiche.
///
/// Seuls le code et le lien du partenaire sont lus ici. Les autres invitations
/// à parier (cotes du partenaire, bouton de mise) gardent leurs propres règles
/// par canal.
class PromoPartenaire {
  final String code, nom, lien;
  const PromoPartenaire({required this.code, required this.nom, required this.lien});

  /// « 1xBet », ou « notre partenaire » si le serveur ne le nomme pas.
  String nomAffiche(BuildContext context) => nom.isEmpty ? tr(context, "notre partenaire") : nom;
}

/// Lu une fois par session. Le serveur injoignable : ce que l'APK direct a
/// déjà reçu au démarrage, sinon rien.
final promoPartenaireProvider = FutureProvider<PromoPartenaire?>((ref) async {
  PromoPartenaire? depuisAffiliation() => BookmakerAffiliation.codePromoDisponible
      ? PromoPartenaire(code: BookmakerAffiliation.codePromo.trim(),
          nom: BookmakerAffiliation.nom, lien: BookmakerAffiliation.lien)
      : null;
  try {
    final r = await ref.read(dioProvider).get<Map<String, dynamic>>('/config');
    final d = r.data ?? const {};
    final code = (d['promoCode'] as String?)?.trim() ?? '';
    if (code.isEmpty) return null;
    final lien = (d['affiliateUrl'] as String?)?.trim() ?? '';
    return PromoPartenaire(
      code: code,
      nom: (d['affiliateName'] as String?)?.trim() ?? '',
      lien: lien.startsWith('http') ? lien : '',
    );
  } catch (_) {
    return depuisAffiliation();
  }
});

/// Copie le code et le dit.
Future<void> copierCodePromo(BuildContext context, String code) async {
  HapticFeedback.lightImpact();
  final message = tr(context, "Code {arg0} copié", [code]);
  await Clipboard.setData(ClipboardData(text: code));
  if (context.mounted) afficherMessage(context, message, type: TypeMessage.succes, duree: const Duration(seconds: 2));
}

/// L'orange plein revenait à l'action principale de l'écran (« Voir
/// l'analyse », l'onglet actif) : le code promo, lui aussi tout orange, lui
/// disputait le regard (revue de l'interface, 9 novembre 2026). Il garde
/// l'accent sur un liseré et son icône, sur la surface des autres cartes.
BoxDecoration _decorPromo(BuildContext context, double rayon) => BoxDecoration(
  color: context.cl.surface,
  borderRadius: BorderRadius.circular(rayon),
  border: Border.all(color: AppColors.primary.withValues(alpha: 0.45), width: 1),
);

/// L'orange plein reste sur la page du code, dont c'est le sujet.
const _degrade = [Color(0xFFFF7A1A), Color(0xFFE5450A)];

Widget _iconePromo(BuildContext context, {double taille = 36}) => Container(
  width: taille, height: taille,
  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
  child: Icon(Icons.card_giftcard_rounded, color: context.cl.accent, size: taille * 0.55),
);

/// Le bandeau, pour les listes : une ligne, le code, « Copier ». Un appui
/// ailleurs ouvre la page du code.
class BandeauCodePromo extends ConsumerWidget {
  final EdgeInsets marge;
  const BandeauCodePromo({super.key, this.marge = const EdgeInsets.only(bottom: 12)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promo = ref.watch(promoPartenaireProvider).valueOrNull;
    if (promo == null) return const SizedBox.shrink();
    final nom = promo.nomAffiche(context);
    return Padding(
      padding: marge,
      child: Semantics(
        button: true,
        label: tr(context, "Code promo {arg0} : {arg1}. Publicité.", [nom, promo.code]),
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('bandeau-code-promo'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/code-promo'),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: _decorPromo(context, 14),
              child: Row(children: [
                _iconePromo(context, taille: 34),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tr(context, "Bonus {arg0} avec notre code promo", [nom]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(promo.code, style: TextStyle(color: context.cl.textP, fontSize: 16,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  Text(BookmakerAffiliation.mention,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.cl.textM, fontSize: 11)),
                ])),
                IconButton(
                  tooltip: tr(context, "Copier le code"),
                  onPressed: () => copierCodePromo(context, promo.code),
                  icon: Icon(Icons.copy_rounded, color: context.cl.accent, size: 20),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// La carte de l'accueil : un peu plus grande que le bandeau, même contenu.
class CarteCodePromo extends ConsumerWidget {
  const CarteCodePromo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promo = ref.watch(promoPartenaireProvider).valueOrNull;
    if (promo == null) return const SizedBox.shrink();
    final nom = promo.nomAffiche(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('carte-code-promo'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/code-promo'),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: _decorPromo(context, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _iconePromo(context, taille: 30),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(context, "Code promo {arg0}", [nom]).toUpperCase(),
                  style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceD,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.cl.border)),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(promo.code,
                    style: TextStyle(color: context.cl.textP, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3))),
                )),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => copierCodePromo(context, promo.code),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cl.accent,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(tr(context, "Copier")),
                ),
              ]),
              const SizedBox(height: 10),
              Text(tr(context, "À saisir lors de ton inscription sur {arg0}.", [nom]),
                style: TextStyle(color: context.cl.textS, fontSize: 13)),
              const SizedBox(height: 4),
              Text(BookmakerAffiliation.mention,
                style: TextStyle(color: context.cl.textM, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// La page du code : le code en grand, « Copier », comment s'en servir,
/// « Ouvrir » le partenaire, et le jeu responsable.
class PageCodePromo extends ConsumerWidget {
  const PageCodePromo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cl = context.cl;
    final etat = ref.watch(promoPartenaireProvider);
    final promo = etat.valueOrNull;
    return Scaffold(
      backgroundColor: cl.bg,
      appBar: AppBar(
        backgroundColor: cl.bg,
        title: Text(promo == null ? tr(context, "Code promo") : tr(context, "Code promo {arg0}", [promo.nomAffiche(context)])),
        centerTitle: true,
      ),
      body: promo == null
          ? Center(child: etat.isLoading
              ? const CircularProgressIndicator(color: AppColors.primary)
              : Padding(padding: const EdgeInsets.all(32), child: Text(
                  tr(context, "Aucun code promo pour le moment."),
                  textAlign: TextAlign.center, style: TextStyle(color: cl.textS))))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: _degrade, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 34),
                  const SizedBox(height: 8),
                  Text(tr(context, "CODE PROMO EXCLUSIF"),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: FittedBox(fit: BoxFit.scaleDown, child: SelectableText(promo.code,
                      key: const Key('code-promo-texte'),
                      style: const TextStyle(color: Color(0xFF1A1D26), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4))),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('copier-code-promo'),
                      onPressed: () => copierCodePromo(context, promo.code),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1D26), foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(tr(context, "Copier le code")),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _Etape(numero: 1, texte: tr(context, "Ouvre {arg0} et crée ton compte.", [promo.nomAffiche(context)])),
              _Etape(numero: 2, texte: tr(context, "Saisis le code {arg0} dans le champ « code promo ».", [promo.code])),
              _Etape(numero: 3, texte: tr(context, "Le bonus de bienvenue s'applique selon les conditions de {arg0}.", [promo.nomAffiche(context)])),
              if (promo.lien.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('ouvrir-partenaire'),
                    onPressed: () => launchUrl(Uri.parse(promo.lien), mode: LaunchMode.externalApplication)
                        .catchError((_) => false),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(tr(context, "Ouvrir {arg0}", [promo.nomAffiche(context)])),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cl.textP,
                      side: BorderSide(color: cl.border),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(BookmakerAffiliation.mention, textAlign: TextAlign.center,
                style: TextStyle(color: cl.textS, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(tr(context, "Les paris comportent des risques : endettement, dépendance. Ne mise que ce que tu peux te permettre de perdre."),
                textAlign: TextAlign.center, style: TextStyle(color: cl.textM, fontSize: 12, height: 1.4)),
              TextButton(
                onPressed: () => context.push('/parametres/jeu-responsable'),
                child: Text(tr(context, "Jeu responsable")),
              ),
            ]),
    );
  }
}

class _Etape extends StatelessWidget {
  final int numero;
  final String texte;
  const _Etape({required this.numero, required this.texte});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 26, height: 26, alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Text('$numero', style: TextStyle(color: context.cl.accent, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(texte, style: TextStyle(color: context.cl.textP, fontSize: 14, height: 1.35)),
      )),
    ]),
  );
}
