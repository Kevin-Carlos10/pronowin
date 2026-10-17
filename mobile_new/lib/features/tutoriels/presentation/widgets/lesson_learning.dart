import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../../../l10n/app_strings.dart';

class LessonPoints extends StatelessWidget {
  const LessonPoints({super.key, required this.title, this.items});
  final String title;
  final dynamic items;
  @override
  Widget build(BuildContext context) {
    final points = items is List
        ? (items as List)
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList()
        : <String>[];
    if (points.isEmpty) return const SizedBox.shrink();
    return _Panel(
      title: title,
      child: Column(
        children: [
          for (final point in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: context.cl.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(point, style: const TextStyle(height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

/// Fictional inputs only: never tied to the user's funds or a live selection.
class ValueExercise extends StatefulWidget {
  const ValueExercise({super.key});
  @override
  State<ValueExercise> createState() => _ValueExerciseState();
}

class _ValueExerciseState extends State<ValueExercise> {
  double probability = 50, odds = 2;
  @override
  Widget build(BuildContext context) {
    final value = (probability / 100 * odds - 1) * 100;
    return _Panel(
      title: tr(context, "À toi d’essayer"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, "Exercice fictif · aucune mise réelle"),
            style: TextStyle(color: context.cl.textS),
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, "Probabilité estimée : {arg0} %", [
              probability.round().toString(),
            ]),
          ),
          Slider(
            value: probability,
            min: 10,
            max: 90,
            divisions: 80,
            semanticFormatterCallback: (v) => '${v.round()} %',
            onChanged: (v) => setState(() => probability = v),
          ),
          Text(tr(context, "Cote : {arg0}", [odds.toStringAsFixed(2)])),
          Slider(
            value: odds,
            min: 1.1,
            max: 5,
            divisions: 78,
            semanticFormatterCallback: (v) => v.toStringAsFixed(2),
            onChanged: (v) => setState(() => odds = v),
          ),
          AnimatedContainer(
            duration: context.duree(const Duration(milliseconds: 200)),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (value > 0 ? context.cl.success : context.cl.textS)
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} %',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(tr(context, "Espérance théorique par unité misée")),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    "Calcul : probabilité × cote − 1. Une estimation positive ne garantit aucun gain.",
                  ),
                  style: TextStyle(color: context.cl.textS, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LessonQuiz extends StatefulWidget {
  const LessonQuiz({super.key, this.questions});
  final dynamic questions;
  @override
  State<LessonQuiz> createState() => _LessonQuizState();
}

class _LessonQuizState extends State<LessonQuiz> {
  final Map<int, int> answers = {};
  @override
  Widget build(BuildContext context) {
    final questions = widget.questions is List
        ? (widget.questions as List)
              .whereType<Map>()
              .where((q) => q['options'] is List && q['answer'] is int)
              .toList()
        : <Map>[];
    if (questions.isEmpty) return const SizedBox.shrink();
    final score = answers.entries
        .where((a) => questions[a.key]['answer'] == a.value)
        .length;
    return _Panel(
      title: tr(context, "Teste tes connaissances"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              context,
              "Un exercice pour comprendre, indépendant de ta progression.",
            ),
            style: TextStyle(color: context.cl.textS),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < questions.length; i++) ...[
            Text(
              '${i + 1}. ${questions[i]['question']}',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
            ),
            const SizedBox(height: 8),
            for (var j = 0; j < (questions[i]['options'] as List).length; j++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(12),
                  ),
                  onPressed: answers.containsKey(i)
                      ? null
                      : () => setState(() => answers[i] = j),
                  icon: Icon(
                    answers[i] == j
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                  ),
                  label: Text('${questions[i]['options'][j]}'),
                ),
              ),
            AnimatedSize(
              duration: context.duree(const Duration(milliseconds: 220)),
              alignment: Alignment.topCenter,
              child: !answers.containsKey(i)
                  ? const SizedBox.shrink()
                  : Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                context,
                                answers[i] == questions[i]['answer']
                                    ? "Bonne réponse"
                                    : "À revoir",
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: answers[i] == questions[i]['answer']
                                    ? context.cl.success
                                    : context.cl.textP,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${questions[i]['explanation']}',
                              style: const TextStyle(height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
          ],
          if (answers.length == questions.length) ...[
            Text(
              tr(context, "Résultat : {arg0} / {arg1}", [
                score.toString(),
                questions.length.toString(),
              ]),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextButton.icon(
              onPressed: () => setState(answers.clear),
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, "Recommencer")),
            ),
          ],
        ],
      ),
    );
  }
}
