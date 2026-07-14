import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import crypto from 'crypto';

const s3 = new S3Client({
  region:      process.env.AWS_REGION      ?? 'eu-west-1',
  credentials: {
    accessKeyId:     process.env.AWS_ACCESS_KEY_ID     ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
  },
});

const BUCKET = process.env.AWS_S3_BUCKET ?? 'pronowin-uploads';

export class S3Service {

  /** Upload une image (base64 ou buffer) et retourne l'URL publique */
  async uploadImage(params: {
    base64:    string;       // "data:image/jpeg;base64,/9j/..."
    folder:    string;       // "proofs" | "avatars"
    userId:    string;
  }): Promise<string> {
    // Extraire le type MIME et les données base64
    const matches = params.base64.match(/^data:([A-Za-z-+\/]+);base64,(.+)$/);
    if (!matches) throw new Error('Format image invalide.');

    const mimeType  = matches[1];
    const imageData = Buffer.from(matches[2], 'base64');
    const ext       = mimeType.split('/')[1].replace('jpeg', 'jpg');

    // Nom de fichier unique
    const filename  = `${params.folder}/${params.userId}/${crypto.randomUUID()}.${ext}`;

    // Vérification taille (max 5MB)
    if (imageData.length > 5 * 1024 * 1024) {
      throw new Error('Image trop grande. Maximum 5 MB.');
    }

    await s3.send(new PutObjectCommand({
      Bucket:      BUCKET,
      Key:         filename,
      Body:        imageData,
      ContentType: mimeType,
      // Accès public en lecture pour affichage dans le dashboard
      ACL:         'public-read',
    }));

    return `https://${BUCKET}.s3.${process.env.AWS_REGION ?? 'eu-west-1'}.amazonaws.com/${filename}`;
  }

  /** Générer une URL pré-signée pour upload direct depuis le mobile */
  async getPresignedUrl(params: {
    folder:    string;
    userId:    string;
    mimeType:  string;
    expiresIn: number; // secondes
  }): Promise<{ uploadUrl: string; fileUrl: string; key: string }> {
    const ext      = params.mimeType.split('/')[1].replace('jpeg', 'jpg');
    const key      = `${params.folder}/${params.userId}/${crypto.randomUUID()}.${ext}`;
    const fileUrl  = `https://${BUCKET}.s3.${process.env.AWS_REGION ?? 'eu-west-1'}.amazonaws.com/${key}`;

    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({
        Bucket:      BUCKET,
        Key:         key,
        ContentType: params.mimeType,
        ACL:         'public-read',
      }),
      { expiresIn: params.expiresIn },
    );

    return { uploadUrl, fileUrl, key };
  }

  /** Supprimer une image */
  async deleteImage(fileUrl: string): Promise<void> {
    try {
      const key = fileUrl.split('.amazonaws.com/')[1];
      if (!key) return;
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
    } catch (e) {
      console.error('[S3] Erreur suppression:', e);
    }
  }
}
