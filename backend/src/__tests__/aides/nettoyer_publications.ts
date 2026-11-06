
import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { BASE_LOCALE } from './base_locale';

/** Nettoyage de fixtures seulement dans les bases jetables explicitement nommées.
 * Le verrou DDL dure jusqu'au commit : les autres connexions ne voient jamais
 * les protections désactivées. Les cascades de clés étrangères restent actives.
 */
export async function nettoyerPublications(where: Prisma.PronosticWhereInput) {
  if (!BASE_LOCALE) throw new Error('Nettoyage réservé aux bases de test dédiées.');
  await prisma.$transaction(async tx => {
    const ids = (await tx.pronostic.findMany({ where, select: { id: true } })).map(p => p.id);
    await tx.$executeRawUnsafe('ALTER TABLE pronostics DISABLE TRIGGER pronostics_publication_guard');
    await tx.$executeRawUnsafe('ALTER TABLE pronostic_publication_events DISABLE TRIGGER journal_publication_immuable');
    await tx.pronosticPublicationEvent.deleteMany({ where: { pronosticId: { in: ids } } });
    await tx.pronostic.deleteMany({ where: { id: { in: ids } } });
    await tx.$executeRawUnsafe('ALTER TABLE pronostic_publication_events ENABLE TRIGGER journal_publication_immuable');
    await tx.$executeRawUnsafe('ALTER TABLE pronostics ENABLE TRIGGER pronostics_publication_guard');
  });
}
