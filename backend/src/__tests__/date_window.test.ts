/**
 * Découpage des journées selon le fuseau du client.
 *
 * `buildDateWhere` est privée : on la teste à travers une réimplémentation
 * fidèle de sa règle, pour figer le contrat plutôt que l'implémentation.
 * Ce qui compte ici, c'est qu'un match de fin de soirée tombe du même côté de
 * minuit pour le serveur et pour l'application — c'est leur désaccord qui
 * faisait afficher « 6 matchs en direct » au-dessus de 10 cartes.
 */

/** Minuit du jour de l'utilisateur contenant `instant`, exprimé en UTC. */
function minuitLocal(instant: Date, decalageMin: number): Date {
  const decalage = decalageMin * 60000;
  const local = new Date(instant.getTime() + decalage);
  const jour = Date.UTC(
    local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate());
  return new Date(jour - decalage);
}

/** Fenêtre [début, fin[ d'un jour `YYYY-MM-DD` dans le fuseau du client. */
function fenetreDuJour(jour: string, decalageMin: number): [Date, Date] {
  const debut = new Date(
    new Date(jour + 'T00:00:00.000Z').getTime() - decalageMin * 60000);
  return [debut, new Date(debut.getTime() + 86400000)];
}

const dans = (d: Date, [a, b]: [Date, Date]) =>
  d.getTime() >= a.getTime() && d.getTime() < b.getTime();

describe('fenêtre de jour calée sur le fuseau du client', () => {
  it('UTC+1 : la journée commence une heure avant minuit UTC', () => {
    const [debut, fin] = fenetreDuJour('2026-08-11', 60);
    expect(debut.toISOString()).toBe('2026-08-10T23:00:00.000Z');
    expect(fin.toISOString()).toBe('2026-08-11T23:00:00.000Z');
  });

  it('UTC-3 : elle commence trois heures après', () => {
    const [debut, fin] = fenetreDuJour('2026-08-11', -180);
    expect(debut.toISOString()).toBe('2026-08-11T03:00:00.000Z');
    expect(fin.toISOString()).toBe('2026-08-12T03:00:00.000Z');
  });

  it('UTC+0 : identique au découpage historique', () => {
    const [debut, fin] = fenetreDuJour('2026-08-11', 0);
    expect(debut.toISOString()).toBe('2026-08-11T00:00:00.000Z');
    expect(fin.toISOString()).toBe('2026-08-12T00:00:00.000Z');
  });

  // Le cas qui posait problème : coup d'envoi à 00h30 heure locale (UTC+1),
  // soit 23h30 Z la veille. Le serveur en UTC le rangeait le 11, l'app le 12.
  it('range un coup d’envoi de 00h30 UTC+1 dans la bonne journée', () => {
    const coupDEnvoi = new Date('2026-08-11T23:30:00.000Z'); // = 12/08 00h30 locale

    expect(dans(coupDEnvoi, fenetreDuJour('2026-08-12', 60))).toBe(true);
    expect(dans(coupDEnvoi, fenetreDuJour('2026-08-11', 60))).toBe(false);

    // Ancien comportement, fuseau serveur en UTC : rangé la veille — c'est
    // exactement l'écart que voyait l'utilisateur entre le compteur et la liste.
    expect(dans(coupDEnvoi, fenetreDuJour('2026-08-11', 0))).toBe(true);
  });

  it('un match de 22h locale reste dans sa journée quel que soit le fuseau', () => {
    for (const decalage of [-300, -60, 0, 60, 180, 330]) {
      const vingtDeuxHeuresLocales = new Date(
        new Date('2026-08-11T22:00:00.000Z').getTime() - decalage * 60000);
      expect(dans(vingtDeuxHeuresLocales, fenetreDuJour('2026-08-11', decalage)))
        .toBe(true);
    }
  });
});

describe('minuit local', () => {
  it('recule d’un jour quand l’instant est avant minuit local', () => {
    // 22h30 Z = 23h30 locale le 11 en UTC+1 → minuit du 11.
    const m = minuitLocal(new Date('2026-08-11T22:30:00.000Z'), 60);
    expect(m.toISOString()).toBe('2026-08-10T23:00:00.000Z');
  });

  it('bascule au jour suivant après minuit local', () => {
    // 23h30 Z = 00h30 locale le 12 en UTC+1 → minuit du 12.
    const m = minuitLocal(new Date('2026-08-11T23:30:00.000Z'), 60);
    expect(m.toISOString()).toBe('2026-08-11T23:00:00.000Z');
  });

  it('gère les fuseaux à demi-heure (Inde, UTC+5:30)', () => {
    const m = minuitLocal(new Date('2026-08-11T20:00:00.000Z'), 330);
    expect(m.toISOString()).toBe('2026-08-11T18:30:00.000Z');
  });
});
