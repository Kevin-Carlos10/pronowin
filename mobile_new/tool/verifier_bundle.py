#!/usr/bin/env python3
"""Verifie qu'un App Bundle est publiable — en lisant le binaire, pas le code.

    python tool/verifier_bundle.py [chemin] [direct|play]

Pourquoi ce controle existe
---------------------------

Le 10 septembre 2026, deux versions ont ete construites avec
`flutter build appbundle --release` au lieu de `tool/build.ps1`. Sans les
`--dart-define`, `API_BASE_URL` retombe sur son defaut :

    defaultValue: 'http://10.0.2.2:3000/api/v1'

`10.0.2.2` est l'alias par lequel un emulateur Android joint la machine de
developpement. Le binaire compile, s'installe, se lance, affiche l'accueil — et
ne peut joindre aucun serveur. Les testeurs voient « Impossible de joindre le
serveur ».

Rien ne le signalait : ni la compilation, ni `flutter analyze`, ni les 456
tests, qui s'executent sur le code source et pas sur l'artefact. Le defaut ne
vit que dans le binaire produit.

Ce controle regarde donc l'artefact lui-meme. Les constantes Dart sont
compilees dans `libapp.so` : l'adresse retenue y figure en clair.
"""
import re
import sys
import zipfile

ATTENDU = 'https://pronowin.space/api/v1'

# La permission qui autorise une application a installer un paquet.
#
# Elle est indispensable au canal direct, qui telecharge et installe lui-meme
# ses mises a jour. Elle est interdite au canal store : la politique « Device
# and Network Abuse » reserve l'installation d'APK hors Play aux boutiques
# d'applications, et sa presence dans un AAB n'est pas une mise a jour refusee
# mais un motif de retrait.
#
# La separation est faite par `productFlavors` — seul `src/direct` declare la
# permission. Ce controle-ci ne lit pas cette intention : il ouvre l'artefact
# produit et regarde ce qu'il contient vraiment. C'est la meme lecon que
# l'adresse de l'API : un defaut qui ne vit que dans le binaire ne se voit
# qu'en ouvrant le binaire.
INSTALLATION = 'REQUEST_INSTALL_PACKAGES'

# Une permission dont on sait qu'elle est declaree, dans les deux variantes.
#
# Elle ne sert qu'a prouver qu'on lit bien le manifeste : sans elle, un
# manifeste illisible rendrait « permission absente » pour toutes les
# permissions, y compris celle qu'on cherche.
TEMOIN = 'android.permission.INTERNET'

# Adresses qui n'ont rien a faire dans un binaire distribue.
LOCALES = ['10.0.2.2', '127.0.0.1', 'localhost', '192.168.']

DEFAUT = 'build/app/outputs/bundle/release/app-release.aab'


def libs(z):
    """Le code Dart compile, toutes architectures confondues.

    Un AAB range ses bibliotheques sous `base/lib/<abi>/`, un APK sous
    `lib/<abi>/`. Le suffixe suffit a couvrir les deux.
    """
    return [n for n in z.namelist() if n.endswith('libapp.so')]


def manifeste(z):
    """Le manifeste, quel que soit le format d'archive.

    AAB : `base/manifest/AndroidManifest.xml`, en protobuf.
    APK : `AndroidManifest.xml` a la racine, en XML binaire Android.

    Les deux gardent le nom du paquet et la version en clair, ce qui suffit
    ici — on cherche des chaines, pas une lecture structuree.
    """
    for chemin in ('base/manifest/AndroidManifest.xml', 'AndroidManifest.xml'):
        try:
            return z.read(chemin)
        except KeyError:
            continue
    return b''


def canal_attendu(argv, chemin):
    """Le canal annonce, ou devine a partir du nom de l'artefact.

    `build.ps1` le passe explicitement. En ligne de commande il est facultatif,
    parce qu'un controle qu'on ne peut pas lancer simplement ne se lance pas.
    """
    if len(argv) > 2 and argv[2] in ('direct', 'play'):
        return argv[2]
    if 'direct' in chemin:
        return 'direct'
    if 'play' in chemin:
        return 'play'
    return None


