extends Node
## Toutes les données du jeu, séparées du code.
## Pour un portage Roblox, ce fichier se traduit presque ligne par ligne en ModuleScript Luau.

const CONFIG := {
	"day_start": 360,          # 06:00, en minutes depuis minuit
	"day_end": 1320,           # 22:00
	"minutes_per_second": 3.0, # une journée dure environ 5 min 20 s
	"days": 5,
	"max_wrong": 2,
}

## Le Secteur C : un réfectoire central relié à trois salles.
## rect = [x_min, x_max, z_min, z_max] en mètres. door = centre de la porte vers le réfectoire.
const ROOMS := {
	"refectoire": {"name": "Réfectoire", "at": "au réfectoire", "rect": [-7.0, 7.0, -6.0, 6.0],
		"light": Color(1.0, 0.62, 0.3), "floor": Color(0.34, 0.25, 0.18)},
	"dortoir": {"name": "Dortoir", "at": "au dortoir", "rect": [-7.0, 7.0, -18.0, -6.0], "door": [0.0, -6.0],
		"light": Color(0.95, 0.72, 0.45), "floor": Color(0.2, 0.21, 0.28)},
	"atelier": {"name": "Atelier", "at": "à l'atelier", "rect": [7.0, 19.0, -6.0, 6.0], "door": [7.0, 0.0],
		"light": Color(1.0, 0.45, 0.2), "floor": Color(0.3, 0.2, 0.16)},
	"infirmerie": {"name": "Infirmerie", "at": "à l'infirmerie", "rect": [-19.0, -7.0, -6.0, 6.0], "door": [-7.0, 0.0],
		"light": Color(0.35, 1.0, 0.7), "floor": Color(0.17, 0.25, 0.24)},
}

const TEAMS := {
	"rouge": {"name": "Rouge", "color": Color(0.7, 0.24, 0.17), "room": "atelier", "weapon": "une clé à molette"},
	"bleu": {"name": "Bleue", "color": Color(0.17, 0.42, 0.52), "room": "refectoire", "weapon": "un couteau de cuisine"},
	"jaune": {"name": "Jaune", "color": Color(0.84, 0.62, 0.16), "room": "infirmerie", "weapon": "un scalpel"},
}

## Routine commune. TEAM = salle d'équipe, EVENING = habitude du soir de chaque habitant.
const BASE_SCHEDULE := [
	[360, "dortoir"], [400, "refectoire"], [480, "TEAM"], [720, "refectoire"],
	[790, "TEAM"], [1080, "refectoire"], [1140, "EVENING"], [1280, "dortoir"],
]

## 6 habitants : 3 équipes x 2 pointures. Chaque combinaison équipe + pointure est unique.
const NPCS := [
	{"id": "gaspard", "name": "Gaspard", "team": "rouge", "shoe": "L", "evening": "atelier", "extra": [],
		"hair": Color(0.2, 0.14, 0.1), "skin": Color(0.78, 0.6, 0.47),
		"chat": "La pompe fait encore ce bruit. Si elle lâche, on respire quoi, nous ?",
		"secret": "Une nuit, j'ai vu la porte scellée s'ouvrir. Juste un instant. Je n'en ai parlé à personne.",
		"locker": "un croquis de la porte scellée, couvert de dates", "keepsake": "le briquet de Gaspard",
		"bond": "Sacha travaillait avec lui le matin. Il avait promis de lui apprendre à souder.",
		"motive": "Gaspard a vu ce qu'il y a derrière la porte scellée. Il tue ceux qui posent trop de questions, pour que personne ne l'ouvre jamais."},
	{"id": "elio", "name": "Elio", "team": "rouge", "shoe": "S", "evening": "infirmerie", "extra": [[900, "infirmerie"], [960, "TEAM"]],
		"hair": Color(0.85, 0.75, 0.55), "skin": Color(0.9, 0.72, 0.6),
		"chat": "Je passe juste voir ma mère à l'infirmerie. Elle va mieux. Je crois.",
		"secret": "Je prends des calmants à l'infirmerie. Pour ma mère. Elle ne dort plus depuis des mois.",
		"locker": "des fioles de calmants volées", "keepsake": "le canif d'Elio",
		"bond": "Maël le considérait comme un petit frère.",
		"motive": "Elio croit que le partage des rations tue sa mère à petit feu. Chaque victime recevait plus qu'elle."},
	{"id": "ruben", "name": "Ruben", "team": "bleu", "shoe": "L", "evening": "refectoire", "extra": [],
		"hair": Color(0.08, 0.06, 0.05), "skin": Color(0.45, 0.3, 0.22),
		"chat": "Une partie de cartes ce soir ? Je te jure que cette fois je rembourse.",
		"secret": "Je dois des rations à la moitié du secteur. Les cartes, ça ne pardonne pas.",
		"locker": "un carnet de dettes plein de ratures", "keepsake": "le jeu de cartes de Ruben",
		"bond": "Il faisait rire Sacha même les pires jours.",
		"motive": "Ruben ne pouvait plus payer ses dettes. Il a commencé par son créancier, puis il n'a plus su s'arrêter."},
	{"id": "nour", "name": "Nour", "team": "bleu", "shoe": "S", "evening": "refectoire", "extra": [],
		"hair": Color(0.1, 0.07, 0.06), "skin": Color(0.62, 0.45, 0.33),
		"chat": "Tu entends ? Les tuyaux chantent quand il fait froid dehors. S'il y a un dehors.",
		"secret": "Il y a un nom gravé sous la cuisine. L'ancien nom du bunker. Il me fait peur.",
		"locker": "un calque de l'inscription gravée sous la cuisine", "keepsake": "le pendentif de Nour",
		"bond": "Lina et elle chantaient ensemble à la fête du solstice.",
		"motive": "Nour a lu le vrai nom du bunker : un lieu d'expérience. Elle pense que certains habitants sont des surveillants, et elle les élimine."},
	{"id": "felix", "name": "Félix", "team": "jaune", "shoe": "L", "evening": "infirmerie", "extra": [],
		"hair": Color(0.55, 0.3, 0.15), "skin": Color(0.85, 0.66, 0.52),
		"chat": "Lave-toi les mains avant de toucher quoi que ce soit ici. Je ne plaisante pas.",
		"secret": "Je teste des remèdes. Sur moi d'abord. Il faut bien que quelqu'un le fasse.",
		"locker": "des seringues et un carnet de doses", "keepsake": "le stéthoscope de Félix",
		"bond": "Il avait soigné la main de Sacha sans rien demander en échange.",
		"motive": "Félix teste un remède sur des gens qui ne savent rien. Les morts sont ses échecs."},
	{"id": "iris", "name": "Iris", "team": "jaune", "shoe": "S", "evening": "infirmerie", "extra": [[1200, "refectoire"]],
		"hair": Color(0.35, 0.12, 0.1), "skin": Color(0.92, 0.76, 0.66),
		"chat": "Tu as vu Maël ? Non, pour rien. Juste comme ça.",
		"secret": "Je suis amoureuse de Maël. Je n'ai jamais osé le dire. Ne le répète pas.",
		"locker": "un mot pour Maël, jamais donné", "keepsake": "le bracelet d'Iris",
		"bond": "Maël trouve un mot plié dans sa poche. Il ne l'ouvre pas encore.",
		"motive": "Iris tue ceux qui s'approchent de Maël. Elle dit que c'est pour le protéger."},
]

