import fs from 'fs';
import {codeSeul} from './aides/code_seul';
import path from 'path';
import {POURCENTAGE_MAX,POURCENTAGE_MIN} from '../utils/confiance';
const root=path.join(__dirname,'../../..');
// Depuis le 1er octobre 2026, l'indice de confiance est un pourcentage que
// l'analyste saisit (1–99, jamais 100). La vitrine ne peut montrer que des
// valeurs que la saisie accepte, et doit dire ce que ce chiffre n'est pas.
describe("la vitrine montre l'indice de confiance tel que l'analyste le saisit",()=>{
  const source=fs.readFileSync(path.join(root,'website/server.js'),'utf8');
  it('des pourcentages que la saisie accepte, et plus de note sur cinq',()=>{
    const code=codeSeul(source);
    const pcts=[...code.matchAll(/Confiance (\d+) %/g)].map(m=>Number(m[1]));
    expect(pcts.length).toBeGreaterThan(0);
    expect(pcts.every(n=>n>=POURCENTAGE_MIN&&n<=POURCENTAGE_MAX)).toBe(true);
    expect(code).not.toMatch(/Confiance \d+\/5/);
  });
  it("dit que c'est une appréciation, pas une probabilité",()=>
    expect(source).toContain('pas une probabilité de gain'));
  it('conserve la règle de fidélité au produit',()=>expect(source).toContain('doit exister dans le produit'));
});
