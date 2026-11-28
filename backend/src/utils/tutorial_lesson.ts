/** Contenu éditorial, limité et validé avant stockage. */
export function parseLesson(input: unknown): any {
  if (input === undefined) return undefined;
  if (input === null || input === '') return {fr: {}, en: {}};
  let value: any;
  try { value = typeof input === 'string' ? JSON.parse(input) : input; }
  catch { throw new Error('Contenu pédagogique invalide.'); }
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Contenu pédagogique invalide.');
  const text = (v: unknown, max = 600): string => {
    if (typeof v !== 'string' || v.length > max) throw new Error('Texte pédagogique invalide ou trop long.');
    return v.trim();
  };
  const list = (v: any, max: number): any[] => {
    if (v == null) return [];
    if (!Array.isArray(v) || v.length > max) throw new Error('Trop d’éléments pédagogiques.');
    return v;
  };
  const result: any = {};
  for (const lang of ['fr','en']) {
    const c = value[lang] ?? {};
    if (typeof c !== 'object' || Array.isArray(c)) throw new Error('Contenu pédagogique invalide.');
    result[lang] = {
      objectives: list(c.objectives, 6).map(v => text(v)).filter(Boolean),
      takeaways: list(c.takeaways, 6).map(v => text(v)).filter(Boolean),
      chapters: list(c.chapters, 10).map(v => {
        if (!v || typeof v !== 'object') throw new Error('Chapitre invalide.');
        if (!Number.isInteger(v.seconds) || v.seconds < 0 || v.seconds > 86400) throw new Error('Repère vidéo invalide.');
        const title = text(v.title, 160); if (!title) throw new Error('Titre du chapitre requis.');
        return {title, seconds:v.seconds};
      }).sort((a,b) => a.seconds-b.seconds),
      quiz: list(c.quiz, 3).map(v => {
        if (!v || typeof v !== 'object') throw new Error('Question invalide.');
        const question = text(v.question); const options = list(v.options,4).map(o=>text(o,300));
        const explanation = text(v.explanation,1200);
        if (!question || !explanation || options.length<2 || options.some(o=>!o) ||
          !Number.isInteger(v.answer) || v.answer<0 || v.answer>=options.length) throw new Error('Question du quiz incomplète.');
        return {question,options,answer:v.answer,explanation};
      }),
    };
  }
  return result;
}