def main():
    chemin = sys.argv[1] if len(sys.argv) > 1 else DEFAUT
    canal = canal_attendu(sys.argv, chemin)
    try:
        z = zipfile.ZipFile(chemin)
    except (OSError, zipfile.BadZipFile) as e:
        print(f'X  {chemin} illisible : {e}')
        return 1

    echecs = []
    ok = lambda m: print('  OK ' + m)
    ko = lambda m: (print('  X  ' + m), echecs.append(m))

    print(f'\n{chemin}\n')

    # ── L'adresse de l'API ──
    binaires = libs(z)
    octets = b''.join(z.read(n) for n in binaires)

    # Un artefact de debogage n'a pas de `libapp.so` : le code Dart y vit dans
    # `kernel_blob.bin`, interprete. On ne peut donc pas y lire l'adresse de
    # l'API -- mais le manifeste, lui, se lit dans les deux cas, et c'est la
    # que vit la permission d'installation. On signale l'impossibilite et on
    # poursuit, plutot que d'abandonner le rapport des sa premiere ligne.
    debogage = not binaires
    if debogage:
        print('  ?  aucun libapp.so : artefact de debogage, API non verifiable')

    elif ATTENDU.encode() in octets:
        ok(f'API de production presente : {ATTENDU}')
    else:
        ko(f'{ATTENDU} absent du binaire — le build n\'a pas recu '
           f'--dart-define=API_BASE_URL')

    for locale in LOCALES:
        # On cherche une adresse http(s) contenant ce fragment, pas le fragment
        # seul : « localhost » apparait dans des bibliotheques tierces sans que
        # l'application y envoie quoi que ce soit.
        motif = re.compile(rb'https?://[^\x00\s"]*' + re.escape(locale.encode()))
        trouve = motif.search(octets)
        if trouve:
            ko(f'adresse locale dans le binaire : '
               f'{trouve.group().decode("utf-8", "replace")[:60]}')
    if not echecs and not debogage:
        ok('aucune adresse locale')

    # ── Version et paquet ──
    mf = manifeste(z)
    if not mf:
        ko('manifeste introuvable')

    # Le manifeste d'un APK est en XML binaire : les chaines y sont encodees en
    # UTF-16. On cherche donc dans les deux encodages.
    def present(texte: str) -> bool:
        return texte.encode() in mf or texte.encode('utf-16-le') in mf

    if present('com.pronowin.app'):
        ok('paquet com.pronowin.app')
    else:
        ko('le paquet n\'est pas com.pronowin.app')

    # ── Permission d'installation, selon le canal ──
    installe = present(INSTALLATION)
    if canal is None:
        print('  ?  canal inconnu : ' + INSTALLATION
              + (' present' if installe else ' absent') + ', non verifie')
    elif canal == 'play':
        if installe:
            ko(INSTALLATION + ' present dans un artefact Play : motif de '
               'retrait, la variante play ne doit pas le declarer')
        elif not present(TEMOIN):
            # Contrepartie indispensable.
            #
            # Le manifeste d'un AAB est en protobuf, celui d'un APK en XML
            # binaire UTF-16. Si la lecture echouait — format change, chemin
            # deplace, encodage different — la recherche ne trouverait rien, et
            # « permission absente » serait annonce sur un manifeste qu'on n'a
            # pas su lire. Le controle le plus important du fichier passerait
            # alors au vert sans avoir rien regarde.
            #
            # On exige donc de retrouver une permission qu'on sait presente.
            ko('manifeste illisible : ' + TEMOIN + ' introuvable, donc '
               'l\'absence de ' + INSTALLATION + ' ne prouve rien')
        else:
            ok(INSTALLATION + ' absent, comme exige par Play')
    else:
        if installe:
            ok(INSTALLATION + ' present : la mise a jour directe peut installer')
        else:
            ko(INSTALLATION + ' absent d\'un artefact direct : la mise a jour '
               'ne pourra pas s\'installer. Build lance sans --flavor direct ?')

    brut = mf.replace(b'\x00', b'')     # aplatit l'UTF-16 pour la recherche
    versions = sorted({m.decode() for m in re.findall(rb'\d+\.\d+\.\d+', brut)
                       if m.decode().startswith('1.0.')})
    if versions:
        ok(f'versionName : {", ".join(versions)}')

    # Un artefact de debogage a passe les controles qu'on a pu lui
    # appliquer, ce qui ne le rend pas publiable pour autant. Le dire
    # autrement serait exactement le defaut que ce fichier existe pour
    # attraper : un rapport vert qui affirme plus qu'il n'a verifie.
    if echecs:
        print('\n%d probleme(s) : NE PAS TELEVERSER\n' % len(echecs))
        return 1
    if debogage:
        print('\nControle partiel : artefact de debogage, NON publiable\n')
        return 0
    print('\nOK - ce bundle est publiable\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
