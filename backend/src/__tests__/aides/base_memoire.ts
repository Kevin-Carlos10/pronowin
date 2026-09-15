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

/**
 * Une relation, dans les deux sens que ces bancs emploient.
 *
 * `vers-un` : la ligne porte la clé étrangère (`pronostic.matchId` → `match`).
 * `plusieurs` : les lignes de la table visée portent la clé (`bankroll.bets`),
 * avec leurs propres `orderBy`, `take` et `include` imbriqués.
 */
type Lien =
  | { cle: string; vers: Map<string, any> }
  | {
      plusieurs: true;
      cleEtrangere: string;
      vers: Map<string, any>;
      liens?: Liens;
    };

type Liens = Record<string, Lien>;

export interface BaseMemoire {
  users:         Map<string, any>;
  referrals:     Map<string, any>;
  transactions:  Map<string, any>;
  subscriptions: Map<string, any>;
  iapPurchases:  Map<string, any>;
  bankrolls:     Map<string, any>;
  bankrollBets:  Map<string, any>;
  pronostics:    Map<string, any>;
  matches:       Map<string, any>;
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

      // Clé unique composée : Prisma la nomme `champA_champB` et passe un objet
      // portant chaque champ. Sans ce cas, la comparaison portait sur une
      // colonne inexistante et ne correspondait jamais — un contrôle de doublon
      // bâti dessus aurait semblé fonctionner tout en ne voyant rien.
      return correspond(ligne, c);
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
    bankrolls:     new Map(),
    bankrollBets:  new Map(),
    pronostics:    new Map(),
    matches:       new Map(),
  };

  /**
   * Résout les relations demandées par `include`.
   *
   * [liens] associe un nom de relation à la clé étrangère qui la porte **et** à
   * la table visée. La cible a d'abord été codée en dur sur `users` : toute
   * autre relation revenait alors `null` en silence, et un banc bâti dessus
   * mesurait une règle à qui on n'avait rien donné à lire.
   */
  const joindre = (ligne: any, include: any, liens: Liens): any => {
    if (!include) return ligne;
    const enrichie = { ...ligne };

    for (const nom of Object.keys(include)) {
      const lien = liens[nom];
      if (!include[nom] || !lien) continue;

      if ('plusieurs' in lien) {
        // Les options de l'include portent ici : `orderBy`, `take`, et les
        // relations imbriquées de chaque élément.
        const opts = typeof include[nom] === 'object' ? include[nom] : {};
        let liste = [...lien.vers.values()]
          .filter((x) => x[lien.cleEtrangere] === ligne.id);
        liste = ordonner(liste, opts.orderBy);
        if (typeof opts.take === 'number') liste = liste.slice(0, opts.take);
        enrichie[nom] = liste.map(
          (x) => joindre({ ...x }, opts.include, lien.liens ?? {}));
        continue;
      }

      const cible = lien.vers.get(ligne[lien.cle]);
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
  const table = (magasin: Map<string, any>, liens: Liens = {}) => {
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
      // `skip` et `take` sont honorés : sans eux, un banc portant sur une
      // lecture paginée lisait tout, et ne pouvait donc pas distinguer un
      // calcul fait sur la page affichée d'un calcul fait sur l'ensemble —
      // précisément ce que `resume_paris.test.ts` doit mesurer.
      findMany: async ({ where, include, orderBy, skip, take }: any = {}) => {
        let lignes = ordonner(filtrer(where), orderBy);
        if (typeof skip === 'number') lignes = lignes.slice(skip);
        if (typeof take === 'number') lignes = lignes.slice(0, take);
        return lignes.map((x) => joindre({ ...x }, include, liens));
      },
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
      groupBy: async ({ by, where, _count, _sum }: any) => {
        const groupes = new Map<string, any[]>();
        for (const l of filtrer(where)) {
          const cle = JSON.stringify((by as string[]).map((c) => l[c] ?? null));
          (groupes.get(cle) ?? groupes.set(cle, []).get(cle)!).push(l);
        }
        return [...groupes.entries()].map(([cle, lignes]) => {
          const valeurs = JSON.parse(cle) as any[];
          const g: any = {};
          (by as string[]).forEach((c, i) => { g[c] = valeurs[i]; });
          if (_count) g._count = { _all: lignes.length };
          if (_sum) {
            g._sum = {};
            for (const champ of Object.keys(_sum)) {
              g._sum[champ] = lignes.reduce((n, l) => n + (l[champ] ?? 0), 0);
            }
          }
          return g;
        });
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
    referral:     table(base.referrals, {
      referrer: { cle: 'referrerId', vers: base.users },
      referred: { cle: 'referredId', vers: base.users },
    }),
    transaction:  table(base.transactions, { user: { cle: 'userId', vers: base.users } }),
    subscription: table(base.subscriptions, { user: { cle: 'userId', vers: base.users } }),
    iapPurchase:  table(base.iapPurchases, { user: { cle: 'userId', vers: base.users } }),
    userBankroll: table(base.bankrolls, {
      user: { cle: 'userId', vers: base.users },
      bets: {
        plusieurs: true,
        cleEtrangere: 'bankrollId',
        vers: base.bankrollBets,
        liens: { pronostic: { cle: 'pronosticId', vers: base.pronostics } },
      },
    }),
    bankrollBet:  table(base.bankrollBets, {
      pronostic: { cle: 'pronosticId', vers: base.pronostics },
    }),
    pronostic:    table(base.pronostics, { match: { cle: 'matchId', vers: base.matches } }),
    match:        table(base.matches),
    // Sans isolation : voir la note en tête de fichier.
    $transaction: async (fn: any) => fn(prisma),
  };

  return { prisma, _base: base };
}
