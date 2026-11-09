extends Node
## Toutes les données du jeu, séparées du code.
## Pour un portage Roblox, ce fichier se traduit presque ligne par ligne en ModuleScript Luau.

const CONFIG := {
	"day_start": 360,          # 06:00, en minutes depuis minuit
	"day_end": 1320,           # 22:00
	"minutes_per_second": 3.0, # une journée dure environ 5 min 20 s
	"days": 5,
	"max_wrong": 2,
	"lockpicks_per_day": 3,
}

## Le Secteur C : un réfectoire central relié à trois salles.
## rect = [x_min, x_max, z_min, z_max] en mètres. door = centre de la porte vers le réfectoire.
const ROOMS := {
	"refectoire": {"name": "Réfectoire", "at": "au réfectoire", "rect": [-7.0, 7.0, -6.0, 6.0],
		"light": Color(1.0, 0.62, 0.3), "floor": Color(0.34, 0.25, 0.18), "ground": "concrete", "ambience": "amb_refectoire"},
	"dortoir": {"name": "Dortoir", "at": "au dortoir", "rect": [-7.0, 7.0, -18.0, -6.0], "door": [0.0, -6.0],
		"light": Color(0.95, 0.7, 0.42), "floor": Color(0.36, 0.24, 0.16), "ground": "wood", "ambience": "amb_dortoir"},
	"atelier": {"name": "Atelier", "at": "à l'atelier", "rect": [7.0, 19.0, -6.0, 6.0], "door": [7.0, 0.0],
		"light": Color(1.0, 0.45, 0.2), "floor": Color(0.24, 0.24, 0.26), "ground": "metal", "ambience": "amb_atelier"},
	"infirmerie": {"name": "Infirmerie", "at": "à l'infirmerie", "rect": [-19.0, -7.0, -6.0, 6.0], "door": [-7.0, 0.0],
		"light": Color(0.45, 1.0, 0.75), "floor": Color(0.55, 0.6, 0.58), "ground": "tile", "ambience": "amb_infirmerie"},
}

const TEAMS := {
	"rouge": {"name": "Rouge", "color": Color(0.7, 0.24, 0.17), "room": "atelier", "weapon": "une clé à molette"},
	"bleu": {"name": "Bleue", "color": Color(0.17, 0.42, 0.52), "room": "refectoire", "weapon": "un couteau de cuisine"},
	"jaune": {"name": "Jaune", "color": Color(0.84, 0.62, 0.16), "room": "infirmerie", "weapon": "un scalpel"},
}

