import catalog from './notification-catalog.json';
export type BilingualPayload = { title: string; body: string; titleEn?: string | null; bodyEn?: string | null; data?: Record<string,string> };
export function translatedNotificationText(value: string): string {
 const exact = (catalog.exact as Record<string,string>)[value];
 if (exact) return exact;
 for (const [pattern, replacement] of catalog.rules) {
  const regex = new RegExp(pattern);
  if(regex.test(value)) return value.replace(regex, replacement);
 }
 return value; // custom notes are preserved, never guessed
}
export function bilingual<T extends BilingualPayload>(payload: T): T & {titleEn: string; bodyEn: string} {
 return {...payload, titleEn: payload.titleEn?.trim() || translatedNotificationText(payload.title), bodyEn: payload.bodyEn?.trim() || translatedNotificationText(payload.body)};
}
export function forLanguage(payload: BilingualPayload, language: string) {
 const p=bilingual(payload);
 return {title: language==='en' ? p.titleEn : p.title, body: language==='en' ? p.bodyEn : p.body,
  data:{...p.data, title_fr:p.title, body_fr:p.body, title_en:p.titleEn, body_en:p.bodyEn}};
}
