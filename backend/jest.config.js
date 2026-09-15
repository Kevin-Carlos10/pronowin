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
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/index.ts',
    '!src/**/*.routes.ts',
  ],
  coverageReporters: ['text', 'lcov'],
};
