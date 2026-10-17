import 'package:pronowin/l10n/app_strings.dart';
import 'package:intl/intl.dart';

/// Tous les formats de date de l'app — avec fallback si locale pas initialisée
class AppDateFormatter {

  /// "ven. 22 mai · 18h45"
  static String matchDate(DateTime d) {
    try {
      return DateFormat("EEE d MMM · HH:mm").format(d);
    } catch (_) {
      return DateFormat("dd/MM/yyyy · HH:mm", 'en').format(d);
    }
  }

  /// "vendredi 22 mai 2026 · 18h45" (pour la page détail)
  static String matchDateFull(DateTime d) {
    try {
      return DateFormat("EEEE d MMMM · HH:mm").format(d);
    } catch (_) {
      return DateFormat("dd/MM/yyyy · HH:mm").format(d);
    }
  }

  /// "22 mai, 18:05" (pour les transactions)
  static String transactionDate(DateTime d) {
    try {
      return DateFormat('d MMM, HH:mm').format(d);
    } catch (_) {
      return DateFormat('dd/MM HH:mm').format(d);
    }
  }

  /// "22 mai" (pour les notifications)
  static String shortDate(DateTime d) {
    try {
      return DateFormat('d MMM').format(d);
    } catch (_) {
      return DateFormat('dd/MM').format(d);
    }
  }

  /// "18:45" (heure seule)
  static String timeOnly(DateTime d) => DateFormat('HH:mm').format(d);

  /// Durée relative : "3 min", "2h", "5j", "22 mai"
  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}min';
    if (diff.inHours   < 24)  return '${diff.inHours}h';
    if (diff.inDays    < 7)   return AppStrings.current.locale.languageCode == 'en' ? '${diff.inDays}d' : '${diff.inDays}j';
    return shortDate(d);
  }
}
