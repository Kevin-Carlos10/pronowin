/**
 * Dérive des saisons de repli.
 *
 * `LEAGUE_MAP` porte une saison codée en dur par compétition. Elle ne sert plus
 * qu'en cas d'échec de l'appel API — mais un repli périmé reste un repli faux,
 * et c'est précisément ce qui a produit le défaut d'origine : en août 2026, les
 * six championnats servaient encore la table finale de 2025-2026.
 *
 * Ce défaut n'est visible d'aucun test unitaire ni d'aucun contrôle de type :
 * le classement se charge, se rend parfaitement, et ment. Seule une
 * confrontation à l'API le révèle.
 *
 *   npx ts-node _check_saisons.ts
 *
 * À lancer chaque rentrée (~août), ou dans une tâche planifiée mensuelle.
 * Sortie non nulle si un repli a divergé.
 */
import 'dotenv/config';
import { LEAGUE_INFO, saisonCourante } from './src/services/api_football.service';

const CODES = ['WC', 'PL', 'BL1', 'SA', 'PD', 'FL1', 'CL'];

(async () => {
  if (!process.env.API_FOOTBALL_KEY) {
    console.error('API_FOOTBALL_KEY absente — contrôle impossible.');
    process.exit(2);
  }

  console.log('code   id     repli    courante   verdict');
  console.log('─────────────────────────────────────────────────');

  const derives: string[] = [];

  for (const code of CODES) {
    const info = LEAGUE_INFO(code);
    if (!info) { console.log(`${code.padEnd(6)} — inconnu de LEAGUE_MAP`); continue; }

    const courante = await saisonCourante(code);
    const ok = courante === info.season;
    if (!ok) derives.push(`${code} : repli ${info.season}, courante ${courante}`);

    console.log(
      code.padEnd(6),
      String(info.id).padEnd(6),
      String(info.season).padEnd(8),
      String(courante ?? '?').padEnd(10),
      ok ? 'à jour' : 'PÉRIMÉ',
    );
  }

  console.log();
  if (derives.length === 0) {
    console.log('Tous les replis correspondent à la saison en cours.');
    process.exit(0);
  }

  console.log(`${derives.length} repli(s) périmé(s) :`);
  derives.forEach(d => console.log(`  · ${d}`));
  console.log();
  console.log('Mettre à jour LEAGUE_MAP dans src/services/api_football.service.ts.');
  console.log('L\'app reste juste tant que l\'API répond — mais elle servira ces');
  console.log('valeurs fausses à la première panne réseau.');
  process.exit(1);
})();
