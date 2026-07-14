import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { NotificationService } from '../services/notification.service';

const svc = new NotificationService();

// ── Historique notifications ──────────────────────────────────────────────────

export const getMyNotifications = async (req: AuthRequest, res: Response) => {
  try {
    const notifs = await svc.getNotifications(req.userId!, 50);
    res.json(notifs.map(n => ({
      id:         n.id,
      title:      n.title,
      body:       n.body,
      type:       n.type,
      is_read:    n.isRead,
      deep_link:  n.deepLink,
      created_at: n.createdAt.toISOString(),
    })));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const markOneRead = async (req: AuthRequest, res: Response) => {
  try {
    await svc.markRead(req.userId!, req.params.id);
    res.json({ success: true });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const markAllRead = async (req: AuthRequest, res: Response) => {
  try {
    await svc.markAllRead(req.userId!);
    res.json({ success: true });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// ── Token FCM ─────────────────────────────────────────────────────────────────

export const registerToken = async (req: AuthRequest, res: Response) => {
  const { fcm_token, platform } = req.body;
  if (!fcm_token) { res.status(422).json({ message: 'fcm_token requis.' }); return; }
  try {
    await svc.registerToken(req.userId!, fcm_token, platform ?? 'android');
    res.json({ success: true });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const sendToUser = async (req: AdminRequest, res: Response) => {
  const { title, body, deep_link } = req.body;
  if (!title || !body) { res.status(422).json({ message: 'title et body requis.' }); return; }
  try {
    const result = await svc.sendToUser(req.params.userId, {
      title, body, data: deep_link ? { deep_link } : {},
    });
    if (!result.success && (result as any).reason === 'no_token') {
      res.status(400).json({ message: 'Token FCM absent. L\'utilisateur doit ouvrir l\'app d\'abord.' });
      return;
    }
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const sendToTopic = async (req: AdminRequest, res: Response) => {
  const { topic, title, body, deep_link } = req.body;
  if (!topic || !title || !body) { res.status(422).json({ message: 'topic, title et body requis.' }); return; }
  try {
    res.json(await svc.sendToTopic(topic, { title, body, data: deep_link ? { deep_link } : {} }));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
