import 'app_strings.dart';
/// Keep source strings in caches; select the display language at render time.
String editorialText(String source, String? english) =>
    AppStrings.current.locale.languageCode == 'en' && english != null && english.trim().isNotEmpty
        ? english : source;
String editorialField(Map<String, dynamic> item, String field) =>
    editorialText(item[field] as String? ?? '', item['${field}_en'] as String?);
