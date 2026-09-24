/**
 * Rend privées les captures de paiement déjà déposées.
 *
 * Jusqu'au 24 septembre 2026, les preuves partaient sur S3 en `public-read`
 * (constat S10). Le code n'en dépose plus de publiques ; celles qui existent
 * gardent l'ACL de leur dépôt. Ce script les repasse en privé, une par une,
 * et dit ce qu'il a fait. Il est idempotent : le relancer ne change rien de
 * plus.
 *
 *   npx ts-node scripts/preuves_privees.ts            # constat seul
 *   npx ts-node scripts/preuves_privees.ts --appliquer
 */
import 'dotenv/config';
import {
  GetBucketPolicyStatusCommand, GetPublicAccessBlockCommand, ListObjectsV2Command,
  PutObjectAclCommand, S3Client,
} from '@aws-sdk/client-s3';

const BUCKET = process.env.AWS_S3_BUCKET ?? 'pronowin-uploads';
const s3 = new S3Client({
  region: process.env.AWS_REGION ?? 'eu-west-1',
  credentials: {
    accessKeyId:     process.env.AWS_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
  },
});
const appliquer = process.argv.includes('--appliquer');

async function main() {
  // Une politique de bucket publique rendrait l'ACL sans effet : on le dit.
  try {
    const statut = await s3.send(new GetBucketPolicyStatusCommand({ Bucket: BUCKET }));
    console.log(`Politique du bucket publique : ${statut.PolicyStatus?.IsPublic ? 'OUI — à corriger dans AWS' : 'non'}`);
  } catch (e: any) {
    console.log(`Politique du bucket : ${e.name === 'NoSuchBucketPolicy' ? 'aucune' : 'illisible (' + e.name + ')'}`);
  }
  try {
    const bloc = await s3.send(new GetPublicAccessBlockCommand({ Bucket: BUCKET }));
    console.log('Blocage des accès publics :', JSON.stringify(bloc.PublicAccessBlockConfiguration));
  } catch (e: any) {
    console.log(`Blocage des accès publics : ${e.name === 'NoSuchPublicAccessBlockConfiguration' ? 'non configuré' : 'illisible (' + e.name + ')'}`);
  }

  let jeton: string | undefined;
  let vus = 0, rendus = 0, echecs = 0;
  do {
    const page = await s3.send(new ListObjectsV2Command({
      Bucket: BUCKET, Prefix: 'proofs/', ContinuationToken: jeton,
    }));
    for (const objet of page.Contents ?? []) {
      vus++;
      if (!appliquer || !objet.Key) continue;
      try {
        await s3.send(new PutObjectAclCommand({ Bucket: BUCKET, Key: objet.Key, ACL: 'private' }));
        rendus++;
      } catch (e: any) {
        echecs++;
        console.error(`  échec sur un objet : ${e.name}`);
      }
    }
    jeton = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (jeton);

  console.log(`${vus} capture(s) dans proofs/ — ${appliquer ? `${rendus} rendue(s) privée(s), ${echecs} échec(s)` : 'constat seul, relancer avec --appliquer'}`);
  if (echecs) process.exit(1);
}

main().catch((e) => { console.error('Échec :', e.name ?? e); process.exit(1); });
