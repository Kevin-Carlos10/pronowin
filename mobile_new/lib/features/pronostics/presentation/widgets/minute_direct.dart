import 'package:flutter/widgets.dart';

import 'package:pronowin/l10n/app_strings.dart';

/// La minute d'un match en direct, comme sur Sofascore : « 67' ».
///
/// Les cartes, les lignes et les vignettes de l'accueil n'affichaient que
/// « En direct » ou « LIVE » (vidéos du 8 novembre 2026). Le serveur envoie
/// pourtant la minute (`elapsed`) : sans elle, un 0-0 en direct ne dit pas
/// s'il en reste cinq minutes ou quatre-vingts.
///
/// [repli] : ce qu'on affiche tant que la source n'a pas publié de minute
/// (coup d'envoi tout juste donné, panne de la source).
String libelleMinuteDirect(BuildContext context, int? minute, {String? repli}) =>
    minute != null && minute > 0 ? "$minute'" : (repli ?? tr(context, "En direct"));

/// La minute lue dans une réponse brute du serveur.
int? minuteDirect(Map<String, dynamic> m) => (m['elapsed'] as num?)?.toInt();
