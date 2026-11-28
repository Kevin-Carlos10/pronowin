"""Remet les defauts de la page d'abonnement et exige que la garde les voie.

    python tool/injections_avantages.py

Lance depuis mobile_new/.

`avantages_premium_test.dart` verifie que la page qui demande 15 $ par mois ne
promet rien qu'elle ne livre. Un controle qui passe sur du code correct ne
prouve rien : celui-ci remet chaque defaut, exige l'echec, puis restaure a
l'octet pres.
"""
import io
import subprocess
import sys
import time

CHEMIN = 'lib/features/compte/presentation/pages/compte_page.dart'
TEST   = 'test/avantages_premium_test.dart'

DEFAUTS = [
    ("le compte d'avantages redevient un litteral",
     "child: Text('${features.length} avantages', style: const TextStyle(",
     "child: const Text('5 avantages', style: TextStyle("),
    ("la page revend l'acces aux tutoriels",
     "    (Icons.headset_mic_rounded,   'Support prioritaire',       'Vos demandes traitées en priorité'),",
     "    (Icons.play_lesson_rounded,   'Tous les tutoriels',        'Bibliothèque complète débloquée'),\n"
     "    (Icons.headset_mic_rounded,   'Support prioritaire',       'Vos demandes traitées en priorité'),"),
    ("un avantage repromet un delai chiffre",
     "'Support prioritaire',       'Vos demandes traitées en priorité'",
     "'Support prioritaire',       'Réponse sous 2h ouvrées'"),
]


def restaurer(chemin, octets, essais=12):
    """Remet le fichier d'origine, en insistant.

    Sous Windows, un antivirus ou un processus qui lit le meme fichier fait
    echouer l'ouverture en ecriture (EBUSY, EPERM, EINVAL) — echecs
    transitoires, que quelques essais espaces suffisent a passer.

    Sans ces reessais, un banc jumeau a deja laisse un defaut injecte dans
    l'arbre de travail. Un outil qui remet volontairement un defaut doit le
    retirer meme quand tout va mal, sinon il devient lui-meme la panne.
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
        r = subprocess.run(['flutter', 'test', TEST], capture_output=True, shell=True)
        vu = r.returncode != 0
    finally:
        restaurer(CHEMIN, octets)

    print(('  DETECTE %s' if vu else '  NON DETECTE %s') % nom)
    if not vu:
        print('          -> le defaut passe : la garde ne garde rien')
        echecs += 1

print('')
print('  %d/%d injections detectees' % (len(DEFAUTS) - echecs, len(DEFAUTS)))
sys.exit(1 if echecs else 0)
