import { Router } from 'express';
import { AdminAuthService } from '../services/admin_auth.service';
import { adminMiddleware, AdminRequest } from '../middleware/admin.middleware';
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
r.post('/login',  async (req, res) => {
  try { res.json(await svc.login(req.body.email, req.body.password)); }
  catch (e: any) { res.status(401).json({ message: e.message }); }
});
// Route de création admin — désactivée en production
r.post('/create', async (req, res) => {
  if (process.env.NODE_ENV === 'production') {
    res.status(404).json({ message: 'Route indisponible.' }); return;
  }
  const secret = req.headers['x-admin-setup-secret'];
  if (secret !== process.env.ADMIN_SETUP_SECRET) { res.status(403).json({ message: 'Interdit.' }); return; }
  try { res.status(201).json(await svc.createAdmin(req.body)); }
  catch (e: any) { res.status(400).json({ message: e.message }); }
});
export default r;
