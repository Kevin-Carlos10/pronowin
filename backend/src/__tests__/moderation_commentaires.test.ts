/**
 * Signaler, bloquer, trancher (règle 1.2 de l'App Store).
 *
 * Banc sur la base de développement : un match, un pronostic, quatre membres.
 * L'alerte courriel est simulée — on vérifie qu'elle part au bon moment.
 */
const mockAlertes: string[] = [];
jest.mock('../services/email.service', () => ({
  envoyerAlerteAdmin: async (sujet: string) => { mockAlertes.push(sujet); return true; },
}));

import { prisma } from '../lib/prisma';
import { CommentsService } from '../services/comments.service';
import { ModerationService, SEUIL_MASQUAGE } from '../services/moderation.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const marque = `banc-moderation-${Date.now()}`;
const commentaires = new CommentsService();
const moderation = new ModerationService();
const membres: Record<'auteur' | 'a' | 'b' | 'c', string> = { auteur: '', a: '', b: '', c: '' };
let pronosticId = '';
let matchId = '';
let adminId = '';

const visibles = async (lecteur: string) =>
  (await commentaires.getComments(pronosticId, lecteur)).comments.map((c: any) => c.content);

beforeAll(async () => {
  if (!BASE_LOCALE) return;
  for (const k of Object.keys(membres) as (keyof typeof membres)[]) {
    const u = await prisma.user.create({
      data: { pseudo: `${marque}-${k}`, referralCode: `${marque.slice(-8)}${k}`.toUpperCase().slice(0, 16) },
    });
    membres[k] = u.id;
  }
  const admin = await prisma.admin.create({
    data: { email: `${marque}@banc.invalid`, passwordHash: 'x', name: 'Banc' },
  });
  adminId = admin.id;
  const match = await prisma.match.create({
    data: {
      externalId: Math.floor(Date.now() / 1000), league: 'Banc', leagueCode: 'BANC',
      homeTeam: 'Domicile', awayTeam: 'Extérieur', matchDate: new Date(),
    },
  });
  matchId = match.id;
  const prono = await prisma.pronostic.create({
    data: {
      matchId, analystId: adminId, predictionType: 'win1', predictionLabel: 'Domicile',
      oddsRecommended: 1.8, confidenceScore: 3,
    },
  });
  pronosticId = prono.id;
});

beforeEach(() => { mockAlertes.length = 0; });

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.pronostic.deleteMany({ where: { id: pronosticId } }); // commentaires et signalements : en cascade
  await prisma.match.deleteMany({ where: { id: matchId } });
  await prisma.admin.deleteMany({ where: { id: adminId } });
  await prisma.user.deleteMany({ where: { id: { in: Object.values(membres).filter(Boolean) } } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('modération des commentaires', () => {
  let commentaireId = '';

  it('le filtre refuse une injure à la publication, avec un code que l\'app traduit', async () => {
    await expect(commentaires.postComment(pronosticId, membres.auteur, 'Quel connard cet arbitre'))
      .rejects.toMatchObject({ statut: 422, code: 'TERMES_INTERDITS' });
    const c = await commentaires.postComment(pronosticId, membres.auteur, 'Analyse discutable à mon avis');
    commentaireId = c.id;
    expect(await visibles(membres.a)).toEqual(['Analyse discutable à mon avis']);
  });

  it('on ne signale pas son propre commentaire, ni deux fois le même', async () => {
    await expect(moderation.signaler(membres.auteur, commentaireId, 'spam'))
      .rejects.toMatchObject({ code: 'SIGNALEMENT_SOI' });
    await moderation.signaler(membres.a, commentaireId, 'insulte');
    expect(mockAlertes).toEqual(['[PronoWin] Commentaire signalé']);
    await expect(moderation.signaler(membres.a, commentaireId, 'spam'))
      .rejects.toMatchObject({ statut: 409, code: 'DEJA_SIGNALE' });
  });

  it(`au ${SEUIL_MASQUAGE}e signalement, le commentaire est retiré en attendant la décision`, async () => {
    await moderation.signaler(membres.b, commentaireId, 'insulte');
    expect(await visibles(membres.c)).toHaveLength(1);
    expect(mockAlertes).toEqual([]); // ni premier signalement, ni masquage

    const r = await moderation.signaler(membres.c, commentaireId, 'haine', 'propos visant un joueur');
    expect(r.masque).toBe(true);
    expect(mockAlertes).toEqual([`[PronoWin] Commentaire masqué d'office (${SEUIL_MASQUAGE} signalements)`]);
    expect(await visibles(membres.a)).toEqual([]);
    expect(await moderation.aTraiter()).toBeGreaterThanOrEqual(1);
  });

  it('le panneau voit le commentaire et ses signalements', async () => {
    const { data } = await moderation.commentairesSignales('en_attente', 1, 100);
    const fiche = data.find((d) => d.comment_id === commentaireId)!;
    expect(fiche.masque).toBe(true);
    expect(fiche.auteur.pseudo).toBe(`${marque}-auteur`);
    expect(fiche.match).toBe('Domicile – Extérieur');
    expect(fiche.signalements.map((s) => s.motif).sort()).toEqual(['haine', 'insulte', 'insulte']);
  });

  it('rejeter rend le commentaire ; une seconde décision est refusée', async () => {
    await moderation.trancher(commentaireId, 'rejeter', 'Banc');
    expect(await visibles(membres.a)).toEqual(['Analyse discutable à mon avis']);
    const statuts = await prisma.signalementCommentaire.findMany({ where: { commentId: commentaireId } });
    expect(statuts.every((s) => s.statut === 'rejete' && s.traitePar === 'Banc')).toBe(true);
    await expect(moderation.trancher(commentaireId, 'retenir', 'Banc'))
      .rejects.toMatchObject({ statut: 409, code: 'DEJA_TRAITE' });
  });

  it('retenir retire le commentaire pour tous', async () => {
    const autre = await commentaires.postComment(pronosticId, membres.auteur, 'Un autre avis tranché');
    await moderation.signaler(membres.a, autre.id, 'spam');
    await moderation.trancher(autre.id, 'retenir', 'Banc');
    expect(await visibles(membres.b)).not.toContain('Un autre avis tranché');
    expect((await moderation.commentairesSignales('traites', 1, 100)).data.map((d) => d.comment_id))
      .toContain(autre.id);
  });

  it('bloquer un membre masque ses commentaires et ses réponses, pour celui qui bloque seulement', async () => {
    const parent = await commentaires.postComment(pronosticId, membres.b, 'Je suis d\'accord avec le pronostic');
    await commentaires.postComment(pronosticId, membres.auteur, 'Moi non plus', parent.id);
    await moderation.bloquer(membres.a, membres.auteur);

    const pourA = (await commentaires.getComments(pronosticId, membres.a)).comments;
    expect(pourA.map((c: any) => c.content)).toEqual(['Je suis d\'accord avec le pronostic']);
    expect(pourA[0].replies).toEqual([]);
    expect(await visibles(membres.c)).toContain('Analyse discutable à mon avis');

    expect((await moderation.listeBloques(membres.a)).map((b) => b.user_id)).toEqual([membres.auteur]);
    await moderation.bloquer(membres.a, membres.auteur); // sans effet, sans erreur
    await expect(moderation.bloquer(membres.a, membres.a)).rejects.toMatchObject({ code: 'BLOCAGE_SOI' });

    await moderation.debloquer(membres.a, membres.auteur);
    expect(await visibles(membres.a)).toContain('Analyse discutable à mon avis');
  });
});
