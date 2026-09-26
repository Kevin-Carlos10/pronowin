/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  // Pose le secret de délégation avant tout import : le middleware
  // d'administration refuse de se charger sans lui, et une suite qui
  // importe une route protégée mourait avant son premier test.
  setupFiles: ['<rootDir>/jest.setup.js'],
  // 5 s par défaut. Plusieurs bancs chargent leurs modules dans le test
  // lui-même (jest.resetModules puis require), et ts-jest les compile à ce
  // moment : avec un worker par cœur, le premier test d'un tel fichier
  // dépassait parfois 5 s sans rien de bloqué (amorcage_admin, une suite sur
  // deux). 20 s laisse la compilation finir et arrête toujours un test qui
  // attend une réponse qui ne viendra pas.
  testTimeout: 20_000,
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/index.ts',
    '!src/**/*.routes.ts',
  ],
  coverageReporters: ['text', 'lcov'],
};
