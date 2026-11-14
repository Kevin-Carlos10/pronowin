"""Remet les trois fuites de contenu payant et exige que la garde les voie.

    python tool/injections_paywall.py

Lance depuis backend/.

`src/__tests__/verrou_paywall.test.ts` verifie que le contenu payant ne quitte
pas le serveur sans passer par `estVerrouille`. Un controle qui passe sur du
code correct ne prouve rien : celui-ci remet chaque fuite, exige l'echec, puis
restaure a l'octet pres.
"""
import io
import subprocess
import sys
import time

TEST = 'src/__tests__/verrou_paywall.test.ts'

NOTIF = 'src/services/notification.service.ts'
FAV   = 'src/controllers/favorites.controller.ts'

# « Pour Toi » n'y figure pas : sa route porte premiumMiddleware, donc il n'y a
# pas de fuite a rejouer. Le test le documente comme exception.
DEFAUTS = [
    (NOTIF, "la notification revele a nouveau le pronostic VIP",
     "    const affiche = params.isPremium ? 'pronostic VIP disponible'\n"
     "                                     : params.predictionLabel;\n"
     "    const body    = isLive\n"
     "      ? `${params.homeTeam} vs ${params.awayTeam} en cours — ${affiche}`\n"
     "      : `${params.homeTeam} vs ${params.awayTeam} — ${affiche}`;",
     "    const body    = isLive\n"
     "      ? `${params.homeTeam} vs ${params.awayTeam} en cours — ${params.predictionLabel}`\n"
     "      : `${params.homeTeam} vs ${params.awayTeam} — ${params.predictionLabel}`;"),
    (FAV, "les favoris relivrent la decision payante",
     "        prediction_label: locked ? null : (p?.predictionLabel ?? ''),",
     "        prediction_label: p?.predictionLabel ?? '',"),
    ('src/routes/pronostics.routes.ts',
     "l'analyse d'un match joue redevient reservee aux abonnes",
     "r.get ('/:id/ai-analyze',  authMiddleware, premiumSaufMatchTermine, C.getAiAnalysis);",
     "r.get ('/:id/ai-analyze',  authMiddleware, premiumMiddleware, C.getAiAnalysis);"),
]


def restaurer(chemin, octets, essais=12):
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
    sys.exit('  ECHEC DE RESTAURATION : contenu different')


echecs = 0
for chemin, nom, sain, corrompu in DEFAUTS:
    octets = io.open(chemin, 'rb').read()
    texte = octets.decode('utf-8')
    saut = '\r\n' if b'\r\n' in octets else '\n'
    sain_n     = sain.replace('\n', saut)
    corrompu_n = corrompu.replace('\n', saut)

    if texte.count(sain_n) != 1:
        print('  ANCRE   %s : %d occurrence(s)' % (nom, texte.count(sain_n)))
        echecs += 1
        continue

    vu = None
    try:
        io.open(chemin, 'w', encoding='utf-8', newline='').write(
            texte.replace(sain_n, corrompu_n))
        r = subprocess.run(['npx', 'jest', TEST], capture_output=True, shell=True)
        vu = r.returncode != 0
    finally:
        restaurer(chemin, octets)

    print(('  DETECTE %s' if vu else '  NON DETECTE %s') % nom)
    if not vu:
        echecs += 1

print('')
print('  %d/%d injections detectees' % (len(DEFAUTS) - echecs, len(DEFAUTS)))
sys.exit(1 if echecs else 0)
