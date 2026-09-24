import {
  S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import crypto from 'crypto';

import { ErreurMetier } from '../utils/erreurs';

const REGION = process.env.AWS_REGION ?? 'eu-west-1';

const s3 = new S3Client({
  region:      REGION,
  credentials: {
    accessKeyId:     process.env.AWS_ACCESS_KEY_ID     ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
  },
});

const BUCKET = process.env.AWS_S3_BUCKET ?? 'pronowin-uploads';
const HOTE_BUCKET = `${BUCKET}.s3.${REGION}.amazonaws.com`;

/**
 * Les dossiers dont le contenu est privé.
 *
 * Les captures de paiement partaient en `public-read`, à une adresse publique
 * permanente : numéros Mobile Money, montants, noms, lisibles par quiconque
 * obtenait le lien, sans expiration (constat S10 de l'audit du 24 septembre
 * 2026). Elles sont désormais privées ; l'administration les lit par une
 * adresse signée qui expire (`urlLectureSignee`). Les avatars restent publics :
 * l'application les affiche à tout le monde.
 */
const DOSSIERS_PRIVES = new Set(['proofs']);

/** Les formats acceptés, et la signature binaire qui les prouve. */
const FORMATS: Record<string, (b: Buffer) => boolean> = {
  'image/jpeg': (b) => b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png':  (b) => b.length > 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  'image/webp': (b) => b.length > 12 && b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP',
};
export const TAILLE_IMAGE_MAX = 5 * 1024 * 1024;

const extension = (mime: string) => mime.split('/')[1].replace('jpeg', 'jpg');
const urlPublique = (cle: string) => `https://${HOTE_BUCKET}/${cle}`;

/**
 * La clé S3 d'une adresse de notre bucket, ou `null` si l'adresse n'en est
 * pas une. Seul le bucket configuré compte : une adresse d'un autre bucket,
 * ou d'un autre site, n'a pas de clé ici.
 */
export function cleDe(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    const u = new URL(url);
    if (u.protocol !== 'https:' || u.host !== HOTE_BUCKET) return null;
    const cle = decodeURIComponent(u.pathname.replace(/^\/+/, ''));
    return cle && !cle.includes('..') ? cle : null;
  } catch {
    return null;
  }
}

export class S3Service {

  /**
   * Dépose une image transmise en base64 et rend son adresse.
   *
   * Le type annoncé dans l'en-tête `data:` n'est plus cru sur parole : les
   * premiers octets doivent être ceux d'un JPEG, d'un PNG ou d'un WebP. Un
   * fichier renommé, ou un type MIME trompeur, est refusé.
   */
  async uploadImage(params: {
    base64:    string;       // "data:image/jpeg;base64,/9j/..."
    folder:    string;       // "proofs" | "avatars"
    userId:    string;
  }): Promise<string> {
    const matches = params.base64.match(/^data:([A-Za-z-+/]+);base64,(.+)$/);
    if (!matches) throw new ErreurMetier('Format image invalide.', 422);

    const mimeType  = matches[1].toLowerCase();
    const imageData = Buffer.from(matches[2], 'base64');

    if (imageData.length > TAILLE_IMAGE_MAX) {
      throw new ErreurMetier('Image trop grande. Maximum 5 Mo.', 413);
    }
    const reconnait = FORMATS[mimeType];
    if (!reconnait || !reconnait(imageData)) {
      throw new ErreurMetier('Image refusée : seuls les formats JPEG, PNG et WebP sont acceptés.', 422);
    }

    const cle = `${params.folder}/${params.userId}/${crypto.randomUUID()}.${extension(mimeType)}`;
    await s3.send(new PutObjectCommand({
      Bucket:      BUCKET,
      Key:         cle,
      Body:        imageData,
      ContentType: mimeType,
      ...(DOSSIERS_PRIVES.has(params.folder) ? {} : { ACL: 'public-read' as const }),
    }));

    return urlPublique(cle);
  }

  /** Générer une URL pré-signée pour upload direct depuis le mobile */
  async getPresignedUrl(params: {
    folder:    string;
    userId:    string;
    mimeType:  string;
    expiresIn: number; // secondes
  }): Promise<{ uploadUrl: string; fileUrl: string; key: string }> {
    const mimeType = params.mimeType.toLowerCase();
    if (!FORMATS[mimeType]) {
      throw new ErreurMetier('Type refusé : seuls les formats JPEG, PNG et WebP sont acceptés.', 422);
    }
    const key = `${params.folder}/${params.userId}/${crypto.randomUUID()}.${extension(mimeType)}`;

    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({
        Bucket:      BUCKET,
        Key:         key,
        ContentType: mimeType,
        ...(DOSSIERS_PRIVES.has(params.folder) ? {} : { ACL: 'public-read' as const }),
      }),
      { expiresIn: params.expiresIn },
    );

    return { uploadUrl, fileUrl: urlPublique(key), key };
  }

  /**
   * Une adresse de lecture temporaire pour un objet de notre bucket.
   *
   * Les captures étant privées, leur adresse brute ne s'ouvre plus : le
   * panneau reçoit à chaque affichage une adresse signée qui expire. Une
   * adresse qui n'est pas de notre bucket est rendue telle quelle — le
   * panneau n'en tire rien de plus qu'avant.
   */
  async urlLectureSignee(url: string | null | undefined, dureeS = 600): Promise<string | null> {
    if (!url) return url ?? null;
    const cle = cleDe(url);
    if (!cle) return url;
    return getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: cle }), { expiresIn: dureeS });
  }

  /** Supprimer une image */
  async deleteImage(fileUrl: string): Promise<void> {
    try {
      const key = cleDe(fileUrl);
      if (!key) return;
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
    } catch (e) {
      console.error('[S3] Erreur suppression:', e);
    }
  }
}