## Postes de travail : chaque tâche visible a un endroit, un geste, un objet en main, un effet et un son.
## pos = où se tient l'habitant, face = le point qu'il regarde. anim : stir, chop, wash, write, hammer,
## weld, reach, inspect, sweep, tend, read, eat, cards, fold.
const STATIONS := {
	# réfectoire
	"cook_stove": {"room": "refectoire", "pos": [-4.5, -4.35], "face": [-4.5, -5.6], "anim": "stir", "prop": "ladle", "fx": "steam", "sound": "task_stir", "label": "Remue la soupe"},
	"chop": {"room": "refectoire", "pos": [-2.0, -4.35], "face": [-2.0, -5.6], "anim": "chop", "prop": "knife", "fx": "", "sound": "task_chop", "label": "Coupe des légumes"},
	"wash_dishes": {"room": "refectoire", "pos": [2.4, -4.35], "face": [2.4, -5.6], "anim": "wash", "prop": "rag", "fx": "water", "sound": "task_water", "label": "Fait la vaisselle"},
	"count_rations": {"room": "refectoire", "pos": [5.3, -4.5], "face": [5.3, -5.8], "anim": "write", "prop": "clipboard", "fx": "", "sound": "task_paper", "label": "Compte les rations"},
	"sweep_refectoire": {"room": "refectoire", "pos": [-3.5, -2.2], "face": [-2.5, -2.2], "anim": "sweep", "prop": "broom", "fx": "dust", "sound": "task_sweep", "label": "Balaie le sol"},
	"seat_1": {"room": "refectoire", "pos": [-5.0, 1.95], "face": [-5.0, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"seat_2": {"room": "refectoire", "pos": [-3.4, 1.95], "face": [-3.4, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"seat_3": {"room": "refectoire", "pos": [3.4, 1.95], "face": [3.4, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"seat_4": {"room": "refectoire", "pos": [5.0, 1.95], "face": [5.0, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"seat_5": {"room": "refectoire", "pos": [-2.25, 3.0], "face": [-4.2, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"seat_6": {"room": "refectoire", "pos": [2.25, 3.0], "face": [4.2, 3.0], "anim": "eat", "prop": "bowl", "fx": "", "sound": "task_eat", "label": "Mange", "sit": true},
	"cards_1": {"room": "refectoire", "pos": [2.25, 3.0], "face": [4.2, 3.0], "anim": "cards", "prop": "cards", "fx": "", "sound": "task_cards", "label": "Joue aux cartes", "sit": true},
	"cards_2": {"room": "refectoire", "pos": [3.4, 1.95], "face": [3.4, 3.0], "anim": "cards", "prop": "cards", "fx": "", "sound": "task_cards", "label": "Joue aux cartes", "sit": true},
	# dortoir
	"read_chair": {"room": "dortoir", "pos": [5.75, -9.5], "face": [4.0, -9.5], "anim": "read", "prop": "book", "fx": "", "sound": "task_paper", "label": "Lit un vieux livre", "sit": true},
	"write_letter": {"room": "dortoir", "pos": [-4.0, -7.55], "face": [-4.0, -6.2], "anim": "write", "prop": "pen", "fx": "", "sound": "task_write", "label": "Écrit une lettre", "sit": true},
	"fold_laundry": {"room": "dortoir", "pos": [4.85, -12.2], "face": [6.0, -12.2], "anim": "fold", "prop": "cloth", "fx": "", "sound": "task_paper", "label": "Plie le linge"},
	# atelier
	"pump_fix": {"room": "atelier", "pos": [12.0, -4.55], "face": [12.0, -5.8], "anim": "reach", "prop": "wrench", "fx": "steam", "sound": "task_hammer", "label": "Répare la pompe à air"},
	"boiler_watch": {"room": "atelier", "pos": [15.1, 3.2], "face": [16.6, 4.4], "anim": "inspect", "prop": "", "fx": "steam", "sound": "task_boiler", "label": "Surveille la chaudière"},
	"weld": {"room": "atelier", "pos": [16.85, 1.6], "face": [18.0, 1.6], "anim": "weld", "prop": "torch", "fx": "sparks", "sound": "task_weld", "label": "Soude une plaque"},
	"bench_repair": {"room": "atelier", "pos": [16.85, -1.3], "face": [18.0, -1.3], "anim": "hammer", "prop": "hammer", "fx": "", "sound": "task_hammer", "label": "Répare une vieille radio"},
	"tools_store": {"room": "atelier", "pos": [10.5, 4.55], "face": [10.5, 5.8], "anim": "reach", "prop": "wrench", "fx": "", "sound": "task_glass", "label": "Range les outils"},
	"sweep_atelier": {"room": "atelier", "pos": [12.5, 0.8], "face": [13.5, 0.8], "anim": "sweep", "prop": "broom", "fx": "dust", "sound": "task_sweep", "label": "Balaie la limaille"},
	# infirmerie
	"tend_patient": {"room": "infirmerie", "pos": [-16.75, -2.8], "face": [-17.9, -2.8], "anim": "tend", "prop": "", "fx": "", "sound": "task_hum", "label": "Soigne un malade"},
	"tend_patient2": {"room": "infirmerie", "pos": [-16.75, 3.2], "face": [-17.9, 3.2], "anim": "tend", "prop": "rag", "fx": "", "sound": "task_hum", "label": "Change un pansement"},
	"visit_mother": {"room": "infirmerie", "pos": [-16.75, 3.2], "face": [-17.9, 3.2], "anim": "read", "prop": "", "fx": "", "sound": "", "label": "Veille sa mère malade", "sit": true},
	"sort_meds": {"room": "infirmerie", "pos": [-12.5, -4.55], "face": [-12.5, -5.8], "anim": "reach", "prop": "vial", "fx": "", "sound": "task_glass", "label": "Trie les remèdes"},
	"brew_remedy": {"room": "infirmerie", "pos": [-14.5, 4.4], "face": [-14.5, 5.6], "anim": "stir", "prop": "vial", "fx": "bubbles", "sound": "task_bubble", "label": "Prépare un remède"},
	"write_records": {"room": "infirmerie", "pos": [-10.0, 4.1], "face": [-10.0, 5.4], "anim": "write", "prop": "pen", "fx": "", "sound": "task_write", "label": "Remplit les dossiers", "sit": true},
	"wash_hands": {"room": "infirmerie", "pos": [-9.0, -4.5], "face": [-9.0, -5.7], "anim": "wash", "prop": "", "fx": "water", "sound": "task_water", "label": "Se lave les mains"},
}

## Routine commune : quel genre d'activité à quelle heure.
## wake/sleep = au lit, meal = un siège libre au réfectoire, work/evening = tâches propres à chacun.
const BASE_SCHEDULE := [
	[360, "wake"], [400, "meal"], [470, "work"], [720, "meal"], [790, "work"],
	[1080, "meal"], [1140, "evening"], [1280, "sleep"],
]

## Apparence : chaque silhouette doit se reconnaître de loin.
## height/bulk/head/legs/shoulders : proportions (1.0 = normal). hair : bald, buzz, spiky, bun, cap, braid, bob, swept.
## face : brows (épaisseur), nose (taille), beard, glasses, eye_size. gait : vitesse, foulée, rebond, balancement, dos voûté.
const NPCS := [
	{"id": "gaspard", "name": "Gaspard", "role": "Mécanicien en chef", "team": "rouge", "shoe": "L",
		"work": ["pump_fix", "boiler_watch", "weld", "tools_store"], "evening": ["boiler_watch", "pump_fix"],
		"look": {"height": 1.08, "bulk": 1.55, "head": 1.05, "legs": 0.8, "shoulders": 1.5,
			"skin": Color(0.78, 0.56, 0.42), "hair": "bald", "hair_color": Color(0.62, 0.6, 0.58),
			"coat": Color(0.52, 0.22, 0.14), "pants": Color(0.22, 0.17, 0.14), "accent": Color(0.42, 0.3, 0.2),
			"eyes": Color(0.3, 0.4, 0.5), "brows": 1.6, "nose": 1.4, "beard": "full", "glasses": "",
			"accessories": ["goggles_head", "apron", "toolbelt"],
			"gait": {"speed": 1.25, "stride": 0.45, "bounce": 0.03, "sway": 0.09, "hunch": 0.08}, "idle": "arms_crossed"},
		"chat": "La pompe fait encore ce bruit. Si elle lâche, on respire quoi, nous ?",
		"secret": "Une nuit, j'ai vu la porte scellée s'ouvrir. Juste un instant. Je n'en ai parlé à personne.",
		"locker": "un croquis de la porte scellée, couvert de dates", "keepsake": "le briquet de Gaspard",
		"bond": "Il avait promis à Lina de lui apprendre à souder.",
		"motive": "Gaspard a vu ce qu'il y a derrière la porte scellée. Il tue ceux qui posent trop de questions, pour que personne ne l'ouvre jamais."},
	{"id": "elio", "name": "Elio", "role": "Apprenti mécanicien", "team": "rouge", "shoe": "S",
		"work": ["bench_repair", "tools_store", "sweep_atelier", "weld"], "evening": ["visit_mother", "read_chair"],
		"look": {"height": 0.88, "bulk": 0.75, "head": 1.12, "legs": 1.15, "shoulders": 0.85,
			"skin": Color(0.92, 0.74, 0.62), "hair": "spiky", "hair_color": Color(0.9, 0.72, 0.38),
			"coat": Color(0.62, 0.3, 0.22), "pants": Color(0.25, 0.38, 0.42), "accent": Color(0.2, 0.62, 0.6),
			"eyes": Color(0.25, 0.55, 0.45), "brows": 0.8, "nose": 0.8, "beard": "", "glasses": "",
			"accessories": ["goggles_eyes", "scarf"],
			"gait": {"speed": 1.75, "stride": 0.7, "bounce": 0.09, "sway": 0.03, "hunch": 0.0}, "idle": "fidget"},
		"chat": "Je passe juste voir ma mère à l'infirmerie ce soir. Elle va mieux. Je crois.",
		"secret": "Je prends des calmants à l'infirmerie. Pour ma mère. Elle ne dort plus depuis des mois.",
		"locker": "des fioles de calmants volées", "keepsake": "le canif d'Elio",
		"bond": "Lina le considérait comme un petit frère.",
		"motive": "Elio croit que le partage des rations tue sa mère à petit feu. Chaque victime recevait plus qu'elle."},
	{"id": "ruben", "name": "Ruben", "role": "Gardien des rations", "team": "bleu", "shoe": "L",
		"work": ["count_rations", "wash_dishes", "sweep_refectoire", "chop"], "evening": ["cards_1", "cards_2"],
		"look": {"height": 1.22, "bulk": 0.82, "head": 0.9, "legs": 1.25, "shoulders": 1.0,
			"skin": Color(0.45, 0.3, 0.22), "hair": "cap", "hair_color": Color(0.08, 0.06, 0.05),
			"coat": Color(0.16, 0.24, 0.4), "pants": Color(0.2, 0.2, 0.24), "accent": Color(0.85, 0.65, 0.2),
			"eyes": Color(0.25, 0.15, 0.08), "brows": 1.0, "nose": 1.3, "beard": "stubble", "glasses": "",
			"accessories": ["long_coat", "cards_pocket"],
			"gait": {"speed": 1.3, "stride": 0.75, "bounce": 0.02, "sway": 0.12, "hunch": 0.22}, "idle": "shuffle"},
		"chat": "Une partie de cartes ce soir ? Je te jure que cette fois je rembourse.",
		"secret": "Je dois des rations à la moitié du secteur. Les cartes, ça ne pardonne pas.",
		"locker": "un carnet de dettes plein de ratures", "keepsake": "le jeu de cartes de Ruben",
		"bond": "Il faisait rire Lina même les pires jours.",
		"motive": "Ruben ne pouvait plus payer ses dettes. Il a commencé par son créancier, puis il n'a plus su s'arrêter."},
	{"id": "nour", "name": "Nour", "role": "Cuisinière", "team": "bleu", "shoe": "S",
		"work": ["cook_stove", "chop", "wash_dishes", "cook_stove"], "evening": ["read_chair", "fold_laundry"],
		"look": {"height": 0.84, "bulk": 1.35, "head": 1.1, "legs": 0.8, "shoulders": 1.0,
			"skin": Color(0.62, 0.44, 0.32), "hair": "bun", "hair_color": Color(0.1, 0.07, 0.06),
			"coat": Color(0.2, 0.5, 0.5), "pants": Color(0.3, 0.22, 0.2), "accent": Color(0.95, 0.9, 0.78),
			"eyes": Color(0.2, 0.12, 0.06), "brows": 1.1, "nose": 1.0, "beard": "", "glasses": "",
			"accessories": ["apron_white", "headband"],
			"gait": {"speed": 1.45, "stride": 0.4, "bounce": 0.06, "sway": 0.1, "hunch": 0.0}, "idle": "hum"},
		"chat": "Tu entends ? Les tuyaux chantent quand il fait froid dehors. S'il y a un dehors.",
		"secret": "Il y a un nom gravé sous la cuisine. L'ancien nom du bunker. Il me fait peur.",
		"locker": "un calque de l'inscription gravée sous la cuisine", "keepsake": "le pendentif de Nour",
		"bond": "Lina et elle chantaient ensemble à la fête du solstice.",
		"motive": "Nour a lu le vrai nom du bunker : un lieu d'expérience. Elle pense que certains habitants sont des surveillants, et elle les élimine."},
	{"id": "felix", "name": "Félix", "role": "Médecin", "team": "jaune", "shoe": "L",
		"work": ["sort_meds", "brew_remedy", "write_records", "tend_patient"], "evening": ["brew_remedy", "write_records"],
		"look": {"height": 1.15, "bulk": 0.8, "head": 1.0, "legs": 1.1, "shoulders": 0.95,
			"skin": Color(0.88, 0.7, 0.58), "hair": "bald_sides", "hair_color": Color(0.5, 0.32, 0.18),
			"coat": Color(0.9, 0.9, 0.86), "pants": Color(0.32, 0.3, 0.28), "accent": Color(0.75, 0.6, 0.2),
			"eyes": Color(0.4, 0.45, 0.35), "brows": 0.9, "nose": 1.5, "beard": "mustache", "glasses": "round",
			"accessories": ["lab_coat", "stethoscope"],
			"gait": {"speed": 1.35, "stride": 0.55, "bounce": 0.01, "sway": 0.0, "hunch": -0.05}, "idle": "hands_back"},
		"chat": "Lave-toi les mains avant de toucher quoi que ce soit ici. Je ne plaisante pas.",
		"secret": "Je teste des remèdes. Sur moi d'abord. Il faut bien que quelqu'un le fasse.",
		"locker": "des seringues et un carnet de doses", "keepsake": "le stéthoscope de Félix",
		"bond": "Il avait soigné la main de Lina sans rien demander en échange.",
		"motive": "Félix teste un remède sur des gens qui ne savent rien. Les morts sont ses échecs."},
	{"id": "iris", "name": "Iris", "role": "Infirmière", "team": "jaune", "shoe": "S",
		"work": ["tend_patient", "wash_hands", "tend_patient2", "sort_meds", "write_records"], "evening": ["write_letter", "tend_patient2"],
		"look": {"height": 0.95, "bulk": 0.9, "head": 1.05, "legs": 1.0, "shoulders": 0.85,
			"skin": Color(0.95, 0.8, 0.7), "hair": "braid", "hair_color": Color(0.55, 0.16, 0.12),
			"coat": Color(0.5, 0.3, 0.45), "pants": Color(0.28, 0.2, 0.26), "accent": Color(0.88, 0.7, 0.25),
			"eyes": Color(0.2, 0.45, 0.25), "brows": 0.7, "nose": 0.75, "beard": "", "glasses": "",
			"accessories": ["nurse_cap", "satchel"],
			"gait": {"speed": 1.55, "stride": 0.55, "bounce": 0.05, "sway": 0.05, "hunch": 0.0}, "idle": "look_around"},
		"chat": "Tu as vu Maël, le frère de Lina ? Non, pour rien. Juste comme ça.",
		"secret": "Je suis amoureuse de quelqu'un ici. Je n'ai jamais osé le dire. Ne le répète pas.",
		"locker": "une lettre d'amour jamais envoyée", "keepsake": "le bracelet d'Iris",
		"bond": "Elle laissait toujours une tasse de tisane chaude à Lina après ses rondes.",
		"motive": "Iris tue ceux qui s'approchent de la personne qu'elle aime. Elle dit que c'est pour la protéger."},
]

## L'héroïne jouable.
const PLAYER := {
	"name": "Lina", "role": "Enquêtrice du Secteur C",
	"look": {"height": 1.0, "bulk": 0.9, "head": 1.05, "legs": 1.05, "shoulders": 0.95,
		"skin": Color(0.86, 0.66, 0.54), "hair": "bob", "hair_color": Color(0.12, 0.08, 0.1),
		"coat": Color(0.38, 0.22, 0.42), "pants": Color(0.16, 0.14, 0.18), "accent": Color(0.95, 0.62, 0.25),
		"eyes": Color(0.6, 0.35, 0.15), "brows": 1.0, "nose": 0.9, "beard": "", "glasses": "",
		"accessories": ["hood", "satchel", "lantern"],
		"gait": {"speed": 1.0, "stride": 0.6, "bounce": 0.05, "sway": 0.03, "hunch": 0.0}, "idle": "breathe"},
	"abilities": [
		{"id": "echo", "name": "Écho", "desc": "Révèle empreintes et indices autour de toi", "cd": 8.0, "sound": "ab_echo"},
		{"id": "thread", "name": "Fil rouge", "desc": "Près du corps : la piste du tueur. Sinon : les trajets récents", "cd": 20.0, "sound": "ab_thread"},
		{"id": "mark", "name": "Regard", "desc": "Marque la personne visée : vraie pointure, visible à travers les murs", "cd": 12.0, "sound": "ab_mark"},
		{"id": "confide", "name": "Confidence", "desc": "La personne visée livre son alibi et un secret", "cd": 6.0, "sound": "ab_confide"},
	],
}

const RUMORS := [
	"La radio a grésillé pendant toute la ronde.",
	"Il paraît que la porte scellée a vibré cette nuit.",
	"L'air est plus lourd depuis une semaine, tu ne trouves pas ?",
	"Quelqu'un a laissé la lumière de l'atelier allumée.",
	"Les rations ont encore baissé. Personne n'ose le dire.",
]

const INTRO := "1013 personnes vivent dans ce qu'elles croient être une grotte. Les parois cachent des portes blindées, des tuyaux, des inscriptions effacées. Chaque nuit, quelqu'un du Secteur C meurt. Lina a cinq jours pour trouver qui."
