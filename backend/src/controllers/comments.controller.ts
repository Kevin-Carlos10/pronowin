import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { CommentsService } from '../services/comments.service';

const svc = new CommentsService();

export const getComments = async (req: AuthRequest, res: Response) => {
  try {
    const result = await svc.getComments(req.params.pronosticId, req.userId!);
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const postComment = async (req: AuthRequest, res: Response) => {
  try {
    const { content, parent_id } = req.body;
    const comment = await svc.postComment(
      req.params.pronosticId, req.userId!, content, parent_id
    );
    res.status(201).json(comment);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const voteOnPronostic = async (req: AuthRequest, res: Response) => {
  try {
    const type = req.body.type as 'AGREE' | 'DISAGREE';
    if (!['AGREE', 'DISAGREE'].includes(type)) {
      res.status(400).json({ message: 'Type invalide. Utilisez AGREE ou DISAGREE.' });
      return;
    }
    const result = await svc.vote(req.params.pronosticId, req.userId!, type);
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const deleteComment = async (req: AuthRequest, res: Response) => {
  try {
    await svc.deleteComment(req.params.commentId, req.userId!);
    res.json({ message: 'Commentaire supprimé.' });
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const postExpertReply = async (req: AdminRequest, res: Response) => {
  try {
    const { content, parent_id } = req.body;
    const comment = await svc.postExpertReply(
      req.params.pronosticId, req.adminId!, content, parent_id
    );
    res.status(201).json(comment);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};
