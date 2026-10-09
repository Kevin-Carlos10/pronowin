/**
 * Rend privées les captures de paiement déjà déposées.
 *
 * Jusqu'au 24 septembre 2026, les preuves partaient sur S3 en `public-read`
 * (constat S10). Le code n'en dépose plus de publiques. Il reste deux choses
 * que le code ne peut pas défaire seul :
 *
 *  - les captures déjà déposées gardent l'ACL publique de leur dépôt ;
 *  - la politique du bucket, relevée le 24 septembre 2026, accorde
 *    `s3:GetObject` à tout le monde sur `arn:aws:s3:::<bucket>/*` — c'est-à-dire
 *    sur les preuves aussi, quelle que soit leur ACL.
 *
 * Ce script fait le constat, et sur demande corrige les deux : ACL privée pour
 * chaque objet de `proofs/`, et lecture publique de la politique ramenée au
 * seul dossier `avatars/`, que l'application affiche à tout le monde. Il est
 * idempotent.
 *
 *   npx ts-node --transpile-only scripts/preuves_privees.ts                 # constat
 *   npx ts-node --transpile-only scripts/preuves_privees.ts --appliquer     # ACL des preuves
 *   npx ts-node --transpile-only scripts/preuves_privees.ts --corriger-politique
 */
import 'dotenv/config';
import {
  GetBucketPolicyCommand, GetBucketPolicyStatusCommand, GetPublicAccessBlockCommand,
  ListObjectsV2Command, PutBucketPolicyCommand, PutObjectAclCommand, S3Client,
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
const corrigerPolitique = process.argv.includes('--corriger-politique');

/** Le seul dossier que tout le monde doit pouvoir lire. */
const DOSSIER_PUBLIC = 'avatars/';

async function politique(): Promise<any | null> {
  try {
    const p = await s3.send(new GetBucketPolicyCommand({ Bucket: BUCKET }));
    return p.Policy ? JSON.parse(p.Policy) : null;
  } catch (e: any) {
    if (e.name === 'NoSuchBucketPolicy') return null;
    throw e;
  }
}

/** La politique, où toute lecture publique du bucket entier est ramenée aux avatars. */
function politiqueCorrigee(p: any): { politique: any; changements: number } {
  let changements = 0;
  const toutLeBucket = `arn:aws:s3:::${BUCKET}/*`;
  const dossierPublic = `arn:aws:s3:::${BUCKET}/${DOSSIER_PUBLIC}*`;
  const statements = (p.Statement ?? []).map((st: any) => {
    const public_ = st.Effect === 'Allow'
      && (st.Principal === '*' || st.Principal?.AWS === '*');
    if (!public_) return st;
    const ressources = Array.isArray(st.Resource) ? st.Resource : [st.Resource];
    if (!ressources.includes(toutLeBucket)) return st;
    changements++;
    const nouvelles = ressources.map((r: string) => (r === toutLeBucket ? dossierPublic : r));
    return { ...st, Resource: nouvelles.length === 1 ? nouvelles[0] : nouvelles };
  });
  return { politique: { ...p, Statement: statements }, changements };
}

async function statutPolitique(): Promise<string> {
  try {
    const statut = await s3.send(new GetBucketPolicyStatusCommand({ Bucket: BUCKET }));
    return statut.PolicyStatus?.IsPublic ? 'publique' : 'non publique';
  } catch (e: any) {
    return e.name === 'NoSuchBucketPolicy' ? 'aucune' : `illisible (${e.name})`;
  }
}

async function main() {
  const p = await politique();
  console.log(`Politique du bucket : ${await statutPolitique()}`);
  if (p) {
    const { politique: corrigee, changements } = politiqueCorrigee(p);
    if (changements === 0) {
      console.log('  aucune lecture publique du bucket entier.');
    } else if (!corrigerPolitique) {
      console.log(`  ${changements} règle(s) ouvrent tout le bucket, preuves comprises —`
        + ' relancer avec --corriger-politique pour les ramener à avatars/.');
    } else {
      await s3.send(new PutBucketPolicyCommand({ Bucket: BUCKET, Policy: JSON.stringify(corrigee) }));
      console.log(`  corrigée : lecture publique limitée à ${DOSSIER_PUBLIC} (${changements} règle(s)).`);
      console.log(JSON.stringify(corrigee, null, 2));
    }
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

  console.log(`${vus} capture(s) dans proofs/ — ${appliquer
    ? `${rendus} rendue(s) privée(s), ${echecs} échec(s)`
    : 'ACL inchangées, relancer avec --appliquer'}`);
  if (corrigerPolitique) console.log(`Politique après correction : ${await statutPolitique()}`);
  if (echecs) process.exit(1);
}

main().catch((e) => { console.error('Échec :', e.name ?? e); process.exit(1); });
