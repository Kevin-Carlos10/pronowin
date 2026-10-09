import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'aides/banc_ecran.dart';
import 'package:pronowin/features/pronostics/presentation/providers/match_info_provider.dart';

void main() {
  setUpAll(preparerBanc);
  test('cotes: clé stable indépendante de la traduction, repli FR et EN', () {
    for (final data in [
      {'name':'Vainqueur du match'}, {'name':'Match Winner'},
      {'name':'Traduit autrement','key':'match winner'},
    ]) {
      final odds=LiveOddsData.fromJson({'markets':[ {...data,'values':[]} ]});
      expect(odds.markets.single.principal, isTrue);
    }
    expect(const LiveOddMarket(name:'Correct Score',values:[]).principal,isFalse);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('match sans pronostic: événements et stats accessibles, thème ${theme.brightness}', (t) async {
      final r = await mesurerEcran(t, ecran: const MatchDetailPage(matchId:'m'), theme:theme,
        echelle:1.8, defilements:2, surcharges: [
          matchDetailProvider('m').overrideWith((ref) async => _match()),
          liveScoreProvider('m').overrideWith((ref) async => const LiveScore(status:'LIVE',homeScore:1,awayScore:0,elapsed:30)),
          matchStatsProvider('m').overrideWith((ref) async => _stats()),
          lineupsProvider('m').overrideWith((ref) async => const LineupsData(available:false)),
          injuriesProvider('m').overrideWith((ref) async => []),
          standingsProvider('m').overrideWith((ref) async => []),
          h2hProvider('m').overrideWith((ref) async => throw Exception('unavailable')),
          liveOddsProvider('m').overrideWith((ref) async => const LiveOddsData(openingOdd:0,markets:[])),
        ], verifier: () {
          expect(find.text('Faits marquants'),findsOneWidget);
          expect(find.text('Statistiques'),findsOneWidget);
          expect(find.text('Aucun pronostic publié pour ce match.'),findsOneWidget);
        });
      expect(r.autres,isEmpty); expect(r.debordements,isEmpty);
    });
  }

  testWidgets('actualise le direct, suspend en arrière-plan et finit le match', (t) async {
    SharedPreferences.setMockInitialValues({});
    var status='LIVE'; var scores=0; var stats=0; var infos=0;
    await t.pumpWidget(ProviderScope(overrides:[
      ...donneesCommunes(),
      matchInfoProvider('m').overrideWith((ref) async { infos++; return const MatchInfo(phase:'ET'); }),
      matchDetailProvider('m').overrideWith((ref) async => _match(status:status.toLowerCase())),
      liveScoreProvider('m').overrideWith((ref) async { scores++; return LiveScore(status:status,homeScore:1,awayScore:0); }),
      matchStatsProvider('m').overrideWith((ref) async { stats++; return _stats(); }),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available:false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      standingsProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('unavailable')),
      liveOddsProvider('m').overrideWith((ref) async => const LiveOddsData(openingOdd:0,markets:[])),
      playerRatingsProvider('m').overrideWith((ref) async => []),
    ],child: MaterialApp(theme:AppTheme.dark,
      builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(disableAnimations:true),child:w!),
      home:const MatchDetailPage(matchId:'m'))));
    await t.pump(); await t.pump(const Duration(milliseconds:500));
    final initial=scores;
    await t.pump(const Duration(seconds:30)); await t.pump();
    expect(scores,greaterThan(initial)); expect(stats,greaterThan(1)); expect(infos,greaterThan(1));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused=scores; final pausedInfo=infos;
    await t.pump(const Duration(seconds:90)); await t.pump();
    expect(scores,paused); expect(infos,pausedInfo);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(); expect(scores,greaterThan(paused));
    status='FINISHED';
    await t.pump(const Duration(seconds:30)); await t.pump(); await t.pump();
    final finished=scores; final finishedInfo=infos;
    await t.pump(const Duration(seconds:60)); await t.pump();
    expect(scores,finished,reason:'le polling doit s’arrêter après la fin'); expect(infos,finishedInfo);
    await t.pumpWidget(const SizedBox()); await t.pump();
    expect(t.takeException(),isNull);
  });
}

MatchModel _match({String status='live'}) => MatchModel.fromJson({
  'id':'m','league':'Premier League','league_country':'PL',
  'home_team':'Home','away_team':'Away','status':status,
  'match_date':DateTime.now().subtract(const Duration(minutes:30)).toIso8601String(),
  'has_pronostic':false,'home_score':1,'away_score':0,
});
MatchStatsData _stats() => MatchStatsData(fixtureId:42,
  updatedAt:DateTime.utc(2026,10,5,12),homeTeam:'Home',awayTeam:'Away',
  events:const [MatchEvent(minute:21,team:'Home',player:'Player',type:'Goal',detail:'Normal Goal')],
  stats:const [MatchStat(label:'Ball Possession',home:'60%',away:'40%')]);
