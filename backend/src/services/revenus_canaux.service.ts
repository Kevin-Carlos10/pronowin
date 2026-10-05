import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';

/**
 * Les ventes par canal, la fidélité des abonnés, et l'export comptable.
 *
 * Chaque accès Premium accordé écrit une ligne `Subscription` : un paiement
 * Mobile Money validé, un achat ou un renouvellement App Store / Google Play,
 * un mois offert par un code partenaire, un geste de l'équipe. Les écrans de
 * revenus n'en lisaient que la somme : rien ne disait ce que rapporte chaque
 * canal, qui renouvelle et qui part, ni ne donnait au comptable la liste des
 * ventes d'un mois.
 *
 * ── Les achats de test ───────────────────────────────────────────────────────
 *
 * Un achat TestFlight — ou celui du testeur d'Apple pendant la vérification —
 * accorde un vrai accès et écrit donc une ligne comme une vente. Il ne l'est
 * pas : la ligne est rapprochée de son achat store (même store, même
 * échéance) et écartée si l'achat vient de l'environnement de test.
 */

export type Canal = 'mobile_money' | 'apple' | 'google' | 'partenaire' | 'offert' | 'autre';

export const CANAUX: Canal[] = ['mobile_money', 'apple', 'google', 'partenaire', 'offert', 'autre'];

/** Les canaux où l'abonné paie : ceux qui comptent dans le taux de renouvellement. */
export const CANAUX_PAYANTS: Canal[] = ['mobile_money', 'apple', 'google', 'autre'];

/** Au-delà de ce délai après la fin, un retour n'est plus un renouvellement. */
export const DELAI_RENOUVELLEMENT_JOURS = 7;

const JOUR = 86_400_000;

// Les clés des méthodes Mobile Money, au cas où une ligne les porterait
// directement plutôt que `manual_mobcash`.
const MOBILE_MONEY = /^(manual_mobcash|mobile_money|orange_money|moov_money|wave|mtn_money)$/;

export function canalDe(moyen: string): Canal {
  if (moyen === 'iap_apple')  return 'apple';
  if (moyen === 'iap_google') return 'google';
  if (moyen === 'manual_admin') return 'offert';
  // `xbet_promo` : le nom d'avant la généralisation aux autres partenaires.
  if (moyen.startsWith('promo_') || moyen === 'xbet_promo') return 'partenaire';
  if (MOBILE_MONEY.test(moyen)) return 'mobile_money';
  return 'autre';
}

export interface LigneAbonnement {
  id:            string;
  userId:        string;
  paymentMethod: string;
  amountPaid:    number | null;
  startDate:     Date;
  endDate:       Date;
  createdAt:     Date;
  promoCodeUsed?: string | null;
}

export interface AchatStore {
  userId:      string;
  store:       string;
  expiresAt:   Date;
  environment: string;
  payload:     any;
}

/** Le prix payé au store, quand il le dit (Apple : millièmes d'unité). */
export function prixStore(achat: Pick<AchatStore, 'store' | 'payload'> | undefined): { montant: number; devise: string } | null {
  const t = achat?.payload?.transaction;
  if (achat?.store === 'apple' && typeof t?.price === 'number' && typeof t?.currency === 'string') {
    return { montant: Math.round(t.price) / 1000, devise: t.currency };
  }
  return null;
}

/**
 * L'achat store d'une ligne d'abonnement.
 *
 * La ligne est écrite avec l'échéance que le store a donnée : elle la partage
 * avec son achat, à la milliseconde. Le compte d'abord ; sinon le store seul,
 * pour un abonnement passé depuis à un autre compte.
 */
export function rapprocheur(achats: AchatStore[]) {
  const parCompte = new Map<string, AchatStore>();
  const parStore  = new Map<string, AchatStore>();
  for (const a of achats) {
    parCompte.set(`${a.store}|${a.userId}|${a.expiresAt.getTime()}`, a);
    parStore.set(`${a.store}|${a.expiresAt.getTime()}`, a);
  }
  return (s: Pick<LigneAbonnement, 'paymentMethod' | 'userId' | 'endDate'>): AchatStore | undefined => {
    const c = canalDe(s.paymentMethod);
    if (c !== 'apple' && c !== 'google') return undefined;
    return parCompte.get(`${c}|${s.userId}|${s.endDate.getTime()}`)
        ?? parStore.get(`${c}|${s.endDate.getTime()}`);
  };
}

