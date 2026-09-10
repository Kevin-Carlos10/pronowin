#!/usr/bin/env python3
"""Verifie qu'un App Bundle est publiable — en lisant le binaire, pas le code.

    python tool/verifier_bundle.py [chemin.aab]

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

# Adresses qui n'ont rien a faire dans un binaire distribue.
LOCALES = ['10.0.2.2', '127.0.0.1', 'localhost', '192.168.']

DEFAUT = 'build/app/outputs/bundle/release/app-release.aab'


def libs(z):
    """Le code Dart compile, toutes architectures confondues."""
    return [n for n in z.namelist() if n.endswith('libapp.so')]


def main():
    chemin = sys.argv[1] if len(sys.argv) > 1 else DEFAUT
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
    if not binaires:
        ko('aucun libapp.so dans le bundle : rien a verifier')
        return 1

    octets = b''.join(z.read(n) for n in binaires)

    if ATTENDU.encode() in octets:
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
    if not echecs:
        ok('aucune adresse locale')

    # ── Version et paquet ──
    try:
        manifeste = z.read('base/manifest/AndroidManifest.xml')
    except KeyError:
        ko('manifeste introuvable')
        manifeste = b''

    if b'com.pronowin.app' in manifeste:
        ok('paquet com.pronowin.app')
    else:
        ko('le paquet n\'est pas com.pronowin.app')

    versions = sorted({m.decode() for m in re.findall(rb'\d+\.\d+\.\d+', manifeste)
                       if m.decode().startswith('1.')})
    if versions:
        ok(f'versionName : {", ".join(versions)}')

    print('\n' + ('OK — ce bundle est publiable\n' if not echecs
                  else f'{len(echecs)} probleme(s) : NE PAS TELEVERSER\n'))
    return 0 if not echecs else 1


if __name__ == '__main__':
    sys.exit(main())
