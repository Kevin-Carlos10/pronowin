import { Router } from 'express';
import { authMiddleware, premiumMiddleware } from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/comments.controller';

const r = Router();

// Tous les membres premium peuvent voir et commenter
r.get ('/:pronosticId',         authMiddleware, premiumMiddleware, C.getComments);
r.post('/:pronosticId',         authMiddleware, premiumMiddleware, C.postComment);
r.post('/:pronosticId/vote',    authMiddleware, premiumMiddleware, C.voteOnPronostic);
r.delete('/:pronosticId/comment/:commentId', authMiddleware, C.deleteComment);

// Réponse expert (admin uniquement)
r.post('/:pronosticId/expert',  adminMiddleware, C.postExpertReply);

export default r;
