"""Casse le cablage du drapeau de compilation et exige que le test le voie.

    python tool/injections_drapeau.py

Lance depuis mobile_new/. Enchaine par tool/verifier_canal.ps1.

canal_drapeau_test.dart controle que --dart-define=STORE_BUILD parvient au
provider. Un controle qui passe sur du code correct ne prouve rien : celui-ci
remet le defaut, exige l'echec, puis restaure a l'octet pres.

Trois defauts, chacun plausible :

  1. le nom de la variable d'environnement change (faute de frappe, renommage) ;
  2. la comparaison se trompe de sens (le canal direct devient le defaut) ;
  3. le provider repond toujours « store » (garde qui ne garde plus rien mais
     qui reste verte sur un test a sens unique).

Restaure a l'octet pres, y compris si la commande de test echoue autrement.
"""
import io
import subprocess
import sys
import time


def restaurer(chemin, octets, essais=12):
    """Remet le fichier d'origine, en insistant.

    Sous Windows, un antivirus ou un processus qui lit le meme fichier fait
    echouer l'ouverture en ecriture (EBUSY, EPERM, EINVAL) — echecs
    transitoires, que quelques essais espaces suffisent a passer.

    Sans ces reessais, un banc jumeau a laisse un defaut injecte dans l'arbre
    de travail : le code portait a nouveau le bug, et rien ne le disait. Un
    outil qui remet volontairement un defaut doit le retirer meme quand tout
    va mal, sinon il devient lui-meme la panne.
    """
    for i in range(essais):
        try:
            with io.open(chemin, 'wb') as f:
                f.write(octets)
            if io.open(chemin, 'rb').read() == octets:
                return
        except OSError as e:
            if i == essais - 1:
                print('\n  ECHEC DE RESTAURATION : %s (%s)' % (chemin, e))
                print('  Restaurez-le : git checkout -- %s\n' % chemin)
                sys.exit(2)
        time.sleep(0.15)
    print('\n  ECHEC DE RESTAURATION : %s (contenu different)' % chemin)
    sys.exit(2)

CHEMIN = 'lib/core/config/distribution_channel.dart'

DEFAUTS = [
    ("le nom de la variable change",
     "String.fromEnvironment('STORE_BUILD')",
     "String.fromEnvironment('STORE_BUILDS')"),
    ("la comparaison change de sens",
     "return _drapeau == 'false' ? CanalDistribution.direct : CanalDistribution.store;",
     "return _drapeau == 'true' ? CanalDistribution.direct : CanalDistribution.store;"),
    ("le provider repond toujours store",
     "(ref) => ref.watch(canalDistributionProvider) == CanalDistribution.store,",
     "(ref) => true,"),
]

octets = io.open(CHEMIN, 'rb').read()
texte = octets.decode('utf-8')
echecs = 0

for nom, sain, corrompu in DEFAUTS:
    if texte.count(sain) != 1:
        print('  ANCRE   %s : %d occurrence(s), attendu 1' % (nom, texte.count(sain)))
        echecs += 1
        continue

    vu = None
    try:
        io.open(CHEMIN, 'w', encoding='utf-8', newline='').write(
            texte.replace(sain, corrompu))
        # Les deux sens : un defaut peut ne mordre que sur l'une des valeurs.
        resultats = []
        for v in ('true', 'false'):
            r = subprocess.run(
                ['flutter', 'test', 'test/canal_drapeau_test.dart',
                 '--dart-define=STORE_BUILD=' + v],
                capture_output=True, shell=True)
            resultats.append(r.returncode != 0)
        vu = any(resultats)
    finally:
        restaurer(CHEMIN, octets)

    if vu:
        print('  DETECTE %s' % nom)
    else:
        print('  NON DETECTE %s' % nom)
        print('          -> le defaut passe : la garde ne garde rien')
        echecs += 1

print('')
print('  %d/%d injections detectees' % (len(DEFAUTS) - echecs, len(DEFAUTS)))
sys.exit(1 if echecs else 0)
