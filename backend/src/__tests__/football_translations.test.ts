import { market, selection, prediction, round, country, absence, transfer } from '../i18n/football';
import cases from './fixtures/football-translations.json';
import fs from 'fs';
import path from 'path';
import vm from 'vm';

describe('football labels shared by the API and the admin', () => {
  const methods: Record<string, Function> = { market, selection, prediction, round, country, absence, transfer };
  for (const c of cases) for (const language of ['fr', 'en'] as const) {
    it(c.method + ': ' + c.input + ' → ' + language, () => {
      const result = methods[c.method](c.input, language);
      expect(typeof result === 'string' ? result : result.text).toBe(c[language]);
      if (typeof result !== 'string') expect(result.known).toBe(c.known);
    });
  }
  it('substitutes only the actual team tokens, preserves the handicap and raw input', () => {
    const input = 'Home -0.5';
    expect(selection(input, 'fr', 'Netherlands', 'Belgium').text).toBe('Pays-Bas -0,5');
    expect(input).toBe('Home -0.5');
    expect(prediction('Belgique gagne', 'en', 'Netherlands', 'Belgium').text).toBe('Belgium wins');
    expect(selection('Jordan Henderson', 'fr', 'Jordan', 'Belgium')).toEqual({text:'Jordan Henderson', known:false});
  });
  it('runs the same behaviour in the actual browser bundle', () => {
    const context: any = {}; vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../../../admin-web/public/football-i18n.js'), 'utf8'), context);
    for (const c of cases) for (const language of ['fr', 'en'] as const) {
      const result = context.PronoFootball[c.method](c.input, language);
      expect(typeof result === 'string' ? result : result.text).toBe(c[language]);
    }
  });
});
