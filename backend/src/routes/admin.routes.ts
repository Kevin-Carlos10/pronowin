import { Router } from 'express';
import { AdminAuthService } from '../services/admin_auth.service';
import { adminMiddleware, AdminRequest } from '../middleware/admin.middleware';
import { lireConfig, ecrireConfig } from '../services/app_config.service';
import { SubscriptionService, BETTING_PLATFORMS } from '../services/subscription.service';
import * as Methodes from '../services/payment_method.service';
import { repondreErreur } from '../utils/erreurs';
import { lireSante } from '../services/sante.service';
import { ajouterAuJournal, verifierChaine } from '../services/journal_admin.service';
import { resumeAchatsStore, reverifierAchatStore } from '../services/achats_store_admin.service';
import {
  programmerPublication, programmerNotification, annulerProgrammation, listerProgrammations,
} from '../services/programmations.service';
const r   = Router();
const svc = new AdminAuthService();
const subSvc = new SubscriptionService();

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
  } catch (e: any) { repondreErreur(res, e, 422); }
});
/**
 * POST /admin/journal — une action d'administration, au nom de l'acteur
 * délégué. Le corps dit ce qui a été fait ; l'auteur vient de la délégation,
 * jamais du corps (constats A3 et D02).
 */
r.post('/journal', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    if (!req.acteurAdmin) { res.status(403).json({ message: 'Auteur inconnu.' }); return; }
    const { action, cible, details, ip, horodatage } = req.body ?? {};
    if (typeof action !== 'string' || !action.trim()) {
      res.status(422).json({ message: 'action requise.' }); return;
    }
    const h = horodatage ? new Date(horodatage) : new Date();
    // Une date d'action dans le futur, ou vieille de plus d'une heure, n'est
    // pas celle d'une action qui vient d'avoir lieu.
    const date = Number.isFinite(h.getTime()) && Math.abs(Date.now() - h.getTime()) < 3600_000 ? h : new Date();
    const e = await ajouterAuJournal(req.acteurAdmin, { action, cible, details, ip, horodatage: date });
    res.status(201).json({ id: e.id, empreinte: e.empreinte });
  } catch (e: any) { repondreErreur(res, e); }
});

/** GET /admin/journal/verification — la chaîne est-elle intacte ? */
r.get('/journal/verification', adminMiddleware, async (_req: AdminRequest, res) => {
  try { res.json(await verifierChaine()); }
  catch (e: any) { repondreErreur(res, e); }
});

/**
 * GET /admin/sante — ce que le tableau de bord doit montrer de la machine.
 *
 * Réservée à l'administrateur principal. Tout est lu, rien n'est calculé en
 * mémoire du panneau : base, tâches de fond, quota football, file des
 * notifications de store, dernière sauvegarde, preuves en attente.
 */
r.get('/sante', adminMiddleware, async (_req: AdminRequest, res) => {
  try { res.json(await lireSante()); }
  catch (e: any) { repondreErreur(res, e); }
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
    // La liste des enseignes accompagne la configuration : le panneau
    // n'offrait un champ « code propre » que pour trois enseignes écrites en
    // dur dans sa vue. Réduire le partenariat côté serveur aurait laissé deux
    // champs sans usage, dont les valeurs n'auraient plus été lues.
    res.json({ ...(await lireConfig()), plateformes: BETTING_PLATFORMS });
  } catch (e: any) { repondreErreur(res, e); }
});

/** PUT /admin/app-config — enregistre les clés reconnues, ignore les autres. */
r.put('/app-config', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const ecrites = await ecrireConfig(req.body ?? {}, req.adminId);
    const { valeurs, origine } = await lireConfig();
    res.json({ updated: ecrites, valeurs, origine });
  } catch (e: any) { repondreErreur(res, e, 422); }
});

/**
 * GET /admin/promo-stats — bilan du parcours « code promo ».
 *
 * Ce parcours coute un mois d'abonnement par conversion. Le detail par
 * plateforme repond a la question qu'aucun autre ecran ne pose : est-ce que
 * les comptes ouverts chez un partenaire valent les mois offerts ?
 */
r.get('/promo-stats', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const jours = Math.min(parseInt((req.query.days as string) ?? '30') || 30, 365);
    res.json(await subSvc.statistiquesCodePromo(jours));
  } catch (e: any) { repondreErreur(res, e); }
});

// ─── Achats App Store et Google Play ─────────────────────────────────────────
//
// Les abonnements vendus par les stores, regroupés par abonnement, avec leurs
// anomalies (payé chez le store, compte non Premium) et les notifications
// reçues des stores. Aucun écran ne les montrait.

r.get('/achats-store', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const store = req.query.store === 'apple' || req.query.store === 'google' ? req.query.store : undefined;
    const etats = ['actif', 'resilie', 'impaye', 'expire', 'rembourse', 'anomalie'];
    const etat  = typeof req.query.etat === 'string' && etats.includes(req.query.etat) ? req.query.etat : undefined;
    res.json(await resumeAchatsStore({
      store, etat,
      tests:     req.query.tests === '1',
      recherche: typeof req.query.q === 'string' ? req.query.q.slice(0, 100) : undefined,
      page:      parseInt(String(req.query.page ?? '1')) || 1,
    }));
  } catch (e: any) { repondreErreur(res, e); }
});

