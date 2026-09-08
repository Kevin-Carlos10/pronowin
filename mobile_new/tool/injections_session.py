"""Remet les defauts de session et exige que les controles les voient.

    python tool/injections_session.py

Lance depuis mobile_new/.

Deux defauts, tous deux constates en production :

  1. le rejeu qui echoue renvoie le 401 d'origine. Un delai depasse devient
     alors « pas de compte », et les ecrans proposent d'en creer un a des
     utilisateurs connectes ;

  2. la requete rejouee n'est pas marquee. Son propre 401 relance un
     rafraichissement, qui rejoue, qui recoit un 401 : boucle sans fin contre
     le serveur.

Un controle qui passe sur du code correct ne prouve rien. Celui-ci remet le
defaut, exige l'echec, puis restaure a l'octet pres. Une injection qui ne
casse rien est un echec du banc, pas un succes du code.
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

TEST = 'test/rejeu_apres_refresh_test.dart'

DIO    = 'lib/core/network/dio_client.dart'
ECRAN  = 'lib/features/pronostics/presentation/pages/match_detail/analyse_ia.dart'

DEFAUTS = [
    (DIO, "un rejeu rate se fait passer pour une absence de compte",
     "                return handler.next(\n"
     "                  retryErr is DioException ? retryErr : error);",
     "                return handler.next(error);"),
    (DIO, "la requete rejouee n'est plus marquee (boucle sans fin)",
     "              error.requestOptions.extra[_dejaRejoue] = true;\n",
     ""),
    (ECRAN, "l'ecran rededuit l'absence de compte du seul code HTTP",
     "if (code == 401 && !ref.watch(effectiveLoggedInProvider)) {",
     "if (code == 401) {"),
]

echecs = 0

for chemin, nom, sain, corrompu in DEFAUTS:
    octets = io.open(chemin, 'rb').read()
    texte = octets.decode('utf-8')

    if texte.count(sain) != 1:
        print('  ANCRE   %s : %d occurrence(s), attendu 1' % (nom, texte.count(sain)))
        echecs += 1
        continue

    vu = None
    try:
        io.open(chemin, 'w', encoding='utf-8', newline='').write(
            texte.replace(sain, corrompu))
        r = subprocess.run(['flutter', 'test', TEST],
                           capture_output=True, shell=True)
        vu = r.returncode != 0
    finally:
        restaurer(chemin, octets)

    if vu:
        print('  DETECTE %s' % nom)
    else:
        print('  NON DETECTE %s' % nom)
        print('          -> le defaut passe : la garde ne garde rien')
        echecs += 1

print('')
print('  %d/%d injections detectees' % (len(DEFAUTS) - echecs, len(DEFAUTS)))
sys.exit(1 if echecs else 0)
