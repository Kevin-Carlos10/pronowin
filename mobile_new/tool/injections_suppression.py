"""Remet les promesses fausses de l'ecran de suppression et exige l'echec.

    python tool/injections_suppression.py

Lance depuis mobile_new/.

`suppression_compte_test.dart` verifie que l'ecran ne promet pas plus que le
serveur ne fait. Un controle qui passe sur du code correct ne prouve rien :
celui-ci remet chaque defaut, exige l'echec, puis restaure a l'octet pres.
"""
import io
import subprocess
import sys
import time

CHEMIN = 'lib/features/parametres/presentation/pages/parametres_page.dart'
TEST   = 'test/suppression_compte_test.dart'

DEFAUTS = [
    ("le bouton repromet un effacement definitif",
     "              subtitle: 'Fermer ton compte et effacer tes informations',",
     "              subtitle: 'Effacer définitivement tes données',"),
    ("l'ecran repromet la resiliation de l'abonnement",
     "          _DeleteWarning(widget.ref.read(isStoreBuildProvider)\n"
     "              ? 'Ton abonnement n\\'est pas résilié : fais-le depuis le Play Store'\n"
     "              : 'Ton abonnement n\\'est ni résilié ni remboursé'),",
     "          _DeleteWarning('Ton abonnement Premium sera annulé'),"),
    ("l'historique est a nouveau annonce comme efface",
     "          _DeleteWarning('Ton historique est conservé sous forme anonyme'),",
     "          _DeleteWarning('Ton historique sera effacé définitivement'),"),
]


def restaurer(chemin, octets, essais=12):
    """Remet le fichier d'origine, en insistant.

    Sous Windows, un antivirus ou un processus qui lit le meme fichier fait
    echouer l'ouverture en ecriture (EBUSY, EPERM, EINVAL) — echecs
    transitoires. Sans ces reessais, un banc jumeau a deja laisse un defaut
    injecte dans l'arbre de travail.
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

# Le fichier est en CRLF. Les ancres sont ecrites avec des `\n` simples, et
# celle qui couvrait trois lignes ne mordait donc pas : « 0 occurrence(s) ».
# Une ancre qui ne trouve rien ressemble a s'y meprendre a un banc qui tourne.
SAUT = '\r\n' if b'\r\n' in octets else '\n'

echecs = 0

for nom, sain, corrompu in DEFAUTS:
    sain     = sain.replace('\n', SAUT)
    corrompu = corrompu.replace('\n', SAUT)

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
