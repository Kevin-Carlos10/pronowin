/** Optional editorial fields: absent preserves existing text; blank clears translation. */
export function optionalText(value: unknown, max = 50000): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null || value === '') return null;
  if (typeof value !== 'string' || value.length > max) throw new Error('Traduction invalide ou trop longue.');
  return value.trim() || null;
}
export function englishPair(title: unknown, body: unknown) {
  const titleEn = optionalText(title, 100), bodyEn = optionalText(body, 300);
  if (!!titleEn !== !!bodyEn) throw new Error('Renseignez le titre ET le message anglais, ou laissez les deux vides.');
  return { titleEn, bodyEn };
}
