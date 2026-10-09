import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'aides/banc_ecran.dart';

void main(){
 setUpAll(preparerBanc);
 test('les groupes et les identifiants survivent au décodage, ancien serveur compatible',(){
  final r=StandingRow.fromJson({'rank':1,'groupId':'b','groupName':'Group B','teamId':3,'season':2024,'isMatchTeam':true,'stale':true});
  expect(r.groupId,'b');expect(r.teamId,3);expect(r.season,2024);expect(r.isMatchTeam,true);expect(r.stale,true);
  expect(StandingRow.fromJson({'rank':1}).groupId,'0');
 });
 for(final theme in [AppTheme.light,AppTheme.dark]){
  testWidgets('sélection du groupe du match puis autre groupe, texte 180%, thème ${theme.brightness}',(t)async{
   await mount(t,theme,rows:[row('a','Alpha',false),row('b','Home',true)]);
   expect(find.text('Saison 2024'),findsOneWidget);
   var menu=t.widget<DropdownButton<String>>(find.byKey(const Key('standings-group')));
   expect(menu.value,'b');
   await t.tap(find.byKey(const Key('standings-group')));await t.pump(const Duration(milliseconds:400));
   await t.tap(find.text('Groupe A').last);await t.pump(const Duration(milliseconds:400));
   menu=t.widget<DropdownButton<String>>(find.byKey(const Key('standings-group')));expect(menu.value,'a');
   expect(find.text('Alpha'),findsOneWidget);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());await t.pump();
  });
 }
 for(final code in [404,503]){
  testWidgets('état explicite et reprise adaptée au code $code',(t)async{
   await mount(t,AppTheme.light,code:code);
   expect(find.text(code==404?'Le fournisseur ne propose pas de classement pour cette compétition.':'Le classement est momentanément indisponible.'),findsOneWidget);
   expect(find.text('Réessayer'),code==404?findsNothing:findsOneWidget);
   expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());await t.pump();
  });
 }
 testWidgets('pas encore publié est distinct de non couvert',(t)async{
  await mount(t,AppTheme.dark);
  expect(find.text("Le classement n'est pas encore publié pour cette saison."),findsOneWidget);
  expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());await t.pump();
 });
}
StandingRow row(String group,String name,bool match)=>StandingRow(rank:1,teamName:name,played:5,win:4,draw:0,lose:1,
 goalsDiff:6,points:12,groupId:group,groupName:'Group ${group.toUpperCase()}',season:2024,isMatchTeam:match,
 zone:'Ligue des champions',zoneNature:'c1');
Future<void> mount(WidgetTester t,ThemeData theme,{List<StandingRow> rows=const [],int? code})async{
 SharedPreferences.setMockInitialValues({});t.view.physicalSize=const Size(780,1600);t.view.devicePixelRatio=2;
 addTearDown(t.view.reset);
 final match=MatchModel.fromJson({'id':'m','league':'Cup','league_country':'AF_999','home_team':'Home','away_team':'Away',
 'status':'finished','match_date':'2024-10-05T12:00:00Z','has_pronostic':false,'home_score':1,'away_score':0});
 await t.pumpWidget(ProviderScope(overrides:[...donneesCommunes(),
  matchDetailProvider('m').overrideWith((ref)async=>match),
  liveScoreProvider('m').overrideWith((ref)async=>const LiveScore(status:'FINISHED',homeScore:1,awayScore:0)),
  matchStatsProvider('m').overrideWith((ref)async=>null),
  lineupsProvider('m').overrideWith((ref)async=>const LineupsData(available:false)),
  injuriesProvider('m').overrideWith((ref)async=>[]),
  h2hProvider('m').overrideWith((ref)async=>throw Exception('none')),
  playerRatingsProvider('m').overrideWith((ref)async=>[]),
  standingsProvider('m').overrideWith((ref)async{
   if(code!=null)throw DioException(requestOptions:RequestOptions(),response:Response(requestOptions:RequestOptions(),statusCode:code));
   return rows;
  }),
 ],child:MaterialApp(theme:theme,
  builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.8),disableAnimations:true),child:child!),
  home:const MatchDetailPage(matchId:'m'))));
 for(var i=0;i<10;i++){await t.pump(const Duration(milliseconds:100));}
 await t.ensureVisible(find.text('Classements'));await t.tap(find.text('Classements'));
 for(var i=0;i<10;i++){await t.pump(const Duration(milliseconds:100));}
}
