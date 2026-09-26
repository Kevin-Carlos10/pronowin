import fs from 'fs';
import path from 'path';

/**
 * La faille : `_verifyAppleJws` vérifiait la signature du JWS avec le
 * certificat contenu **dans le JWS lui-même**. Un attaquant générait sa propre
 * paire de clés, y joignait son certificat auto-signé, signait la charge de son
 * choix — et la vérification passait. L'échéance transmise était ensuite écrite
 * telle quelle dans `subscriptionExpiresAt`.
 *
 * Ces contrôles portent sur la structure du code plutôt que sur une exécution :
 * le défaut ne se manifestait ni à la compilation, ni dans un test unitaire du
 * chemin nominal — la signature « valide » de l'attaquant se comportait
 * exactement comme celle d'Apple.
 */
describe('webhook Apple — la notification ne fait pas autorité', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'services', 'iap.service.ts'), 'utf8');

  /** Le code sans les commentaires, qui citent volontairement la faille. */
  const code = source
    .split('\n')
    .filter(l => {
      const t = l.trimStart();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

  it('ne vérifie plus une signature avec le certificat qu\'elle transporte', () => {
    expect(code).not.toContain('_verifyAppleJws');
    expect(/jwt\.verify\s*\(/.test(code)).toBe(false);
  });

  it('n\'extrait plus de certificat du JWS', () => {
    expect(code).not.toContain('x5c');
    expect(code).not.toContain('BEGIN CERTIFICATE');
  });

  it('rejoue la vérification auprès d\'Apple', () => {
    const handler = code.slice(code.indexOf('async handleAppleNotification'));
    const corps   = handler.slice(0, handler.indexOf('\n  }'));
    expect(corps).toContain('verifyAndRecord');
    expect(corps).toContain("store:   'apple'");
  });

  it('n\'écrit plus l\'échéance transmise par la notification', () => {
    const handler = code.slice(code.indexOf('async handleAppleNotification'));
    const corps   = handler.slice(0, handler.indexOf('\n  }'));
    expect(corps).not.toContain('expiresDate');
    expect(corps).not.toContain('subscriptionExpiresAt');
  });

  it('le point d\'écriture direct a disparu', () => {
    // `_applyStoreEvent` écrivait le Premium depuis la charge reçue et décidait
    // de la révocation d'après le seul `notificationType` de l'appelant.
    expect(code).not.toContain('_applyStoreEvent');
    expect(code).not.toContain('notificationType:');
  });

  it('traite Apple et Google de la même façon', () => {
    for (const nom of ['handleAppleNotification', 'handleGoogleNotification']) {
      const h = code.slice(code.indexOf(`async ${nom}`));
      const corps = h.slice(0, h.indexOf('\n  }'));
      expect(corps).toContain('verifyAndRecord');
    }
  });

  it('une notification pour un achat inconnu reste sans effet', () => {
    const handler = code.slice(code.indexOf('async handleAppleNotification'));
    const corps   = handler.slice(0, handler.indexOf('\n  }'));
    expect(corps).toContain('unknown_original_transaction');
    // La recherche en base doit précéder toute écriture : sans cela, un
    // identifiant inventé suffirait à créer une ligne.
    expect(corps.indexOf('findFirst'))
      .toBeLessThan(corps.indexOf('verifyAndRecord'));
  });

  it('une charge illisible ne provoque pas d\'accès non lu', () => {
    const handler = code.slice(code.indexOf('async handleAppleNotification'));
    const corps   = handler.slice(0, handler.indexOf('\n  }'));
    expect(corps).toContain('payload_sans_transaction');
    expect(corps).toContain('original_transaction_absent');
  });
});