const FRIENDS := [
	{"id": "lina", "name": "Lina", "role": "la confidente", "color": Color(0.55, 0.36, 0.68),
		"hair": Color(0.12, 0.08, 0.1), "skin": Color(0.86, 0.68, 0.56),
		"abilities": [
			{"id": "interroger", "name": "Interroger", "desc": "Alibi de la nuit", "cd": 2.0},
			{"id": "ecoute", "name": "Écoute", "desc": "Voir à travers les murs", "cd": 18.0},
			{"id": "reconfort", "name": "Réconfort", "desc": "Un secret, une pointure", "cd": 10.0},
			{"id": "souvenir", "name": "Souvenir", "desc": "Trajets de la dernière heure", "cd": 28.0},
		]},
	{"id": "mael", "name": "Maël", "role": "le traqueur", "color": Color(0.85, 0.45, 0.2),
		"hair": Color(0.7, 0.3, 0.12), "skin": Color(0.9, 0.72, 0.58),
		"abilities": [
			{"id": "traces", "name": "Traces", "desc": "Empreintes et pointures", "cd": 6.0},
			{"id": "sprint", "name": "Élan", "desc": "Course rapide 3 s", "cd": 9.0},
			{"id": "marquer", "name": "Marquer", "desc": "Suivre, voir la vraie pointure", "cd": 14.0},
			{"id": "pister", "name": "Pister", "desc": "Près du corps : piste du tueur", "cd": 24.0},
		]},
	{"id": "sacha", "name": "Sacha", "role": "le mécano", "color": Color(0.42, 0.55, 0.68),
		"hair": Color(0.05, 0.05, 0.06), "skin": Color(0.55, 0.4, 0.3),
		"abilities": [
			{"id": "fouiller", "name": "Fouiller", "desc": "Fibres, caisses", "cd": 3.0},
			{"id": "camera", "name": "Caméra", "desc": "Filme la nuit (2 max)", "cd": 4.0},
			{"id": "crocheter", "name": "Crocheter", "desc": "Ouvrir un casier (3/jour)", "cd": 2.0},
			{"id": "radio", "name": "Radio", "desc": "Rapport de la ronde de 2 h", "cd": 15.0},
		]},
]

const RUMORS := [
	"La radio a grésillé pendant toute la ronde.",
	"Il paraît que la porte scellée a vibré cette nuit.",
	"L'air est plus lourd depuis une semaine, tu ne trouves pas ?",
	"Quelqu'un a laissé la lumière de l'atelier allumée.",
	"Les rations ont encore baissé. Personne n'ose le dire.",
]

const INTRO := "1013 personnes vivent dans ce qu'elles croient être une grotte. Les parois cachent des portes blindées, des tuyaux, des inscriptions effacées. Chaque nuit, quelqu'un du Secteur C meurt. Lina, Maël et Sacha ont cinq jours pour trouver qui."
