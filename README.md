# Bunker 1013

Jeu d'enquête à la troisième personne, dans un bunker caché au fond d'une grotte.
1013 personnes y vivent. Chaque nuit, quelqu'un du Secteur C meurt. Lina, l'enquêtrice
du secteur, a cinq jours pour trouver le meurtrier, avec quatre capacités sur les touches 1 à 4.

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
| 1 2 3 4 | Capacités de Lina |
| E | Parler, fouiller le corps ou une caisse, crocheter un casier, écouter la radio |
| C | Carnet d'enquête, écarter ou accuser un suspect |
| F (maintenu) | Accélérer le temps |
| N deux fois | Finir la journée |
| P | Couper ou remettre le filtre peinture |
| Échap | Pause : volumes, filtre peinture, bouton « Débloquer » |

Regarder quelqu'un (le point au centre de l'écran) affiche son nom, son métier et ce qu'il fait.

## Les capacités de Lina

| Touche | Capacité | Recharge | Effet |
| --- | --- | --- | --- |
| 1 | Écho | 8 s | Une onde révèle les empreintes autour de toi (rouges si elles datent de la nuit). |
| 2 | Fil rouge | 20 s | Près du corps : la piste du tueur jusqu'à sa cachette. Ailleurs : les trajets récents de chacun. |
| 3 | Regard | 12 s | Marque la personne visée : sa vraie pointure, et tu la vois à travers les murs pendant une minute. |
| 4 | Confidence | 6 s | La personne visée, proche, donne son alibi de la nuit et un secret. Le tueur ment sur sa pointure. |

## Anti-blocage

Lina ne heurte que les murs et les meubles, jamais les habitants. Si elle ne bouge plus malgré
les touches pendant 3 secondes, ou si elle sort de la carte, elle revient à sa dernière position
sûre. Le menu pause a aussi un bouton « Débloquer ».

## Sons

Tous les sons sont générés par `tools/gen_audio.py` (aucune licence à gérer) :
`python tools/gen_audio.py` les recrée dans `assets/audio/` (il faut Python, numpy et ffmpeg).

## Test automatique

`Godot --path . --headless -- --autotest` vérifie les salles, les routines, les capacités et
l'anti-blocage, puis affiche `AUTOTEST OK`. Sans `--headless`, il enregistre aussi des captures
d'écran dans le dossier utilisateur de Godot.

## Organisation du projet

```
project.godot            réglages du projet
scenes/main.tscn         scène de départ
scripts/game_data.gd     TOUTES les données : salles, équipes, habitants, routines, capacités, textes
scripts/game.gd          état de la partie, indices, touches
scripts/main.gd          journée, nuit, meurtre, capacités, fin de partie
scripts/bunker.gd        construction du Secteur C et trajets des habitants
scripts/npc.gd           habitants, tâches visibles, effets et sons
scripts/player.gd        Lina : déplacement, pas, anti-blocage
scripts/audio.gd         lecture des sons (Sfx)
tools/gen_audio.py       fabrique tous les sons du jeu
scripts/camera_rig.gd    caméra par-dessus l'épaule
scripts/character_visual.gd  personnages stylisés : silhouette, visage, cheveux, accessoires, démarche
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