const estTest = (achat: AchatStore | undefined) => achat?.environment === 'Sandbox';

// ─── Ventes par canal ────────────────────────────────────────────────────────

export interface VentesCanal {
  canal:            Canal;
  ventes:           number;
  /** Premier abonnement du compte, tous canaux confondus. */
  nouveaux:         number;
  reabonnements:    number;
  /** Somme des montants connus, en FCFA. */
  fcfa:             number;
  montantsInconnus: number;
  /** Ce que les clients ont payé au store, par devise, avant commission. */
  store:            { devise: string; montant: number }[];
}

export function agregerVentes(
  ventes: LigneAbonnement[],
  premierAchat: Map<string, Date>,
  achatDe: (s: LigneAbonnement) => AchatStore | undefined,
) {
  const lignes = new Map<Canal, VentesCanal>(CANAUX.map((c) => [c, {
    canal: c, ventes: 0, nouveaux: 0, reabonnements: 0, fcfa: 0, montantsInconnus: 0, store: [],
  }]));
  let tests = 0;
  for (const v of ventes) {
    const achat = achatDe(v);
    if (estTest(achat)) { tests++; continue; }
    const l = lignes.get(canalDe(v.paymentMethod))!;
    l.ventes++;
    if (premierAchat.get(v.userId)?.getTime() === v.createdAt.getTime()) l.nouveaux++;
    else l.reabonnements++;
    // Un store ne donne pas de montant en FCFA : il n'est pas « inconnu »
    // pour autant quand son prix figure dans l'achat.
    const prix = prixStore(achat);
    if (prix) {
      const d = l.store.find((x) => x.devise === prix.devise)
        ?? (l.store.push({ devise: prix.devise, montant: 0 }), l.store[l.store.length - 1]);
      d.montant = Math.round((d.montant + prix.montant) * 100) / 100;
    } else if (v.amountPaid === null) {
      l.montantsInconnus++;
    } else {
      l.fcfa += v.amountPaid;
    }
  }
  const canaux = [...lignes.values()].filter((l) => l.ventes > 0);
  return {
    canaux,
    total: {
      ventes:   canaux.reduce((s, l) => s + l.ventes, 0),
      nouveaux: canaux.reduce((s, l) => s + l.nouveaux, 0),
      fcfa:     Math.round(canaux.reduce((s, l) => s + l.fcfa, 0)),
    },
    tests,
  };
}

/** Les achats store utiles au rapprochement des lignes [lignes]. */
async function achatsPour(lignes: LigneAbonnement[]): Promise<AchatStore[]> {
  const echeances = lignes
    .filter((l) => ['apple', 'google'].includes(canalDe(l.paymentMethod)))
    .map((l) => l.endDate);
  if (!echeances.length) return [];
  // Au-delà d'un millier d'échéances, lire la table entière : elle ne compte
  // que les achats store, et une liste `in` de cette taille coûte plus cher.
  return prisma.iapPurchase.findMany({
    where:  echeances.length <= 1000 ? { expiresAt: { in: echeances } } : {},
    select: { userId: true, store: true, expiresAt: true, environment: true, payload: true },
  });
}

export async function ventesParCanal(params: { jours: number }) {
  const jours = Math.max(1, Math.min(params.jours, 3650));
  const debut = new Date(Date.now() - jours * JOUR);
  const ventes = await prisma.subscription.findMany({
    where:  { createdAt: { gte: debut } },
    select: { id: true, userId: true, paymentMethod: true, amountPaid: true,
              startDate: true, endDate: true, createdAt: true },
  });
  const comptes = [...new Set(ventes.map((v) => v.userId))];
  const [historique, achats] = await Promise.all([
    comptes.length
      ? prisma.subscription.findMany({ where: { userId: { in: comptes } }, select: { userId: true, createdAt: true } })
      : Promise.resolve([] as { userId: string; createdAt: Date }[]),
    achatsPour(ventes),
  ]);
  const premierAchat = new Map<string, Date>();
  for (const h of historique) {
    const p = premierAchat.get(h.userId);
    if (!p || h.createdAt < p) premierAchat.set(h.userId, h.createdAt);
  }
  return { jours, ...agregerVentes(ventes, premierAchat, rapprocheur(achats)) };
}

