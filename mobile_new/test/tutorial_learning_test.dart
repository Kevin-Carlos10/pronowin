import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/tutoriels/presentation/widgets/lesson_learning.dart';
import 'package:pronowin/features/tutoriels/presentation/pages/tutorial_detail_page.dart';
import 'package:pronowin/features/tutoriels/presentation/providers/tutorial_provider.dart';
import 'package:pronowin/features/tutoriels/domain/entities/tutorial_entity.dart';
import 'aides/banc_ecran.dart';

const lesson = TutorialEntity(id:'lesson', title:'Comprendre le Value Bet', description:'Comparer une estimation à une cote.', level:TutorialLevel.beginner,category:'valuebet',lessonContent:{'fr':{'objectives':['Comparer une probabilité et une cote.'],'takeaways':['Une estimation reste incertaine.']}});
void main(){
 setUpAll(preparerBanc);
 for(final dark in [false,true]){
  for(final scale in [1.0,1.8]){
   testWidgets('lesson layout dark=$dark scale=$scale',(tester) async {
    final result = await mesurerEcran(tester,ecran:const TutorialDetailPage(tutorialId:'lesson',preloaded:lesson),theme:dark ? AppTheme.dark:AppTheme.light,echelle:scale,surcharges:[tutorialsProvider.overrideWith((ref) async=>[])],defilements:5);
    expect(result.debordements, isEmpty);
    expect(result.autres, isEmpty);
   });
  }
 }
 testWidgets('simulator recalculates expected value',(tester) async {
  await tester.pumpWidget(MaterialApp(theme:AppTheme.light,home:const Scaffold(body:SingleChildScrollView(child:ValueExercise()))));
  expect(find.text('0.0 %'),findsOneWidget);
  tester.widget<Slider>(find.byType(Slider).first).onChanged!(60);
  await tester.pumpAndSettle();
  expect(find.text('+20.0 %'),findsOneWidget);
 });
 testWidgets('quiz explains wrong answers and can be retried',(tester) async {
  await tester.pumpWidget(MaterialApp(theme:AppTheme.light,home:const Scaffold(body:SingleChildScrollView(child:LessonQuiz(questions:[{'question':'Un gain est-il garanti ?', 'options':['Oui','Non'], 'answer':1,'explanation':'Une estimation peut être erronée.'}])))));
  await tester.tap(find.text('Oui'));await tester.pumpAndSettle();
  expect(find.text('À revoir'),findsOneWidget);
  expect(find.text('Une estimation peut être erronée.'),findsOneWidget);
  expect(find.text('Résultat : 0 / 1'),findsOneWidget);
  await tester.tap(find.text('Recommencer'));await tester.pumpAndSettle();
  await tester.tap(find.text('Non'));await tester.pumpAndSettle();
  expect(find.text('Bonne réponse'),findsOneWidget);
  expect(find.text('Résultat : 1 / 1'),findsOneWidget);
 });
}
