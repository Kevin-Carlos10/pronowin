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
/// Tous les fournisseurs partagent désormais la même forme. C'est le modèle des
/// grandes apps sport (Sofascore, OneFootball) : on propose, on n'oriente pas.
///
/// Ajouter « Continuer avec Apple » — obligatoire dès la sortie iOS, règle 4.8
/// de l'App Store — ne demandera qu'une entrée de plus dans la pile.
class BoutonFournisseur extends StatelessWidget {
  final String libelle;

  /// Marque du fournisseur, à sa gauche. `null` pour un chemin sans marque
  /// (l'e-mail), qui reçoit alors une icône neutre.
  final Widget? logo;

  final VoidCallback? onPressed;

  /// Grise le bouton pendant qu'un autre chemin est en cours : deux
  /// authentifications simultanées produiraient deux sessions concurrentes.
  final bool desactive;

  const BoutonFournisseur({
    super.key,
    required this.libelle,
    this.logo,
    this.onPressed,
    this.desactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final actif = !desactive && onPressed != null;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: actif ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Opacity(
            opacity: actif ? 1 : 0.45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.cl.borderS, width: 1),
              ),
              child: Row(children: [
                SizedBox(width: 22, height: 22, child: Center(child: logo)),
                // Le libellé reste centré sur toute la largeur du bouton, la
                // marque flottant à gauche — c'est ce qui aligne visuellement
                // les intitulés d'une pile où les logos n'ont pas la même
                // largeur.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: Text(
                      libelle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ]),
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
      SvgPicture.string(_svg, width: 20, height: 20);
}

/// Icône du chemin par e-mail : neutre, elle ne prétend à aucune marque.
class LogoEmail extends StatelessWidget {
  const LogoEmail({super.key});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.alternate_email_rounded, size: 20, color: context.cl.textS);
}
