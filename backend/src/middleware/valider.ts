import { NextFunction, Request, Response } from 'express';
import { z, ZodTypeAny } from 'zod';

/**
 * La validation d'entrée, déclarée route par route (constat S3 de l'audit du
 * 24 septembre 2026).
 *
 * Elle était artisanale : express-validator dans un fichier sur 59 routes, et
 * 87 contrôles écrits à la main, chacun à sa façon. Le piège trouvé sur les
 * cotes en est le symptôme — `parseFloat('')` vaut NaN, et `NaN < 1.2` est
 * faux : une cote vide passait le contrôle du minimum.
 *
 * Ici la demande est convertie une fois, à l'entrée, par un schéma : un
 * nombre y est un nombre fini ou la demande est refusée, et le contrôleur
 * reçoit des valeurs déjà typées. Le refus est un 422 au format de toutes les
 * erreurs de l'API — `message` lisible — avec le détail des champs.
 */
export function valider(schemas: { body?: ZodTypeAny; query?: ZodTypeAny; params?: ZodTypeAny }) {
  return (req: Request, res: Response, next: NextFunction): void => {
    for (const partie of ['params', 'query', 'body'] as const) {
      const schema = schemas[partie];
      if (!schema) continue;
      const r = schema.safeParse(req[partie] ?? {});
      if (!r.success) {
        const champs = r.error.issues.map((i) => ({
          champ:   i.path.join('.') || partie,
          message: i.message,
        }));
        res.status(422).json({ message: champs[0].message, code: 'VALIDATION', champs });
        return;
      }
      (req as unknown as Record<string, unknown>)[partie] = r.data;
    }
    next();
  };
}

// ─── Briques communes ────────────────────────────────────────────────────────

/** « la cote » → « La cote » : le libellé s'écrit comme dans une phrase. */
const Maj = (libelle: string) => libelle.charAt(0).toUpperCase() + libelle.slice(1);

/** Vide, absent ou nul : « pas de valeur », pas zéro ni NaN. */
const vide = (v: unknown) => v === '' || v === null || v === undefined;

/** Un nombre fini, depuis un nombre ou un texte (formulaire, JSON).
 *  [libelle] comme dans une phrase : « la cote conseillée ». */
export const nombre = (libelle: string) => z.preprocess(
  (v) => (vide(v) ? undefined : typeof v === 'string' ? Number(v.trim().replace(',', '.')) : v),
  z.number({ required_error: `Indiquez ${libelle}.`, invalid_type_error: `${Maj(libelle)} doit être un nombre.` })
    .finite(`${Maj(libelle)} doit être un nombre.`),
);

/** Le même, facultatif : vide devient `undefined`. */
export const nombreFacultatif = (libelle: string) => z.preprocess(
  (v) => (vide(v) ? undefined : typeof v === 'string' ? Number(v.trim().replace(',', '.')) : v),
  z.number({ invalid_type_error: `${Maj(libelle)} doit être un nombre.` })
    .finite(`${Maj(libelle)} doit être un nombre.`).optional(),
);

/** Case à cocher, JSON ou formulaire : true, 'true', 'on', '1'. Absent : faux. */
export const booleen = z.preprocess(
  (v) => v === true || v === 'true' || v === 'on' || v === '1', z.boolean());

/** Un identifiant reçu du client : texte non vide, borné. */
export const identifiant = (libelle: string) => z.string({
  required_error: `Indiquez ${libelle}.`, invalid_type_error: `${Maj(libelle)} est invalide.`,
}).trim().min(1, `Indiquez ${libelle}.`).max(80, `${Maj(libelle)} est invalide.`);

/** Texte libre facultatif, borné. Vide devient `undefined`. */
export const texteFacultatif = (max: number) => z.preprocess(
  (v) => (vide(v) ? undefined : v), z.string().trim().max(max).optional());
