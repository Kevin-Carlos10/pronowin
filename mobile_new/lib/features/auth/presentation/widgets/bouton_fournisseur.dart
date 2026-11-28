import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';

/// Un chemin de connexion, dans une pile où tous se valent.
///
/// L'écran opposait auparavant un bouton plein (« Continuer » par e-mail) à un
/// bouton contour (Google) : le choix était donc fait pour l'utilisateur, et il
/// poussait vers le chemin le plus lent — celui qui exige d'attendre un code,
/// d'aller le chercher dans sa boîte, de le ressaisir — et le seul qui coûte un
/// envoi à PronoWin.
///
/// Tous les fournisseurs partagent la même forme et la même hauteur. C'est le
/// modèle des grandes apps sport (Sofascore, OneFootball) : on propose, on
/// n'oriente pas.
///
/// Depuis le 24 novembre 2026 (écran « Connexion ou inscription » montré par
/// l'utilisateur) : des rectangles arrondis au contour léger, le libellé en
/// capitales espacées, la marque à gauche. Seul Apple peut être plein
/// ([plein]) : ses règles de présentation proposent un bouton noir (ou blanc
/// sur fond sombre), jamais la couleur de l'app — aucun chemin ne prend
/// l'orange de la marque.
class BoutonFournisseur extends StatelessWidget {
  final String libelle;

  /// Marque du fournisseur, à sa gauche. `null` pour un chemin sans marque
  /// (l'e-mail), qui reçoit alors une icône neutre. Les icônes prennent la
  /// couleur du libellé.
  final Widget? logo;

  final VoidCallback? onPressed;

  /// Grise le bouton pendant qu'un autre chemin est en cours : deux
  /// authentifications simultanées produiraient deux sessions concurrentes.
  final bool desactive;

  /// Fond plein de la couleur du texte (noir en clair, blanc en sombre) :
  /// « Continuer avec Apple », selon les règles d'Apple.
  final bool plein;

  const BoutonFournisseur({
    super.key,
    required this.libelle,
    this.logo,
    this.onPressed,
    this.desactive = false,
    this.plein = false,
  });

  /// Rayon des coins, le même pour tous.
  static const rayon = 10.0;

  @override
  Widget build(BuildContext context) {
    final actif = !desactive && onPressed != null;
    final encre = plein ? context.cl.bg : context.cl.textP.withValues(alpha: 0.82);

    // Le libellé s'affiche en capitales ; le lecteur d'écran le lit tel
    // qu'il s'écrit, sans l'épeler.
    return Semantics(
      button: true,
      enabled: actif,
      label: libelle,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Opacity(
          opacity: actif ? 1 : 0.45,
          child: Material(
            color: plein ? context.cl.textP : Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rayon),
              side: plein
                  ? BorderSide.none
                  : BorderSide(color: context.cl.border, width: 1),
            ),
            child: InkWell(
              onTap: actif ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: IconTheme(
                  data: IconThemeData(color: plein ? context.cl.bg : context.cl.textP),
                  child: Row(children: [
                    SizedBox(width: 28, height: 28, child: Center(child: logo)),
                    // Le libellé reste centré sur toute la largeur du bouton,
                    // la marque flottant à gauche — c'est ce qui aligne
                    // visuellement les intitulés d'une pile où les logos n'ont
                    // pas la même largeur.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 28),
                        child: Text(
                          libelle.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: encre,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo Google officiel, en quatre couleurs.
///
/// `Icons.g_mobiledata_rounded` était employé jusqu'ici : un « G » monochrome
/// de la police Material, qui n'est pas la marque Google. Les conditions
/// d'usage du bouton Google exigent le logo officiel — et à l'œil, un G gris
/// ne se reconnaît pas comme un bouton Google.
class LogoGoogle extends StatelessWidget {
  const LogoGoogle({super.key});

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17"/>
  <path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46"/>
  <path fill="#FBBC05" d="M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88z"/>
  <path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07"/>
</svg>''';

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, width: 24, height: 24);
}

/// Le logo Apple, pour « Continuer avec Apple ». Les règles d'Apple veulent
/// le logo seul, monochrome, de la couleur du texte du bouton : il prend
/// celle que le bouton lui donne.
class LogoApple extends StatelessWidget {
  const LogoApple({super.key});

  @override
  Widget build(BuildContext context) => const Icon(Icons.apple, size: 26);
}

/// Icône du chemin par e-mail : neutre, elle ne prétend à aucune marque.
/// Une enveloppe au trait, de la couleur du libellé, comme les autres logos.
class LogoEmail extends StatelessWidget {
  const LogoEmail({super.key});

  @override
  Widget build(BuildContext context) => const Icon(Icons.mail_outline_rounded, size: 26);
}
