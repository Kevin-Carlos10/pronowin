# Version 1.0.37 (53) — Suivis qui alertent, classement en direct

Préparée le 15 novembre 2026, après la 1.0.36 (52, iOS n° 57 sur 3be36c7).
Rien de ce qui sert à parier n'a été ajouté. Le serveur et le panneau
d'administration sont déployés avant la publication.

## Nouveautés

- **Alertes des équipes et ligues suivies** : une équipe suivie annonce le
  coup d'envoi, les buts et le résultat de ses matchs ; une ligue suivie, le
  coup d'envoi et le résultat (ses buts, sur toute une journée, feraient
  trop). Les suivis sont désormais connus du serveur ; au premier lancement,
  ceux du téléphone s'y ajoutent. Deux interrupteurs dans Paramètres >
  Notifications push, « Équipes suivies » et « Ligues suivies ».
- **Classement en direct** pendant les matchs : les matchs en cours comptent
  au score du moment, avec la place gagnée ou perdue et le score à côté de
  chaque équipe qui joue. Dans la fiche d'un match en cours et dans l'onglet
  Classement d'une compétition ; « Général » rend le classement officiel.
  Calculé sur le téléphone, sans appel de plus au fournisseur.
- **Chercher et suivre un championnat** depuis la recherche (« ligue des
  champions », « liga »…), avec son bouton Suivre.
- **Confrontations directes en détail** : toucher une rencontre passée ouvre
  son score, la mi-temps, les faits du match et les statistiques ; sa fiche
  complète si elle est dans notre base.

## Écrans revus (dessin des Paramètres)

- **Modifier le profil** : cartes Identité et Compte, validation en direct,
  « Enregistrer » actif seulement après une modification, confirmation avant
  d'abandonner des changements.
- **Compte** et **Parrainage** au même dessin ; tutoiement partout.
- **Cartes à 8 points du bord de l'écran**, comme Sofascore.

## Partage

- Les partages et QR codes mènent à la page de téléchargement du site, code
  de parrainage compris.

## Côté serveur (déjà actif avant la publication)

- **Relance des abonnés expirés** : automatique 3 jours après l'échéance,
  une seule fois ; et depuis le panneau (filtre « Premium expiré » >
  Relancer), avec le code promo en option. Interrupteur « Abonnement
  Premium ».

## À faire à la soumission

- **Google Play** : remplacer l'AAB du brouillon de production par celui-ci.
- **App Store** : ne pas soumettre avant la réponse d'Apple sur la 1.0.33
  (58) ; Remarques honnêtes sur le code promo (voir 1.0.34).
