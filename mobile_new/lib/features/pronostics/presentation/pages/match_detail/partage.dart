// Partage du pronostic — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

/// Le texte qui accompagne l'image — et rien de plus.
///
/// ── Il répétait l'image, ligne pour ligne ─────────────────────────────────
///
/// Le message portait les équipes, la compétition, la date, le pronostic, la
/// confiance et la cote. La carte partagée juste au-dessus porte **exactement
/// les mêmes** : la ligue en pastille, les deux écussons avec les noms, le
/// pronostic en grand, la cote et la confiance en encadrés, la date et le
/// domaine en pied. Pour un match joué, elle affiche même le score et un
/// bandeau « Pronostic GAGNANT ».
///
/// Le destinataire lisait donc tout en double, et le lien — la seule chose
/// qu'une image ne peut pas porter — se retrouvait noyé en huitième ligne.
///
/// Ce qui reste ici est ce que l'image ne sait pas faire : une ligne de sujet
/// et un lien cliquable. Les équipes sont la seule répétition assumée : un
/// message qui n'annoncerait qu'un lien se lit comme un envoi douteux, et
/// certains clients n'affichent pas les images.
///
/// ── Le lien « voir le détail » était mort ─────────────────────────────────
///
/// Le message renvoyait vers `pronowin.space/pronostics/<id>`. Cette route
/// n'existe pas : le site ne sert que l'accueil et les pages légales, et
/// **toute** adresse sous `/pronostics` répond 404 — vérifié sur le serveur,
/// avec l'identifiant réel d'un pronostic partagé.
///
/// Chaque pronostic partagé depuis que ce message existe portait donc un lien
/// qui ne menait nulle part. Un lien mort dans un partage coûte plus qu'un
/// lien absent : le destinataire le suit, tombe sur une erreur, et c'est
/// l'application qu'il juge.
///
/// Le détail vit dans l'application, pas sur le site. Le message le dit et
/// n'envoie qu'là où il y a quelque chose à trouver.
String _buildShareText(MatchEntity match) {
  final duel = '${match.homeTeam} vs ${match.awayTeam}';

  final sujet = switch (match.result) {
    PronosticResult.win  => '✅ *Pronostic gagnant* — $duel',
    PronosticResult.loss => '📊 *Résultat* — $duel',
    PronosticResult.push => '↩️ *Pronostic remboursé* — $duel',
    null                 => '⚽ *Pronostic PronoWin* — $duel',
  };

  return '$sujet\n\n'
      '📲 Pour consulter le détail et plein d\'autres pronostics, '
      'télécharge l\'application :\n'
      '⬇️ ${AppConstants.apkDownloadUrl}';
}

Future<void> _launchShare(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

void _showShareSheet(BuildContext context, MatchEntity match) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(match: match),
  );
}

class _ShareSheet extends StatefulWidget {
  final MatchEntity match;
  const _ShareSheet({required this.match});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  bool _capturing = false;

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final text = _buildShareText(widget.match);
      await PronoShareService.captureAndShare(
        repaintKey: _cardKey,
        shareText:  text,
        pixelRatio: 3.0,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur de capture : $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _buildShareText(widget.match);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border:       Border.all(color: context.cl.border, width: 0.5),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [

            // ── Handle ──────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.cl.borderS,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Text('Partager ce pronostic',
              style: TextStyle(
                color: context.cl.textP, fontSize: 15,
                fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('${widget.match.homeTeam} vs ${widget.match.awayTeam}',
              style: TextStyle(color: context.cl.textS, fontSize: 12),
              textAlign: TextAlign.center),
            const SizedBox(height: 20),

            // ── Prévisualisation de la carte ─────────────────────────────────
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: PronoShareCard(match: widget.match),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Bouton principal : Partager l'image ──────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _capturing ? null : _shareImage,
                icon: _capturing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.image_rounded, size: 18),
                label: Text(_capturing ? 'Génération…' : 'Partager l\'image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Boutons alternatifs ──────────────────────────────────────────
            Row(children: [
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.chat_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare('https://wa.me/?text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.send_rounded,
                label: 'Telegram',
                color: const Color(0xFF0088CC),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare(
                      'https://t.me/share/url?url=${AppConstants.siteUrl}&text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.copy_rounded,
                label: 'Copier',
                color: AppColors.primary,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Pronostic copié !'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ));
                },
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final IconData fallbackIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShareBtn({
    required this.fallbackIcon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5)),
      child: Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle),
          child: Center(child: Icon(fallbackIcon, color: color, size: 20)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─── COMPOSITIONS D'ÉQUIPE ──────────────────────────────────────────────────────

/// Code HTTP d'une erreur Dio, ou null si ce n'en est pas une — utilisé pour
/// distinguer un invité non connecté (401) d'une vraie panne réseau/serveur.
int? _statusOf(Object? error) =>
    error is DioException ? error.response?.statusCode : null;

/// Message compact affiché à la place du contenu d'une carte (Compositions,
/// Blessures, Classement, H2H) quand elle exige une connexion — plutôt que de
/// faire disparaître silencieusement la carte, ce qui donne l'impression que
/// le match n'a aucune donnée alors qu'il suffit de se connecter.
class _CardLoginPrompt extends StatelessWidget {
  final String message;
  const _CardLoginPrompt({required this.message});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/auth/email?from=${Uri.encodeComponent('/pronostics')}'),
    child: Row(children: [
      Icon(Icons.login_rounded, color: AppColors.primary, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message,
          style: TextStyle(color: context.cl.textM, fontSize: 12))),
      Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
    ]),
  );
}