// ─── Fidélité ────────────────────────────────────────────────────────────────

/**
 * Une fin d'abonnement est « renouvelée » si un autre abonnement du compte
 * prend le relais : il court au-delà de cette fin, et il a commencé au plus
 * tard DELAI_RENOUVELLEMENT_JOURS après elle.
 *
 * La même règle couvre les trois cas réels : le réabonnement anticipé (pris
 * avant la fin, il prolonge l'échéance), le réabonnement en retard de
 * quelques jours (Mobile Money payé après coup), et l'abonnement plus long
 * qui couvrait déjà la période (un annuel Mobile Money pendant un mensuel
 * store).
 */
export function estRenouvele(s: LigneAbonnement, autres: LigneAbonnement[]): boolean {
  const fin = s.endDate.getTime();
  return autres.some((a) => a !== s && a.endDate.getTime() > fin
    && a.startDate.getTime() <= fin + DELAI_RENOUVELLEMENT_JOURS * JOUR);
}

export interface Taux { canal: Canal | 'global'; fins: number; renouvelees: number; taux: number | null }

const taux = (canal: Taux['canal'], fins: number, renouvelees: number): Taux =>
  ({ canal, fins, renouvelees, taux: fins ? Math.round((renouvelees / fins) * 100) : null });

export function analyserFidelite(
  abonnements: LigneAbonnement[],
  maintenant = new Date(),
  fenetreJours = 90,
) {
  const parCompte = new Map<string, LigneAbonnement[]>();
  for (const a of abonnements) {
    (parCompte.get(a.userId) ?? parCompte.set(a.userId, []).get(a.userId)!).push(a);
  }

  const t = maintenant.getTime();
  const delai = DELAI_RENOUVELLEMENT_JOURS * JOUR;

  // Les fins dont l'issue est connue : le délai de renouvellement est écoulé.
  const fins = abonnements
    .filter((a) => a.endDate.getTime() + delai <= t)
    .map((a) => ({ a, renouvele: estRenouvele(a, parCompte.get(a.userId)!) }));

  const recentes = fins.filter(({ a }) => a.endDate.getTime() >= t - fenetreJours * JOUR);
  const parCanal = CANAUX.map((c) => {
    const f = recentes.filter(({ a }) => canalDe(a.paymentMethod) === c);
    return taux(c, f.length, f.filter((x) => x.renouvele).length);
  }).filter((x) => x.fins > 0);
  const payantes = recentes.filter(({ a }) => CANAUX_PAYANTS.includes(canalDe(a.paymentMethod)));

  // Six derniers mois, par mois de fin — payants seulement.
  const mensuel = Array.from({ length: 6 }, (_, i) => {
    const d = new Date(Date.UTC(maintenant.getUTCFullYear(), maintenant.getUTCMonth() - 5 + i, 1));
    const f = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1));
    const dans = fins.filter(({ a }) => CANAUX_PAYANTS.includes(canalDe(a.paymentMethod))
      && a.endDate >= d && a.endDate < f);
    const { fins: n, renouvelees, taux: pct } = taux('global', dans.length, dans.filter((x) => x.renouvele).length);
    // Des fins du mois attendent encore leur issue : le taux n'est pas définitif.
    return { mois: d.toISOString().slice(0, 7), fins: n, renouvelees, taux: pct, enCours: f.getTime() > t - delai };
  });

  // Par compte : l'échéance de son dernier abonnement, et ce qu'il a payé.
  const comptes = [...parCompte.entries()].map(([userId, liste]) => {
    const dernier = liste.reduce((m, a) => (a.endDate > m.endDate ? a : m), liste[0]);
    const payes = liste.filter((a) => CANAUX_PAYANTS.includes(canalDe(a.paymentMethod)));
    return {
      userId,
      canal:        canalDe(dernier.paymentMethod),
      finLe:        dernier.endDate,
      paiements:    payes.length,
      totalFcfa:    Math.round(payes.reduce((s, a) => s + (a.amountPaid ?? 0), 0)),
      abonneDepuis: liste.reduce((m, a) => (a.startDate < m ? a.startDate : m), liste[0].startDate),
    };
  });

  return {
    fenetreJours,
    delaiJours: DELAI_RENOUVELLEMENT_JOURS,
    global: taux('global', payantes.length, payantes.filter((x) => x.renouvele).length),
    parCanal,
    mensuel,
    // Premium qui s'arrête dans la semaine : un abonné Mobile Money doit
    // repayer lui-même, c'est le moment de le lui rappeler.
    bientot: comptes.filter((c) => c.finLe.getTime() > t && c.finLe.getTime() <= t + 7 * JOUR)
      .sort((a, b) => a.finLe.getTime() - b.finLe.getTime()),
    // Premium terminé ces 30 derniers jours, sans suite.
    partis: comptes.filter((c) => c.finLe.getTime() <= t && c.finLe.getTime() > t - 30 * JOUR)
      .sort((a, b) => b.finLe.getTime() - a.finLe.getTime()),
  };
}

