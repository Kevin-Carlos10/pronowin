import fs from 'fs';
import {codeSeul} from './aides/code_seul';
import path from 'path';
const root=path.join(__dirname,'../../..');
describe('la vitrine utilise la note réelle sur cinq',()=>{
  const source=fs.readFileSync(path.join(root,'website/server.js'),'utf8');
  it('montre des notes valides, sans fausse probabilité',()=>{
    const notes=[...codeSeul(source).matchAll(/Confiance (\d+)\/5/g)].map(m=>Number(m[1]));
    expect(notes.length).toBeGreaterThan(0);
    expect(notes.every(n=>n>=1&&n<=5)).toBe(true);
    expect(codeSeul(source)).not.toMatch(/Confiance \d+\s*%/);
  });
  it('conserve la règle de fidélité au produit',()=>expect(source).toContain('doit exister dans le produit'));
});
