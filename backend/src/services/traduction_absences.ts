import { journal } from '../utils/logger';
import { absence } from '../i18n/football';
const inconnus = new Set<string>();
/** Deterministic display translation, shared with the mobile client. */
export function traduireAbsence(motif: unknown): string {
  if (typeof motif !== 'string') return '';
  const texte = motif.trim(); if (!texte) return '';
  const result = absence(texte, 'fr');
  if (result.known) return result.text;
  const cle = texte.toLowerCase();
  if (!inconnus.has(cle)) {
    if (inconnus.size >= 200) inconnus.clear();
    inconnus.add(cle); journal.warn('[Absences] motif non traduit : ' + texte);
  }
  return texte;
}
/** A category, deliberately independent of the display language. */
export function estSuspension(motif: unknown): boolean {
  if (typeof motif !== 'string') return false;
  const cle = motif.toLowerCase();
  return cle.includes('card') || cle.includes('suspend');
}