export async function fideliteAbonnes(params: { jours?: number } = {}) {
  const fenetre = [30, 90, 365].includes(params.jours ?? 0) ? params.jours! : 90;
  const abonnements = await prisma.subscription.findMany({
    select: { id: true, userId: true, paymentMethod: true, amountPaid: true,
              startDate: true, endDate: true, createdAt: true },
  });
  const achatDe = rapprocheur(await achatsPour(abonnements));
  const reels = abonnements.filter((a) => !estTest(achatDe(a)));
  const r = analyserFidelite(reels, new Date(), fenetre);

  // Les comptes des deux listes : pseudo, et rien d'autre. Le contact se lit
  // sur la fiche du compte, sous la permission « utilisateurs ».
  const ids = [...new Set([...r.bientot, ...r.partis].map((c) => c.userId))];
  const users = ids.length
    ? await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, pseudo: true, deletedAt: true } })
    : [];
  const pseudo = new Map(users.map((u) => [u.id, u]));
  const habiller = (l: typeof r.partis) => l
    .filter((c) => pseudo.has(c.userId) && pseudo.get(c.userId)!.deletedAt === null)
    .slice(0, 200)
    .map((c) => ({ ...c, pseudo: pseudo.get(c.userId)!.pseudo,
                   finLe: c.finLe.toISOString(), abonneDepuis: c.abonneDepuis.toISOString() }));

  return { ...r, bientot: habiller(r.bientot), partis: habiller(r.partis) };
}

// ─── Export comptable ────────────────────────────────────────────────────────

/** Les ventes d'un mois (AAAA-MM, heure universelle), une ligne par vente. */
export async function exportComptable(mois: string) {
  const m = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(mois);
  if (!m) throw new ErreurMetier('Mois attendu au format AAAA-MM.', 422);
  const debut = new Date(Date.UTC(+m[1], +m[2] - 1, 1));
  const fin   = new Date(Date.UTC(+m[1], +m[2], 1));

  const ventes = await prisma.subscription.findMany({
    where:   { createdAt: { gte: debut, lt: fin } },
    orderBy: { createdAt: 'asc' },
    select:  { id: true, userId: true, paymentMethod: true, amountPaid: true, startDate: true,
               endDate: true, createdAt: true, promoCodeUsed: true,
               user: { select: { pseudo: true } } },
  });
  const achatDe = rapprocheur(await achatsPour(ventes));

  const lignes = ventes.map((v) => {
    const achat = achatDe(v);
    const prix = prixStore(achat);
    const canal = canalDe(v.paymentMethod);
    return {
      reference:   v.id,
      date:        v.createdAt.toISOString(),
      compte:      v.user.pseudo,
      compteId:    v.userId,
      canal,
      moyen:       v.paymentMethod,
      test:        estTest(achat),
      debut:       v.startDate.toISOString(),
      fin:         v.endDate.toISOString(),
      jours:       Math.round((v.endDate.getTime() - v.startDate.getTime()) / JOUR),
      // Un store ne paie pas en FCFA : son montant est dans sa devise.
      montantFcfa: canal === 'apple' || canal === 'google' ? null : v.amountPaid,
      montantStore: prix?.montant ?? null,
      devise:      prix?.devise ?? null,
      codePromo:   v.promoCodeUsed,
    };
  });
  return { mois, lignes };
}