/**
 * POST /admin/achats-store/:id/reverifier — redemande au store l'état d'un
 * abonnement et le reporte sur le compte. Sert les anomalies : un achat payé
 * dont la vérification n'a pas abouti au moment de l'achat.
 */
r.post('/achats-store/:id/reverifier', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const resultat = await reverifierAchatStore(req.params.id);
    if (!resultat) { res.status(404).json({ message: 'Achat introuvable.' }); return; }
    res.json(resultat);
  } catch (e: any) { repondreErreur(res, e, 502); }
});

// ─── Programmations ──────────────────────────────────────────────────────────
//
// Publier un pronostic, envoyer une notification, à une heure choisie. Une
// route par type : chacun relève de sa propre permission.

/** L'instant demandé : une date ISO, avec son fuseau. */
const instantDe = (v: unknown) => new Date(typeof v === 'string' ? v : NaN);
const auteurDe = (req: AdminRequest) => req.acteurAdmin?.nom ?? 'Administrateur';

r.get('/programmations/pronostics', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const pronosticId = typeof req.query.pronostic === 'string' ? req.query.pronostic : undefined;
    res.json(await listerProgrammations('publication_pronostic', { pronosticId }));
  } catch (e: any) { repondreErreur(res, e); }
});

r.post('/programmations/pronostics', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.status(201).json(await programmerPublication({
      pronosticId: typeof req.body?.pronostic_id === 'string' ? req.body.pronostic_id : undefined,
      matchId:     typeof req.body?.match_id === 'string' ? req.body.match_id : undefined,
      prevueLe:    instantDe(req.body?.prevue_le),
      auteur:      auteurDe(req),
    }));
  } catch (e: any) { repondreErreur(res, e, 422); }
});

r.delete('/programmations/pronostics/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try { res.json(await annulerProgrammation(req.params.id, 'publication_pronostic', auteurDe(req))); }
  catch (e: any) { repondreErreur(res, e, 409); }
});

r.get('/programmations/notifications', adminMiddleware, async (_req: AdminRequest, res) => {
  try { res.json(await listerProgrammations('notification')); }
  catch (e: any) { repondreErreur(res, e); }
});

r.post('/programmations/notifications', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    const b = req.body ?? {};
    res.status(201).json(await programmerNotification({
      segment: String(b.segment ?? ''), title: String(b.title ?? ''), body: String(b.body ?? ''),
      titleEn: b.title_en, bodyEn: b.body_en,
      deepLink: typeof b.deep_link === 'string' ? b.deep_link : null,
      imageUrl: typeof b.image === 'string' ? b.image : null,
      prevueLe: instantDe(b.prevue_le),
      auteur:   auteurDe(req),
    }));
  } catch (e: any) { repondreErreur(res, e, 422); }
});

r.delete('/programmations/notifications/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try { res.json(await annulerProgrammation(req.params.id, 'notification', auteurDe(req))); }
  catch (e: any) { repondreErreur(res, e, 409); }
});

// ─── Méthodes de paiement Mobile Money ───────────────────────────────────────
//
// La clé (`key`) n'est jamais modifiable après création : elle est stockée
// telle quelle dans Transaction.paymentMethod et dans les preuves d'abonnement.
// La renommer rendrait l'historique illisible.

r.get('/payment-methods', adminMiddleware, async (_req: AdminRequest, res) => {
  try { res.json(await Methodes.listerToutes()); }
  catch (e: any) { repondreErreur(res, e); }
});

r.post('/payment-methods', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.status(201).json(await Methodes.creer({
      key:       req.body.key,
      label:     String(req.body.label ?? ''),
      phone:     String(req.body.phone ?? ''),
      ussd:      req.body.ussd_template !== undefined
                   ? String(req.body.ussd_template) : undefined,
      isActive:  req.body.is_active !== false,
      sortOrder: Number(req.body.sort_order ?? 0),
    }));
  } catch (e: any) { repondreErreur(res, e, 422); }
});

r.put('/payment-methods/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try {
    res.json(await Methodes.modifier(req.params.id, {
      label:     req.body.label !== undefined ? String(req.body.label) : undefined,
      phone:     req.body.phone !== undefined ? String(req.body.phone) : undefined,
      // `undefined` distingue « champ absent » (la bascule actif/inactif
      // n'envoie que `is_active`) de « champ vidé », qui efface le modèle.
      ussd:      req.body.ussd_template !== undefined
                   ? String(req.body.ussd_template) : undefined,
      isActive:  req.body.is_active !== undefined ? req.body.is_active === true || req.body.is_active === 'true' : undefined,
      sortOrder: req.body.sort_order !== undefined ? Number(req.body.sort_order) : undefined,
    }));
  } catch (e: any) { repondreErreur(res, e, 422); }
});

r.delete('/payment-methods/:id', adminMiddleware, async (req: AdminRequest, res) => {
  try { res.json(await Methodes.supprimer(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 422); }
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
  catch (e: any) { repondreErreur(res, e, 400); }
});
export default r;
