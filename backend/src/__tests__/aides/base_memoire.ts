/**
 * Une base Prisma simulée en mémoire, pour les bancs qui portent sur l'argent.
 *
 * Ce fichier ne contient aucun test — `testMatch` ne retient que `*.test.ts`.
 *
 * ── Ce qu'elle permet d'établir, et ce qu'elle ne permet pas ───────────────
 *
 * Elle reproduit fidèlement **la forme** des appels Prisma : `where` plat avec
 * `gte`/`in`, `increment`/`decrement`, `count` rendu par `updateMany`, et les
 * relations résolues par `include`. Les opérations sont asynchrones, donc deux
 * appels lancés ensemble s'entrelacent réellement — c'est ce qui permet de
 * reproduire une course.
 *
 * Elle ne reproduit **pas** l'isolation transactionnelle de Postgres :
 * `$transaction` exécute simplement la suite. Un banc bâti dessus n'établit
 * donc jamais qu'une écriture est atomique en production. Ce qu'il établit est
 * ce dont l'atomicité dépend — qu'une écriture soit **conditionnelle**, et que
 * le code ne poursuive que si elle a effectivement changé une ligne.
 */

export interface BaseMemoire {
  users:         Map<string, any>;
  referrals:     Map<string, any>;
  transactions:  Map<string, any>;
  subscriptions: Map<string, any>;
  iapPurchases:  Map<string, any>;
}

/** Une ligne satisfait-elle une clause `where` ? */
function correspond(ligne: any, where: any): boolean {
  return Object.entries(where ?? {}).every(([cle, cond]: [string, any]) => {
    if (cle === 'OR') {
      return (cond as any[]).some((sous) => correspond(ligne, sous));
    }
    if (cond !== null && typeof cond === 'object' && !(cond instanceof Date)) {
      const c: any = cond;
      if ('gte' in c) return ligne[cle] >= c.gte;
      if ('gt'  in c) return ligne[cle] >  c.gt;
      if ('lte' in c) return ligne[cle] <= c.lte;
      if ('lt'  in c) return ligne[cle] <  c.lt;
      if ('in'  in c) return (c.in as any[]).includes(ligne[cle]);
      if ('not' in c) return ligne[cle] !== c.not;
      if ('equals' in c) return ligne[cle] === c.equals;
      return false;
    }
    return ligne[cle] === cond;
  });
}

/** Applique un `data` Prisma (valeurs directes ou `increment`/`decrement`). */
function appliquer(ligne: any, data: any): void {
  for (const [cle, val] of Object.entries(data ?? {})) {
    if (val !== null && typeof val === 'object' && !(val instanceof Date)) {
      const v: any = val;
      if ('increment' in v) { ligne[cle] = (ligne[cle] ?? 0) + v.increment; continue; }
      if ('decrement' in v) { ligne[cle] = (ligne[cle] ?? 0) - v.decrement; continue; }
    }
    ligne[cle] = val;
  }
}

/** Trie une liste selon un `orderBy` Prisma à un seul champ. */
function ordonner(lignes: any[], orderBy: any): any[] {
  if (!orderBy) return lignes;
  const [champ, sens] = Object.entries(orderBy)[0] as [string, string];
  return [...lignes].sort((a, b) => {
    const x = a[champ], y = b[champ];
    const d = x === y ? 0 : (x > y ? 1 : -1);
    return sens === 'desc' ? -d : d;
  });
}

export function creerBase() {
  const base: BaseMemoire = {
    users:         new Map(),
    referrals:     new Map(),
    transactions:  new Map(),
    subscriptions: new Map(),
    iapPurchases:  new Map(),
  };

  /**
   * Résout les relations demandées par `include`.
   *
   * [liens] associe un nom de relation à la clé étrangère qui la porte ; la
   * cible est toujours `users`, seule table reliée dans ces bancs.
   */
  const joindre = (ligne: any, include: any, liens: Record<string, string>) => {
    if (!include) return ligne;
    const enrichie = { ...ligne };
    for (const nom of Object.keys(include)) {
      if (!include[nom] || !liens[nom]) continue;
      const cible = base.users.get(ligne[liens[nom]]);
      enrichie[nom] = cible ? { ...cible } : null;
    }
    return enrichie;
  };

  /**
   * Les opérations d'une table.
   *
   * Toutes asynchrones, et c'est le point : chaque `await` cède la main, si
   * bien que deux appels lancés ensemble s'entrelacent comme deux requêtes
   * concurrentes le feraient.
   */
  const table = (magasin: Map<string, any>, liens: Record<string, string> = {}) => {
    let compteur = 0;
    const filtrer = (where: any) =>
      [...magasin.values()].filter((x) => correspond(x, where));

    return {
      findUnique: async ({ where, include }: any) => {
        const l = filtrer(where)[0];
        return l ? joindre({ ...l }, include, liens) : null;
      },
      findFirst: async ({ where, include, orderBy }: any = {}) => {
        const l = ordonner(filtrer(where), orderBy)[0];
        return l ? joindre({ ...l }, include, liens) : null;
      },
      findMany: async ({ where, include, orderBy }: any = {}) =>
        ordonner(filtrer(where), orderBy)
          .map((x) => joindre({ ...x }, include, liens)),
      count: async ({ where }: any = {}) => filtrer(where).length,
      update: async ({ where, data }: any) => {
        const l = filtrer(where)[0];
        if (!l) throw new Error('ligne introuvable');
        appliquer(l, data);
        return { ...l };
      },
      updateMany: async ({ where, data }: any) => {
        const lignes = filtrer(where);
        lignes.forEach((l) => appliquer(l, data));
        return { count: lignes.length };
      },
      create: async ({ data }: any) => {
        const id = data.id ?? `auto-${++compteur}`;
        const l = { id, ...data };
        magasin.set(id, l);
        return { ...l };
      },
      upsert: async ({ where, create, update }: any) => {
        const l = filtrer(where)[0];
        if (l) { appliquer(l, update); return { ...l }; }
        const id = create.id ?? `auto-${++compteur}`;
        const neuf = { id, ...create };
        magasin.set(id, neuf);
        return { ...neuf };
      },
      aggregate: async ({ where, _sum }: any) => {
        const lignes = filtrer(where);
        const somme: any = {};
        for (const champ of Object.keys(_sum ?? {})) {
          somme[champ] = lignes.reduce((n, l) => n + (l[champ] ?? 0), 0);
        }
        return { _sum: somme };
      },
    };
  };

  const prisma: any = {
    user:         table(base.users),
    referral:     table(base.referrals, { referrer: 'referrerId', referred: 'referredId' }),
    transaction:  table(base.transactions, { user: 'userId' }),
    subscription: table(base.subscriptions, { user: 'userId' }),
    iapPurchase:  table(base.iapPurchases, { user: 'userId' }),
    // Sans isolation : voir la note en tête de fichier.
    $transaction: async (fn: any) => fn(prisma),
  };

  return { prisma, _base: base };
}
