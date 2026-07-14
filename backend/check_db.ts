import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function check() {
  console.log('\n=== VÉRIFICATION BASE DE DONNÉES ===\n');

  // 1. Vérifier les colonnes de la table users
  const userCols = await prisma.$queryRaw<any[]>`
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_name = 'users'
    ORDER BY ordinal_position;
  `;
  console.log('📋 Colonnes table USERS :');
  userCols.forEach(c => {
    const isNew = ['first_name','last_name','birth_date'].includes(c.column_name);
    console.log(`  ${isNew ? '✅' : '  '} ${c.column_name} (${c.data_type})`);
  });

  // 2. Vérifier si la table tutorials existe
  const tables = await prisma.$queryRaw<any[]>`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `;
  console.log('\n📋 Tables existantes :');
  const tableNames = tables.map((t: any) => t.table_name);
  tableNames.forEach((t: string) => {
    const isNew = t === 'tutorials';
    console.log(`  ${isNew ? '✅' : '  '} ${t}`);
  });

  const hasTutorials = tableNames.includes('tutorials');
  const hasFirstName = userCols.some(c => c.column_name === 'first_name');
  const hasLastName  = userCols.some(c => c.column_name === 'last_name');
  const hasBirthDate = userCols.some(c => c.column_name === 'birth_date');

  console.log('\n=== RÉSUMÉ ===');
  console.log(`  Table tutorials   : ${hasTutorials ? '✅ OK' : '❌ MANQUANTE'}`);
  console.log(`  Colonne first_name: ${hasFirstName ? '✅ OK' : '❌ MANQUANTE'}`);
  console.log(`  Colonne last_name : ${hasLastName  ? '✅ OK' : '❌ MANQUANTE'}`);
  console.log(`  Colonne birth_date: ${hasBirthDate ? '✅ OK' : '❌ MANQUANTE'}`);

  if (!hasTutorials || !hasFirstName) {
    console.log('\n⚠️  Des éléments manquent → utiliser: npx prisma db push');
  } else {
    console.log('\n🎉 Tout est en ordre !');
  }

  await prisma.$disconnect();
}

check().catch(console.error);
