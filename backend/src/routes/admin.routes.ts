import { Router } from 'express';
import { AdminAuthService } from '../services/admin_auth.service';
const r   = Router();
const svc = new AdminAuthService();
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
