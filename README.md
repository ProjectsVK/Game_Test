# Bunker 1013

Jeu d'enquête à la troisième personne, dans un bunker caché au fond d'une grotte.
1013 personnes y vivent. Chaque nuit, quelqu'un du Secteur C meurt. Lina, Maël et Sacha
ont cinq jours pour trouver le meurtrier, chacun avec quatre capacités sur les touches 1 à 4.

Moteur : **Godot 4** (gratuit, léger, open source).

## Lancer le jeu

1. Télécharger Godot 4 (version standard, pas .NET) : https://godotengine.org/download
   Le projet vise Godot 4.3 ou plus récent.
2. Ouvrir Godot, cliquer sur **Importer**, choisir le fichier `project.godot` de ce dossier.
3. Appuyer sur **F5** (ou le bouton ▶ en haut à droite).

La première ouverture prend quelques secondes : Godot importe les polices et compile les shaders.

## Commandes

| Touche | Action |
| --- | --- |
| Z Q S D (ou W A S D) | Marcher |
| Souris | Viser, tourner la caméra |
| Maj | Courir |
| 1 2 3 4 | Capacités de l'ami actif |
| E | Parler à quelqu'un |
| Tab | Changer d'ami |
| C | Carnet d'enquête, écarter ou accuser un suspect |
| F (maintenu) | Accélérer le temps |
| N deux fois | Finir la journée |
| P | Couper ou remettre le filtre peinture |
| Échap | Fermer, libérer la souris |

## Les trois amis

| Ami | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| Lina, la confidente | Interroger (alibi) | Écoute (à travers les murs) | Réconfort (secret, pointure) | Souvenir (trajets récents) |
| Maël, le traqueur | Traces (empreintes) | Élan (course) | Marquer (vraie pointure) | Pister (piste du tueur) |
| Sacha, le mécano | Fouiller (fibres, caisses) | Caméra (filme la nuit) | Crocheter (casiers) | Radio (lits vides à 2 h) |

## Organisation du projet

```
project.godot            réglages du projet
scenes/main.tscn         scène de départ
scripts/game_data.gd     TOUTES les données : salles, équipes, habitants, routines, capacités, textes
scripts/game.gd          état de la partie, indices, touches
scripts/main.gd          journée, nuit, meurtre, capacités, fin de partie
scripts/bunker.gd        construction du Secteur C et trajets des habitants
scripts/npc.gd           habitants et leurs routines
scripts/friend.gd        les trois amis (contrôle et suivi)
scripts/camera_rig.gd    caméra par-dessus l'épaule
scripts/character_visual.gd  silhouettes provisoires (à remplacer par de vrais modèles)
scripts/hud.gd           interface, carnet, écrans de récit
shaders/                 rendu peint : ombrage en bandes, contours, filtre pinceau plein écran
assets/fonts/            polices Alegreya (licence OFL)
```

## Le style visuel

Le rendu peint vient de trois shaders :

- `toon.gdshader` : lumière en bandes, ombres teintées de bleu, coups de brosse procéduraux.
- `outline.gdshader` : contour encré autour des personnages.
- `painterly.gdshader` : passe plein écran (filtre de Kuwahara pour les aplats peints, contours
  par profondeur, ombres froides et lumières chaudes, grain, vignette).

Les personnages et le décor sont encore des formes simples. La prochaine étape visuelle est de
modéliser de vrais personnages et décors (Blender, gratuit) et de les glisser à la place.

## Plus tard : Roblox

Roblox n'accepte que des jeux faits dans Roblox Studio, en Luau. Le code devra donc être réécrit.
Pour faciliter ce travail, toutes les données du jeu sont dans `scripts/game_data.gd`, séparées
du code : ce fichier se traduit presque ligne par ligne en ModuleScript Luau.
