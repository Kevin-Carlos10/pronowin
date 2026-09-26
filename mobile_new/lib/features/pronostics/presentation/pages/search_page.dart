import 'package:flutter/material.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/pronostics_provider.dart';
import '../widgets/match_card_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl   = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Le filtre local a été retiré.
  //
  // Il parcourait `pagedState.matches` — la liste **déjà chargée** du provider
  // paginé : vingt matchs, ceux de la page courante et des filtres courants.
  // Une équipe qui existe mais dont la page n'avait pas été téléchargée était
  // annoncée absente, et le résultat dépendait du nombre de fois qu'on avait
  // fait défiler la liste.
  //
  // La recherche est faite par la base, via `rechercheMatchsProvider`.

  @override
  Widget build(BuildContext context) {
    final terme      = _query.trim();
    // La recherche part au serveur, dès deux caractères — même seuil que lui.
    final resultats  = ref.watch(rechercheMatchsProvider(terme));
    final authState  = ref.watch(authProvider);
    final isPremium  = authState is AuthAuthenticated && authState.user.isPremium;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.cl.textP),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: TextStyle(color: context.cl.textP, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Équipe, ligue…',
            hintStyle: TextStyle(color: context.cl.textM, fontSize: 16),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: context.cl.textM, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: terme.length < 2
        ? _EmptyPrompt()
        : resultats.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
            error: (_, _) => ErreurChargement(
                erreur: "La recherche n'a pas abouti.",
                quoi: 'les matchs',
                from: '/recherche',
                onRetry: () =>
                    ref.invalidate(rechercheMatchsProvider(terme))),
            data: (liste) => liste.isEmpty
                ? _NoResults(query: _query)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                    itemCount: liste.length,
                    itemBuilder: (_, i) => MatchCardWidget(
                      match: liste[i],
                      isPremiumUser: isPremium,
                      showDate: true,
                    ),
                  ),
          ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_rounded, size: 56, color: context.cl.textM),
      const SizedBox(height: 16),
      Text('Rechercher un match ou une ligue',
        style: TextStyle(color: context.cl.textS, fontSize: 15,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Ex: PSG, Ligue 1, Real Madrid…',
        style: TextStyle(color: context.cl.textM, fontSize: 13)),
    ]),
  );
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.sentiment_dissatisfied_rounded,
        size: 52, color: context.cl.textM),
      const SizedBox(height: 16),
      Text('Aucun résultat pour "$query"',
        style: TextStyle(color: context.cl.textS, fontSize: 15,
          fontWeight: FontWeight.w600),
        textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('Essayez un autre nom d\'équipe ou de ligue',
        style: TextStyle(color: context.cl.textM, fontSize: 13)),
    ]),
  );
}
