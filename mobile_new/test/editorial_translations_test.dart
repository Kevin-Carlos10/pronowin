import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/l10n/editorial_text.dart';
import 'package:pronowin/features/tutoriels/domain/entities/tutorial_entity.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';
void main(){
 tearDown(()=>AppStrings.setCurrentLanguage('fr'));
 test('recommendations and bankroll retain both languages after loading',(){
  final p=ForYouProno.fromJson({'id':'p','league':'L','league_code':'L','home_team':'Greece','away_team':'Netherlands','match_date':'2026-10-07T10:00:00Z','prediction_type':'other','prediction_label':'Choix FR','prediction_label_en':'Pick EN','analyst_note':'Note FR','analyst_note_en':'Note EN','odds_recommended':1.8,'confidence_score':4,'ai_probability':70});
  final b=BankrollBet.fromJson({'id':'b','pronostic_id':'p','match':{'id':'m','home_team':'H','away_team':'A','league':'L'},'staked_amount':10,'suggested_amount':10,'odds_used':1.8,'potential_gain':18,'created_at':'2026-10-07T10:00:00Z','prediction_label':'Choix FR','prediction_label_en':'Pick EN','confidence_score':4},currency:'XOF');
  final rec=ForYouRec(score:50,reasons:['Ta ligue préférée'],reasonsEn:['Your favourite league'],pronostic:p);
  AppStrings.setCurrentLanguage('en');expect(rec.reasons,['Your favourite league']);expect(p.predictionLabel,'Pick EN');expect(p.analystNote,'Note EN');expect(p.homeTeam,'Greece');expect(b.predictionLabel,'Pick EN');
  AppStrings.setCurrentLanguage('fr');expect(p.predictionLabel,'Choix FR');expect(p.homeTeam,'Grèce');expect(b.predictionLabel,'Choix FR');
 });
 test('already loaded tutorial follows locale; cache and copy keep both originals',(){
  final t=TutorialEntity.fromJson({'id':'t','title':'Titre','title_en':'Title','description':'Description FR','description_en':'Description EN','article_content':'Article FR','article_content_en':'Article EN'});
  AppStrings.setCurrentLanguage('en'); expect(t.title,'Title');expect(t.articleContent,'Article EN');
  expect(t.toJson()['title'],'Titre');expect(t.copyWith(isCompleted:true).toJson()['title'],'Titre');
  AppStrings.setCurrentLanguage('fr');expect(t.title,'Titre');
 });
 test('prediction and analyst note switch without rewriting cached sources',(){
  final p=MatchModel.fromJson({'id':'p','league':'L','home_team':'H','away_team':'A','match_date':'2026-10-07T10:00:00Z','prediction_label':'Choix FR','prediction_label_en':'Pick EN','analyst_note':'Note FR','analyst_note_en':'Note EN'});
  AppStrings.setCurrentLanguage('en');expect(p.predictionLabel,'Pick EN');expect(p.analystNote,'Note EN');
  expect(p.toJson()['prediction_label'],'Choix FR');expect(p.toJson()['analyst_note_en'],'Note EN');
 });
 test('notification mark as read preserves translations across language changes',(){
  final n=AppNotification.fromJson({'id':'n','title':'Bonjour','body':'Texte','title_en':'Hello','body_en':'Text'}).copyWith(isRead:true);
  AppStrings.setCurrentLanguage('en');expect(n.title,'Hello');expect(n.body,'Text');
  AppStrings.setCurrentLanguage('fr');expect(n.title,'Bonjour');expect(n.isRead,true);
 });
 test('missing translation retains the original, including RSS and old cache entries',(){
  AppStrings.setCurrentLanguage('en');expect(editorialField({'titre':'Original'},'titre'),'Original');
  expect(editorialText('Original','  '),'Original');
 });
}
