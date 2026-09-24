import express, { Express } from 'express';

/**
 * Taille des corps JSON, par route.
 *
 * Toutes les routes acceptaient 10 Mo, parce que deux d'entre elles reçoivent
 * une image en base64 : n'importe quel appel pouvait faire allouer 10 Mo à
 * l'API (constat S4 de l'audit du 24 septembre 2026). Les deux routes d'image
 * gardent une limite d'image (5 Mo de fichier, soit ~6,7 Mo en base64),
 * l'administration une limite de contenu éditorial, et tout le reste 256 Ko.
 *
 * Le premier analyseur qui lit un corps le marque comme lu : les suivants le
 * laissent passer. L'ordre de montage fait donc la règle.
 */
export const ROUTES_IMAGE = ['/api/v1/subscriptions/submit-proof', '/api/v1/profile/avatar'];
export const ROUTES_ADMIN = ['/api/v1/admin', '/api/v1/pronostics/admin', '/api/v1/comments'];

export function monterAnalyseursJson(app: Express) {
  app.use(ROUTES_IMAGE, express.json({ limit: '8mb' }));
  app.use(ROUTES_ADMIN, express.json({ limit: '2mb' }));
  app.use(express.json({ limit: '256kb' }));
}
