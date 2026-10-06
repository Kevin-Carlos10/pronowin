/**
 * Les notifications : un seul langage, des anciennes aux nouvelles, et des
 * sélections nommées en français.
 */
import fs from 'fs';
import path from 'path';
import { harmoniserNotification } from '../utils/notifications_anciennes';
import { nomEquipe, PAYS } from '../utils/noms_equipes';

describe('les anciennes notifications, réécrites à la lecture', () => {
  it('les titres du système perdent leur émoji et leur majuscule', () => {
    const n = harmoniserNotification({ id: 'n1', title: '🏆 Pronostic Gagnant !', body: 'x' });
    expect(n.title).toBe('Pronostic gagnant !');
    expect(n.id).toBe('n1');
    expect(harmoniserNotification({ title: '❌ Pronostic Perdant', body: '' }).title).toBe('Pronostic perdant');
    expect(harmoniserNotification({ title: '⚠️ Compte suspendu', body: '' }).title).toBe('Compte suspendu');
    expect(harmoniserNotification({ title: '💰 Commission L2 reçue !', body: '' }).title).toBe('Commission L2 reçue !');
  });

  it('l\'accord et la devise du corps sont corrigés', () => {
    const n = harmoniserNotification({
      title: '🏆 Pronostic Gagnant !',
      body: '+7 800 XOF sur Bodo/Glimt vs NEC Nijmegen. Votre bankroll est mis à jour !',
    });
    expect(n.body).toBe('+7 800 FCFA sur Bodo/Glimt vs NEC Nijmegen. Votre bankroll est mise à jour !');
  });

  it('un message rédigé depuis le panneau reste tel quel', () => {
    const n = { title: '🔥 Offre spéciale ce week-end', body: 'Profitez-en !' };
    expect(harmoniserNotification(n)).toBe(n);
    // Un émoji connu devant un texte inconnu n'est pas un ancien titre.
    expect(harmoniserNotification({ title: '🎉 Merci à tous !', body: '' }).title).toBe('🎉 Merci à tous !');
  });
});

describe('les sélections nommées en français', () => {
  it('traduit les pays, garde les clubs et la catégorie', () => {
    expect(nomEquipe('Belgium')).toBe('Belgique');
    expect(nomEquipe('Ivory Coast')).toBe("Côte d'Ivoire");
    expect(nomEquipe('Spain U21')).toBe('Espagne U21');
    expect(nomEquipe('Barcelona')).toBe('Barcelona');
  });

  it('la table du serveur est celle du mobile', () => {
    // Deux copies, deux langages : c'est précisément ce qui diverge.
    const dart = fs.readFileSync(
      path.join(__dirname, '..', '..', '..', 'mobile_new', 'lib', 'core', 'utils', 'noms_equipes.dart'), 'utf8');
    const debut = dart.indexOf('const _pays');
    const bloc = dart.slice(debut, dart.indexOf('\n};', debut));
    const mobile: Record<string, string> = {};
    for (const m of bloc.matchAll(/(?:'([^']*)'|"([^"]*)")\s*:\s*(?:'([^']*)'|"([^"]*)")/g)) {
      mobile[m[1] ?? m[2]] = m[3] ?? m[4];
    }
    expect(Object.keys(mobile).length).toBeGreaterThan(100);
    expect(PAYS).toEqual(mobile);
  });

  it('les notifications de match passent par `nomEquipe`', () => {
    // Les lignes `title:` / `body:` qui citent une équipe : c'est le texte
    // qui atterrit sur l'écran verrouillé.
    const fautifs: string[] = [];
    for (const f of ['pronostics.service.ts', 'notification.service.ts', 'bankroll.service.ts']) {
      const src = fs.readFileSync(path.join(__dirname, '..', 'services', f), 'utf8');
      for (const l of src.split('\n')) {
        const t = l.trimStart();
        // Un nom brut : `${match.homeTeam}`, `${params.awayTeam}`…
        if ((t.startsWith('title:') || t.startsWith('body:')) && /\$\{\s*(?:[\w.]+\.)?(homeTeam|awayTeam)\s*\}/.test(t)) {
          fautifs.push(`${f}: ${t}`);
        }
      }
    }
    expect(fautifs).toEqual([]);
  });
});
