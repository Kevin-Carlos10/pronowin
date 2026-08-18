import { prisma } from '../lib/prisma';

/**
 * Numéros Mobile Money de réception des paiements.
 *
 * Auparavant : trois variables `MOBCASH_*` côté serveur, et une constante
 * `_paymentPhone` codée en dur dans l'app — qui ne portaient déjà pas les
 * mêmes valeurs. L'écran de paiement montrait la constante, le serveur ne
 * connaissait que les variables, et rien ne signalait l'écart.
 *
 * Cette table est désormais la source unique. `MOBCASH_NUMBERS` ne sert plus
 * que de repli au cas où la table serait vide.
 */

export interface MethodePaiement {
  key:       string;
  label:     string;
  phone:     string;
  isActive:  boolean;
  sortOrder: number;
}

/** Repli : la table est vide (première installation, base réinitialisée…). */
const REPLI: MethodePaiement[] = [
  { key: 'orange_money', label: 'Orange Money', phone: process.env.MOBCASH_ORANGE ?? '', isActive: true, sortOrder: 0 },
].filter(m => m.phone !== '');

/** Clé technique : minuscules, chiffres et tirets bas uniquement. */
export function normaliserCle(brut: string): string {
  return brut.trim().toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')  // accents
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/** Méthodes proposées à l'utilisateur : actives, dans l'ordre défini. */
export async function listerPubliques(): Promise<MethodePaiement[]> {
  try {
    const lignes = await prisma.paymentMethod.findMany({
      where:   { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { label: 'asc' }],
      select:  { key: true, label: true, phone: true, isActive: true, sortOrder: true },
    });
    return lignes.length ? lignes : REPLI;
  } catch {
    return REPLI;
  }
}

/** Toutes les méthodes, actives ou non — vue d'administration. */
export async function listerToutes() {
  return prisma.paymentMethod.findMany({
    orderBy: [{ sortOrder: 'asc' }, { label: 'asc' }],
  });
}

function _valider(label: string, phone: string) {
  if (!label.trim())  throw new Error('Le nom de l\'opérateur est requis.');
  if (label.length > 40) throw new Error('Nom d\'opérateur trop long (40 caractères maximum).');

  // On accepte les espaces et le « + » à la saisie, mais le numéro stocké ne
  // garde que les chiffres et un éventuel « + » de tête : c'est lui qui part
  // dans le presse-papier de l'utilisateur, il doit être composable tel quel.
  const nettoye = phone.trim().replace(/[\s.\-()]/g, '');
  if (!/^\+?\d{6,15}$/.test(nettoye)) {
    throw new Error('Numéro invalide : 6 à 15 chiffres, avec ou sans indicatif « + ».');
  }
  return nettoye;
}

export async function creer(params: {
  key?: string; label: string; phone: string; isActive?: boolean; sortOrder?: number;
}) {
  const phone = _valider(params.label, params.phone);
  const key   = normaliserCle(params.key?.trim() || params.label);
  if (!key) throw new Error('Impossible de dériver un identifiant depuis ce nom.');

  const existe = await prisma.paymentMethod.findUnique({ where: { key } });
  if (existe) throw new Error(`L'identifiant « ${key} » existe déjà.`);

  return prisma.paymentMethod.create({
    data: {
      key, label: params.label.trim(), phone,
      isActive:  params.isActive  ?? true,
      sortOrder: params.sortOrder ?? 0,
    },
  });
}

export async function modifier(id: string, params: {
  label?: string; phone?: string; isActive?: boolean; sortOrder?: number;
}) {
  const actuel = await prisma.paymentMethod.findUnique({ where: { id } });
  if (!actuel) throw new Error('Méthode introuvable.');

  const label = params.label ?? actuel.label;
  const phone = _valider(label, params.phone ?? actuel.phone);

  // La clé n'est jamais modifiée : elle est stockée dans Transaction.paymentMethod
  // et dans les preuves d'abonnement. La renommer orphelinerait l'historique.
  return prisma.paymentMethod.update({
    where: { id },
    data: {
      label: label.trim(),
      phone,
      isActive:  params.isActive  ?? actuel.isActive,
      sortOrder: params.sortOrder ?? actuel.sortOrder,
    },
  });
}

export async function supprimer(id: string) {
  const m = await prisma.paymentMethod.findUnique({ where: { id } });
  if (!m) throw new Error('Méthode introuvable.');

  // Un numéro déjà utilisé n'est pas supprimable : son identifiant figure dans
  // des transactions et des preuves, qui deviendraient illisibles. On le
  // désactive — il disparaît de l'app, l'historique reste interprétable.
  const utilisee = await prisma.transaction.count({ where: { paymentMethod: m.key } });
  if (utilisee > 0) {
    await prisma.paymentMethod.update({ where: { id }, data: { isActive: false } });
    return { supprime: false, desactive: true, transactions: utilisee };
  }

  await prisma.paymentMethod.delete({ where: { id } });
  return { supprime: true, desactive: false, transactions: 0 };
}
