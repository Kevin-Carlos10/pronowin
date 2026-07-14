import { PrismaClient } from '@prisma/client';

// Singleton pour éviter d'épuiser le pool de connexions PostgreSQL
// (une seule instance partagée entre tous les services/controllers)
const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
