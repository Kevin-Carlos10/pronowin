"""Remet les divergences du catalogue de repli et exige que la garde les voie.

    python scripts/injections_catalogue.py

Lance depuis backend/.

`catalogue_tutoriels.test.ts` verifie que `DEMO_TUTORIALS` ne verrouille rien
et ne ressuscite pas le tutoriel retire. Un controle qui passe sur du code
correct ne prouve rien : celui-ci remet chaque defaut, exige l'echec, puis
restaure a l'octet pres.
"""
import io
import subprocess
import sys
import time

CHEMIN = 'src/services/tutorial.service.ts'
TEST   = 'src/__tests__/catalogue_tutoriels.test.ts'

DEFAUTS = [
    ("un tutoriel de repli redevient Premium",
     "    is_premium: false, view_count: 0, rating: 0, author_name: 'Expert PronoWin',\n"
     "    thumbnail_url: null, video_url: null, has_video: false,\n"
     "    published_at: new Date().toISOString(),\n"
     "  },\n"
     "  {\n"
     "    id: 'tut_004'",
     "    is_premium: true, view_count: 0, rating: 0, author_name: 'Expert PronoWin',\n"
     "    thumbnail_url: null, video_url: null, has_video: false,\n"
     "    published_at: new Date().toISOString(),\n"
     "  },\n"
     "  {\n"
     "    id: 'tut_004'"),
    ("le tutoriel retire ressuscite par le repli",
     "];",
     "  {\n"
     "    id: 'tut_005', title: 'Strategie des handicaps asiatiques',\n"
     "    description: 'x', level: 'advanced', category: 'strategie',\n"
     "    duration_seconds: 900, is_premium: false, view_count: 0, rating: 0,\n"
     "    author_name: 'Expert PronoWin', thumbnail_url: null, video_url: null,\n"
     "    has_video: false, published_at: new Date().toISOString(),\n"
     "  },\n"
     "];"),
]


def restaurer(chemin, octets, essais=12):
    """Remet le fichier d'origine, en insistant.

    Sous Windows, un antivirus ou un processus qui lit le meme fichier fait
    echouer l'ouverture en ecriture (EBUSY, EPERM, EINVAL). Ce sont des echecs
    transitoires.

    Sans ces reessais, ce banc a deja laisse un `is_premium: true` injecte dans
    l'arbre de travail : le paywall etait de retour dans le code, et seul un
    `grep` de verification l'a montre. Un outil qui remet volontairement un
    defaut doit le retirer meme quand tout va mal, sinon il devient la panne.
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
                print('  Le fichier contient encore le defaut injecte.')
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
        r = subprocess.run(['npx', 'jest', TEST], capture_output=True, shell=True)
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
