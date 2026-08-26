import { Router } from 'express';
import { AdminAuthService } from '../services/admin_auth.service';
import { adminMiddleware, AdminRequest } from '../middleware/admin.middleware';
import { lireConfig, ecrireConfig } from '../services/app_config.service';
import * as Methodes from '../services/payment_method.service';
const r   = Router();
const svc = new AdminAuthService();

/**
 * PATCH /admin/profile/password
 *
 * L'admin-web postait ici depuis toujours pour l'admin principal ; la route
 * n'existait pas et le changement de mot de passe échouait systématiquement.
 * (Les sous-admins sont gérés localement par l'admin-web, hors backend.)
 */
r.patch('/profile/password', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.json(await svc.changePassword(
      req.adminId!, req.body.current_password, req.body.new_password));
  } catch (e: any) { res.status(422).json({ message: e.message }); }
});
/**
 * GET /admin/app-config — réglages de version et de mise à jour.
 *
 * Renvoie aussi l'origine de chaque valeur (`base` ou `env`) : sans ça,
 * l'administrateur ne peut pas distinguer un réglage qu'il a enregistré d'une
 * valeur héritée du serveur, et croit modifier ce qu'il ne modifie pas.
 */
r.get('/app-config', adminMiddleware, async (_req: AdminRequest, res) => {
  try {
    res.json(await lireConfig());
  } catch (e: any) { res.status(500).json({ message: e.message }); }
});

/** PUT /admin/app-config — enregistre les clés reconnues, ignore les autres. */
r.put('/app-config', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const ecrites = await ecrireConfig(req.body ?? {}, req.adminId);
    const { valeurs, origine } = await lireConfig();
    res.json({ updated: ecrites, valeurs, origine });
  } catch (e: any) { res.status(422).json({ message: e.message }); }
});

// ─── Méthodes de paiement Mobile Money ───────────────────────────────────────
//
// La clé (`key`) n'est jamais modifiable après création : elle est stockée
// telle quelle dans Transaction.paymentMethod et dans les preuves d'abonnement.
// La renommer rendrait l'historique illisible.

r.get('/payment-methods', adminMiddleware, async (_req: AdminRequest, res) => {
  try { res.json(await Methodes.listerToutes()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
});

r.post('/payment-methods', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.status(201).json(await Methodes.creer({
      key:       req.body.key,
      label:     String(req.body.label ?? ''),
      phone:     String(req.body.phone ?? ''),
      isActive:  req.body.is_active !== false,
      sortOrder: Number(req.body.sort_order ?? 0),
    }));
  } catch (e: any) { res.status(422).json({ message: e.message }); }
});

r.put('/payment-methods/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.json(await Methodes.modifier(req.params.id, {
      label:     req.body.label !== undefined ? String(req.body.label) : undefined,
      phone:     req.body.phone !== undefined ? String(req.body.phone) : undefined,
      isActive:  req.body.is_active !== undefined ? req.body.is_active === true || req.body.is_active === 'true' : undefined,
      sortOrder: req.body.sort_order !== undefined ? Number(req.body.sort_order) : undefined,
    }));
  } catch (e: any) { res.status(422).json({ message: e.message }); }
});

r.delete('/payment-methods/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try { res.json(await Methodes.supprimer(req.params.id)); }
  catch (e: any) { res.status(422).json({ message: e.message }); }
});

r.post('/login',  async (req, res) => {
  try { res.json(await svc.login(req.body.email, req.body.password)); }
  catch (e: any) { res.status(401).json({ message: e.message }); }
});
/**
 * POST /admin/create — amorçage du premier administrateur.
 *
 * Le contrôle précédent s'écrivait `secret !== process.env.ADMIN_SETUP_SECRET`.
 * Absent des deux côtés, cela compare `undefined !== undefined`, c'est-à-dire
 * **faux** : le garde laissait passer. Et rien ne rendait ce cas improbable —
 * `ADMIN_SETUP_SECRET` ne figurait pas dans `.env.example`, que le README
 * demande de recopier tel quel, avec `NODE_ENV=development` en deuxième ligne.
 * Un déploiement fait en suivant la documentation ouvrait donc la création de
 * comptes administrateurs à tout le monde — `createAdmin` accepte le rôle
 * envoyé dans le corps, `super_admin` compris.
 *
 * Trois conditions désormais, dans cet ordre, chacune fermant d'elle-même :
 * pas en production, secret configuré côté serveur, secret fourni et égal.
 */
r.post('/create', async (req, res) => {
  if (process.env.NODE_ENV === 'production') {
    res.status(404).json({ message: 'Route indisponible.' }); return;
  }
  const attendu = process.env.ADMIN_SETUP_SECRET;
  if (!attendu) {
    // Ne pas dépendre de NODE_ENV pour cette protection : sans secret
    // configuré, la route n'existe pas, quel que soit l'environnement.
    res.status(404).json({ message: 'Route indisponible.' }); return;
  }
  const secret = req.headers['x-admin-setup-secret'];
  if (!secret || secret !== attendu) { res.status(403).json({ message: 'Interdit.' }); return; }
  try { res.status(201).json(await svc.createAdmin(req.body)); }
  catch (e: any) { res.status(400).json({ message: e.message }); }
});
export default r;
