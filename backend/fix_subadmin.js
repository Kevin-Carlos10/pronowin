const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcrypt');
const prisma = new PrismaClient();

async function fix() {
  const hash = await bcrypt.hash('1234567890', 10);
  const r = await prisma.subAdmin.update({
    where: { username: 'jean_martin' },
    data:  { passwordHash: hash },
  });
  console.log('✅ Mot de passe mis à jour pour', r.username);
}

fix().catch(console.error).finally(() => prisma.$disconnect());
