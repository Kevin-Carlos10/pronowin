import { ecrireConfig, lireConfig } from '../services/app_config.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

/**
 * On ne peut pas exiger une version qu'on ne publie pas.
 *
 * C'est la faute de configuration qui enferme les utilisateurs, et elle se fait
 * en deux clics depuis le panneau : relever `APK_MIN_VERSION` avant d'avoir mis
 * le nouvel APK en ligne.
 *
 * Sur le canal direct, l'APK ne se met pas à jour tout seul. Le blocage affiche
 * une fenêtre dont l'unique bouton télécharge le fichier publié. Si le seuil
 * exige une version que ce fichier ne contient pas, l'utilisateur télécharge,
 * installe, relance — et retrouve la même fenêtre. À chaque lancement, sans
 * issue, jusqu'à ce qu'un administrateur le remarque.
 *
 * Le format de chaque champ était vérifié — une URL doit commencer par http,
 * une version doit ressembler à « x.y.z » — mais jamais la cohérence entre
 * eux. Deux valeurs individuellement valides suffisaient donc à produire une
 * configuration qui bloque tout le monde.
 *
 * La validation porte sur l'état **résultant**, pas sur ce que le formulaire
 * envoie : relever le minimum seul, sans toucher au reste, doit être refusé en
 * le comparant à la dernière version déjà enregistrée.
 */
decrireSurBaseLocale('seuils de mise à jour', () => {
  // Toutes les clés que ce banc écrit — pas seulement celles qu'il vérifie.
  //
  // La première version n'en restaurait que quatre et oubliait
  // `APP_UPDATE_MESSAGE`. Une exécution du banc d'injection, guard retiré, a
  // donc laissé « ce message ne doit pas etre enregistre » dans la
  // configuration ; l'exécution suivante a echoué en accusant le code, qui
  // était correct. Un banc qui ne nettoie pas derrière lui finit par accuser
  // à tort — ou pire, par faire passer un défaut.
  //
  // La configuration est partagée : `ecrireConfig` écrit en base, et c'est la
  // base que sert `GET /config` à toutes les applications installées.
  const CLES = [
    'APP_MIN_VERSION', 'APP_LATEST_VERSION',
    'APK_MIN_VERSION', 'APK_LATEST_VERSION',
    'APP_UPDATE_MESSAGE',
  ] as const;

  const initial: Record<string, string> = {};

  beforeAll(async () => {
    const { valeurs } = await lireConfig();
    for (const c of CLES) initial[c] = valeurs[c as keyof typeof valeurs] as string;
  });

  afterAll(async () => {
    // Remise dans l'état trouvé, sans quoi le test suivant partirait d'un état
    // qu'il n'a pas choisi.
    await ecrireConfig(initial, 'test');
    const { valeurs } = await lireConfig();
    for (const c of CLES) {
      if (valeurs[c as keyof typeof valeurs] !== initial[c]) {
        throw new Error(
          `Restauration incomplète : ${c} vaut `
        + `« ${valeurs[c as keyof typeof valeurs]} » au lieu de « ${initial[c]} ».`);
      }
    }
  });

  it('refuse un minimum supérieur à la dernière version publiée', async () => {
    await expect(ecrireConfig({
      APK_MIN_VERSION:    '2.0.0',
      APK_LATEST_VERSION: '1.0.5',
    }, 'test')).rejects.toThrow(/dépasse la dernière version publiée/);
  });

  it('refuse aussi quand seul le minimum bouge', async () => {
    // Le cas réel : l'administrateur relève le seuil depuis le panneau sans
    // toucher au reste. La validation doit comparer à ce qui est déjà
    // enregistré, pas seulement aux champs envoyés.
    await ecrireConfig({ APK_LATEST_VERSION: '1.0.5' }, 'test');
    await expect(ecrireConfig({ APK_MIN_VERSION: '1.9.0' }, 'test'))
      .rejects.toThrow(/dépasse la dernière version publiée/);
  });

  it('accepte un minimum égal ou inférieur', async () => {
    // Sans ce point, une validation qui refuserait tout passerait les deux
    // précédents sans laisser configurer quoi que ce soit.
    await expect(ecrireConfig({
      APK_MIN_VERSION:    '1.0.5',
      APK_LATEST_VERSION: '1.0.5',
    }, 'test')).resolves.toBeDefined();

    await expect(ecrireConfig({
      APK_MIN_VERSION:    '1.0.0',
      APK_LATEST_VERSION: '1.0.5',
    }, 'test')).resolves.toBeDefined();
  });

  it('compare les nombres, pas les chaînes', async () => {
    // « 1.10.0 » est postérieur à « 1.9.0 ». Une comparaison lexicographique
    // dirait l'inverse et refuserait une configuration parfaitement valide —
    // ou, pire, en accepterait une qui bloque.
    await expect(ecrireConfig({
      APK_MIN_VERSION:    '1.9.0',
      APK_LATEST_VERSION: '1.10.0',
    }, 'test')).resolves.toBeDefined();
  });

  it('applique la même règle au canal store', async () => {
    await expect(ecrireConfig({
      APP_MIN_VERSION:    '3.0.0',
      APP_LATEST_VERSION: '1.0.0',
    }, 'test')).rejects.toThrow(/store/);
  });

  it('n\'écrit rien quand la validation échoue', async () => {
    // Une validation au fil de l'écriture laisserait la moitié des clés
    // enregistrées : une configuration à moitié appliquée, c'est-à-dire
    // exactement l'état qu'on cherche à interdire.
    await ecrireConfig({ APK_MIN_VERSION: '1.0.0', APK_LATEST_VERSION: '1.0.5' }, 'test');

    await expect(ecrireConfig({
      APK_MIN_VERSION:  '9.0.0',
      APP_UPDATE_MESSAGE: 'ce message ne doit pas etre enregistre',
    }, 'test')).rejects.toThrow();

    const { valeurs } = await lireConfig();
    expect(valeurs.APK_MIN_VERSION).toBe('1.0.0');
    expect(valeurs.APP_UPDATE_MESSAGE).not.toBe('ce message ne doit pas etre enregistre');
  });
});
