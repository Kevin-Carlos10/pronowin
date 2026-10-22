import fs from 'fs';
import path from 'path';

let preuves: any[] = [];
let filtreRecu: any = null;
const envois: Array<{ sujet: string; corps: string }> = [];
let envoiReussi = true;

jest.mock('../lib/prisma', () => ({
  prisma: {
    subscriptionProof: {
      findMany: jest.fn(async (args: any) => {
        filtreRecu = args.where;
        return preuves;
      }),
    },
  },
}));

jest.mock('../services/email.service', () => ({
  envoyerAlerteAdmin: jest.fn(async (sujet: string, corps: string) => {
    envois.push({ sujet, corps });
    return envoiReussi;
  }),
}));

import {
  attenteEnHeures,
  achatsEnRetard,
  corpsAlerte,
  signalerAchatsEnRetard,
  SEUIL_ATTENTE_HEURES,
  INTERVALLE_CONTROLE_MS,
} from '../services/alerte_achats.service';

/**
 * Un achat payé et jamais activé ne doit pas passer inaperçu.
 *
 * ── Ce que rien ne couvrait ───────────────────────────────────────────────
 *
 * La validation des preuves est manuelle. Rien ne relançait, rien n'expirait,
 * rien ne signalait : une preuve restée `pending` y restait indéfiniment, avec
 * de l'argent déjà encaissé en face.
 *
 * Aucun journal d'erreur ne s'en plaignait, aucun service ne tombait. C'est
 * une panne invisible par construction — la seule chose qui puisse la révéler
 * est un contrôle qui la cherche.
 *
 * ── Ce que ce banc tient ──────────────────────────────────────────────────
 *
 * Que le contrôle regarde la bonne chose (`pending`, et assez ancien), qu'il
 * se taise quand tout va bien, et qu'il parle quand il le faut. Les trois
 * comptent : un contrôle qui alerte à tort finit par n'être plus lu, ce qui
 * revient à ne pas alerter du tout.
 */
describe('attente, en heures', () => {
  const t = (h: number) => new Date(Date.UTC(2026, 8, 21, 12, 0, 0) - h * 3_600_000);
  const maintenant = new Date(Date.UTC(2026, 8, 21, 12, 0, 0));

  it('compte les heures écoulées', () => {
    expect(attenteEnHeures(t(7), maintenant)).toBe(7);
  });

  it('arrondit vers le bas', () => {
    const presque = new Date(maintenant.getTime() - (3 * 3_600_000 + 59 * 60_000));
    expect(attenteEnHeures(presque, maintenant)).toBe(3);
  });

  it('ne rend jamais de négatif pour une date du présent', () => {
    expect(attenteEnHeures(maintenant, maintenant)).toBe(0);
  });
});

describe('ce que le contrôle va chercher', () => {
  const maintenant = new Date(Date.UTC(2026, 8, 21, 12, 0, 0));

  beforeEach(() => {
    preuves = [];
    filtreRecu = null;
  });

  it('ne regarde que les preuves encore en attente', async () => {
    await achatsEnRetard(maintenant);
    expect(filtreRecu.status).toBe('pending');
  });

  it('et seulement celles dépassant le seuil', async () => {
    await achatsEnRetard(maintenant);
    const limite = filtreRecu.createdAt.lt as Date;
    expect(maintenant.getTime() - limite.getTime()).toBe(INTERVALLE_CONTROLE_MS);
    expect(SEUIL_ATTENTE_HEURES).toBeGreaterThan(2);
  });

  it('désigne le compte par son pseudo', async () => {
    preuves = [{
      id: 'p1', type: 'payment_screenshot',
      createdAt: new Date(maintenant.getTime() - 9 * 3_600_000),
      user: { pseudo: 'Parieur_XY', phoneNumber: '+22670000000' },
    }];
    const r = await achatsEnRetard(maintenant);
    expect(r[0].compte).toBe('Parieur_XY');
    expect(r[0].heures).toBe(9);
  });

  it('à défaut, par le numéro qui a servi à payer', async () => {
    preuves = [{
      id: 'p2', type: 'payment_screenshot',
      createdAt: new Date(maintenant.getTime() - 9 * 3_600_000),
      user: { pseudo: null, phoneNumber: '+22670000000' },
    }];
    const r = await achatsEnRetard(maintenant);
    expect(r[0].compte).toBe('+22670000000');
  });
});

