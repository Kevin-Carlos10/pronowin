import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/match_entity.dart';
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

  List<MatchEntity> _filter(List<MatchEntity> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return all.where((m) =>
      m.homeTeam.toLowerCase().contains(q) ||
      m.awayTeam.toLowerCase().contains(q) ||
      m.league.toLowerCase().contains(q) ||
      m.predictionLabel.toLowerCase().contains(q)
    ).toList()
      ..sort((a, b) => a.matchDate.compareTo(b.matchDate));
  }

  @override
  Widget build(BuildContext context) {
    final pagedState = ref.watch(matchesPaginatedProvider);
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
      body: pagedState.isInitialLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : pagedState.error != null && pagedState.matches.isEmpty
        ? Center(child: Text('Impossible de charger les matchs',
            style: TextStyle(color: context.cl.textS)))
        : Builder(builder: (context) {
          final all = pagedState.matches;
          if (_query.trim().isEmpty) {
            return _EmptyPrompt();
          }
          final results = _filter(all);
          if (results.isEmpty) {
            return _NoResults(query: _query);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
            itemCount: results.length,
            itemBuilder: (_, i) => MatchCardWidget(
              match: results[i],
              isPremiumUser: isPremium,
              showDate: true,
            ),
          );
        }),
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