describe('quand alerter, et quand se taire', () => {
  const maintenant = new Date(Date.UTC(2026, 8, 21, 12, 0, 0));

  beforeEach(() => {
    preuves = [];
    envois.length = 0;
    envoiReussi = true;
  });

  it('rien en attente : aucun courriel', async () => {
    const r = await signalerAchatsEnRetard(maintenant);
    expect(r).toEqual({ enRetard: 0, alerteEnvoyee: false });
    expect(envois).toHaveLength(0);
  });

  it("une alerte quotidienne « tout va bien » cesserait d'être lue", async () => {
    // Le meme controle, formule autrement : le silence est le comportement
    // normal. C'est ce qui rend un courriel recu significatif.
    await signalerAchatsEnRetard(maintenant);
    await signalerAchatsEnRetard(maintenant);
    expect(envois).toHaveLength(0);
  });

  it('un achat en retard : un courriel, nommant la personne', async () => {
    preuves = [{
      id: 'p1', type: 'payment_screenshot',
      createdAt: new Date(maintenant.getTime() - 14 * 3_600_000),
      user: { pseudo: 'Parieur_XY', phoneNumber: null },
    }];

    const r = await signalerAchatsEnRetard(maintenant);
    expect(r.enRetard).toBe(1);
    expect(r.alerteEnvoyee).toBe(true);
    expect(envois).toHaveLength(1);
    expect(envois[0].corps).toContain('Parieur_XY');
    expect(envois[0].corps).toContain('14 h');
  });

  it("un envoi impossible est compté, pas avalé", async () => {
    // Si SMTP tombe, l'alerte n'est pas partie. Le dire est la seule chose
    // qui distingue « rien a signaler » de « je n'ai pas pu le signaler ».
    envoiReussi = false;
    preuves = [{
      id: 'p1', type: 'payment_screenshot',
      createdAt: new Date(maintenant.getTime() - 14 * 3_600_000),
      user: { pseudo: 'Parieur_XY', phoneNumber: null },
    }];

    const r = await signalerAchatsEnRetard(maintenant);
    expect(r.enRetard).toBe(1);
    expect(r.alerteEnvoyee).toBe(false);
  });

  it('le corps dit ce qui est en jeu et où aller', () => {
    const corps = corpsAlerte([
      { id: 'p1', type: 'payment_screenshot', heures: 14, compte: 'A' },
      { id: 'p2', type: 'xbet_account_screenshot', heures: 30, compte: 'B' },
    ]);
    expect(corps).toContain('2 achat(s)');
    expect(corps).toContain('/admin/abonnements');
    expect(corps).toContain('ont payé');
  });
});

describe('le contrôle est réellement branché', () => {
  // Les tâches planifiées vivent dans taches.ts depuis le constat P1 ; l'API
  // et le processus pronowin-taches les lancent par demarrerTaches().
  const lire = (fichier: string) => fs
    .readFileSync(path.join(__dirname, '..', fichier), 'utf8')
    .split('\n')
    .filter((l) => !l.trimStart().startsWith('//') && !l.trimStart().startsWith('*'))
    .join('\n');
  const index = lire('taches.ts');

  it('taches.ts le planifie', () => {
    expect(index).toContain('signalerAchatsEnRetard');
    expect(index).toContain('setInterval(runAchatsEnRetard');
  });

  it('l\'API et le processus des tâches lancent bien taches.ts', () => {
    expect(lire('index.ts')).toMatch(/arreterTaches = demarrerTaches\(\)/);
    expect(lire('taches_processus.ts')).toMatch(/demarrerTaches\(\)/);
  });

  it("il ne dépend pas de la clé API football", () => {
    // Le defaut qu'on evite : range dans le bloc `if (API_FOOTBALL_KEY)`, le
    // controle disparaitrait avec cette cle sans que rien ne le dise. Une
    // alerte muette est pire que pas d'alerte : on croit etre couvert.
    const bloc = index.indexOf('if (process.env.API_FOOTBALL_KEY)');
    // L'avertissement du bloc « sinon » nomme désormais la bonne variable
    // (il annonçait FOOTBALL_DATA_API_KEY, qui n'est lue nulle part).
    const finBloc = index.indexOf('API_FOOTBALL_KEY manquante');
    const appel = index.indexOf('setInterval(runAchatsEnRetard');

    expect(bloc).toBeGreaterThan(-1);
    expect(finBloc).toBeGreaterThan(bloc);
    expect(appel).toBeGreaterThan(finBloc);
  });

  it("le rappel d'expiration Premium non plus", () => {
    // Il était rangé dans le bloc football : sans cette clé, plus aucun
    // abonné n'était prévenu de la fin de son accès (constat I13).
    const finBloc = index.indexOf('API_FOOTBALL_KEY manquante');
    const appel = index.indexOf('setInterval(runExpiryReminder');
    expect(appel).toBeGreaterThan(finBloc);
  });
});
