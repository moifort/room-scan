# RoomScan — scanner LiDAR et maquette 3D d'une pièce

Design validé le 2026-07-31.

## Objectif

Application iOS permettant de scanner une pièce de l'appartement avec le LiDAR d'un iPhone 15 Pro, d'en reconnaître les murs, les ouvertures et les meubles, et d'en consulter une maquette 3D. Les pièces scannées sont conservées entre les sessions.

## Périmètre

Dans le périmètre :

- Scan d'une pièce avec détection des murs, portes, fenêtres, ouvertures et meubles.
- Reconnaissance des meubles : catégorie et dimensions mesurées.
- Maquette 3D consultable façon maison de poupée, orbitable et zoomable.
- Meubles représentés par des volumes colorés par catégorie.
- Sélection d'un meuble pour lire sa catégorie et ses dimensions.
- Bibliothèque locale de pièces enregistrées.

Hors périmètre, explicitement :

- Toute manipulation des meubles : déplacer, pivoter, supprimer.
- Ajouter des meubles absents du scan.
- Assemblage de plusieurs pièces en un appartement complet.
- Export de fichier (USDZ, OBJ, plan 2D) et partage.
- Réalité augmentée après le scan.
- Synchronisation iCloud, comptes, multi-appareils.

Le réaménagement virtuel reste l'objectif à terme, mais il est reporté. Le design en tient compte sans le construire : voir « Évolution prévue ».

## Décisions de cadrage

| Question | Décision |
| --- | --- |
| Usage de cette version | Scanner, reconnaître, consulter |
| Lieu de la consultation | Maquette 3D hors-site, pas d'AR |
| Rendu des meubles | Volumes colorés par catégorie, étiquetés à la sélection |
| Manipulation | Aucune |
| Persistance | Bibliothèque locale de pièces |
| Approche technique | RoomPlan clé en main + maquette RealityKit maison |

## Approche technique

L'application s'appuie sur **RoomPlan**, qui fournit la capture guidée et la classification des meubles, et sur une maquette **RealityKit** écrite à la main pour la consultation.

L'écran de scan est `RoomCaptureView`, la vue fournie par Apple : guidage à l'écran, surlignage des surfaces et des objets pendant la capture, animation de fin. En sortie, un `CapturedRoom` contient les surfaces (murs, portes, fenêtres, ouvertures, sol) et les objets, chacun avec un identifiant, des dimensions, une transformation et un indice de confiance. Les meubles sont classés dans le vocabulaire fermé de RoomPlan : rangement, réfrigérateur, cuisinière, lit, évier, lave-linge, WC, baignoire, four, lave-vaisselle, table, canapé, chaise, cheminée, télévision, escalier.

Conséquences acceptées de ce choix : un bureau sera classé « table », un meuble atypique peut être manqué, mal découpé ou fusionné avec un voisin. C'est le compromis en échange d'une détection que l'on n'écrit pas soi-même.

Alternatives écartées :

- **Session de capture pilotée à la main** (`RoomCaptureSession` + vue AR custom) : contrôle esthétique du scan, mais il faut réécrire le guidage, le retour temps réel et la gestion des états. Bénéfice cosmétique, coût élevé. À reconsidérer seulement si l'écran d'Apple s'avère insuffisant à l'usage.
- **ARKit brut** : reconstruction et classification maison. Réécrit des années de travail d'Apple pour un résultat inférieur.
- **Export USDZ + visionneuse QuickLook** : trivial, mais on perd la main sur l'apparence de la maquette et sur la sélection des meubles, et l'évolution vers le réaménagement devient impossible sans tout reprendre.

Le rendu utilise RealityKit et non SceneKit : SceneKit est déprécié. Le prix à payer est une caméra orbitale à écrire soi-même, environ une centaine de lignes bien cernées et testables.

## Architecture

Contrainte structurante : **RoomPlan ne fonctionne pas sur simulateur**, faute de LiDAR. Si la maquette dépendait du scanner, chaque ajustement d'affichage exigerait de brancher l'iPhone, compiler et rescanner une vraie pièce. Le visualiseur ne connaît donc que le modèle de données interne, jamais RoomPlan. Un scan réel est enregistré une fois et conservé comme jeu de données d'exemple ; toute l'itération sur la maquette se fait sur simulateur.

Cinq modules, dans un projet Xcode unique :

- **RoomModel** — types purs : pièce, mur, ouverture, meuble, catégorie. Aucune dépendance à RoomPlan ni à RealityKit. C'est le vocabulaire commun.
- **RoomCapture** — la seule zone qui importe RoomPlan. Enveloppe `RoomCaptureView` dans SwiftUI, gère le cycle de vie de la session, traduit `CapturedRoom` vers `RoomModel`.
- **RoomStore** — la bibliothèque : lecture, écriture, suppression, renommage sur le disque.
- **RoomViewer** — la maquette : construction de la scène RealityKit, caméra orbitale, sélection.
- **App** — assemblage SwiftUI et navigation.

Les dépendances pointent toutes vers `RoomModel`, qui ne dépend de personne. `RoomCapture`, `RoomStore` et `RoomViewer` s'ignorent mutuellement ; seul le module `App` les compose.

## Modèle de données

Types de `RoomModel` :

- `RoomScan` — capture : version de schéma, murs, ouvertures, meubles, et emprise du sol. L'emprise est le polygone de sol fourni par RoomPlan lorsqu'il existe ; à défaut, le rectangle englobant des murs. Elle sert au cadrage de la caméra et au dessin de la vignette.
- `Wall` — identifiant, centre, largeur, hauteur, orientation.
- `Opening` — identifiant, nature (porte, fenêtre, ouverture), mur porteur, centre, largeur, hauteur.
- `FurniturePiece` — identifiant, catégorie, empreinte au sol (largeur, profondeur), hauteur, position, orientation, indice de confiance.
- `FurnitureCategory` — énumération reprenant les catégories RoomPlan, plus un cas inconnu pour absorber sans casse une catégorie ajoutée par une future version d'iOS.
- `RoomMetadata` — identifiant, nom, date de création, date de modification, version de schéma.

Le scan est traité comme une donnée immuable : rien dans cette version ne le réécrit après enregistrement. Cette discipline est ce qui permettra d'ajouter plus tard un agencement modifiable sans risquer les mesures d'origine.

Repère : celui d'ARKit, axe vertical vers le haut, origine au point de départ du scan. L'orientation d'un élément est extraite de sa matrice de transformation sous forme d'un angle unique autour de la verticale.

## Persistance

Une pièce est un dossier dans le répertoire Documents de l'application, nommé par l'identifiant de la pièce, contenant trois fichiers :

- `room.json` — métadonnées (nom, dates, version).
- `scan.json` — la capture.
- `thumbnail.png` — vignette pour la bibliothèque.

Chaque fichier JSON porte un numéro de version de schéma, ce qui permet de faire évoluer le format sans invalider les scans existants. Une pièce dont les fichiers sont illisibles ou d'une version inconnue apparaît dans la liste comme non ouvrable, avec la possibilité de la supprimer. Elle ne provoque jamais de plantage et n'empêche pas le chargement des autres.

La vignette est un plan vu de dessus dessiné en Core Graphics à partir du modèle : contour des murs et empreintes des meubles. Ce choix évite de capturer une image de la scène 3D, reste déterministe et se teste sans écran.

## Parcours utilisateur

1. **Bibliothèque** — liste des pièces avec vignette, nom et date. Bouton pour lancer un nouveau scan. Balayage pour supprimer, appui pour renommer.
2. **Scan** — écran RoomPlan d'Apple. À la fin, un aperçu du résultat, un champ pour nommer la pièce, puis enregistrer ou recommencer.
3. **Maquette** — le visualiseur. Retour à la bibliothèque par la navigation standard.

## Maquette 3D

La pièce apparaît comme une maquette posée devant l'utilisateur : sol plein, murs en dalles claires, ouvertures marquées en creux, un volume coloré par meuble aux dimensions réelles.

**Caméra.** Un doigt qui glisse fait orbiter autour du centre de la pièce, le pincement rapproche ou éloigne, deux doigts translatent le point de visée. Un bouton ramène à la vue de dessus, un autre recadre sur la pièce entière. L'angle vertical est borné entre le ras du sol et la verticale pour éviter les renversements de caméra. Aucun geste n'étant attribué aux meubles dans cette version, le glissement oriente toujours la caméra.

**Occultation des murs.** Vue de l'extérieur, les murs situés entre la caméra et la pièce masquent tout l'intérieur. Les murs qui tournent le dos à la caméra sont donc masqués, recalculé à chaque mouvement de caméra. Sans ce traitement, la maquette est une boîte fermée et inutilisable.

**Sélection.** Un tap sur un meuble le surligne et affiche son étiquette : nom de catégorie et dimensions au sol en centimètres, plus la hauteur. Les étiquettes ne s'affichent que pour la sélection ; les afficher toutes transformerait la maquette en mur de texte. Un tap dans le vide désélectionne.

**Inventaire.** Un panneau escamotable liste les meubles reconnus, groupés par catégorie et comptés. Toucher une ligne sélectionne le meuble correspondant dans la maquette. C'est la lecture la plus directe du résultat de la reconnaissance, et ça évite de chasser un objet à l'œil dans la scène.

Un meuble dont l'indice de confiance rendu par RoomPlan n'est pas le plus élevé est affiché avec un contour distinct, pour que l'incertitude de la reconnaissance soit visible plutôt que silencieuse.

## Cas d'erreur

- **RoomPlan indisponible** (appareil sans LiDAR, simulateur) : la bibliothèque reste consultable, le bouton de scan est désactivé avec une explication.
- **Accès caméra refusé** : écran explicatif avec raccourci vers les Réglages.
- **Scan sans mur détecté** (abandon trop rapide) : l'enregistrement est refusé, avec proposition de recommencer.
- **Session interrompue** (appel entrant, passage en arrière-plan) : choix entre reprendre et abandonner.
- **Avertissements de suivi ou de surchauffe** émis par RoomPlan : relayés à l'utilisateur pendant le scan.
- **Dimensions aberrantes** (nulles ou démesurées) : bornées avant construction de la scène, pour qu'un objet mal mesuré ne casse pas le rendu ni le cadrage.
- **Fichiers corrompus ou de version inconnue** : pièce marquée non ouvrable, supprimable, sans effet sur les autres.
- **Espace disque insuffisant** à l'enregistrement : message explicite, le scan reste en mémoire pour permettre une seconde tentative.

## Stratégie de test

Le découpage rend testable sans appareil ni écran tout ce qui compte :

- **Traduction RoomPlan vers RoomModel** — `CapturedRoom` étant sérialisable, un scan réel est enregistré une fois au format JSON et sert de fixture. Les tests vérifient le nombre d'éléments, les catégories, les dimensions et l'extraction de l'orientation.
- **Géométrie de la maquette** — orbite de caméra, bornes d'angle, cadrage automatique, sélection des murs à masquer : fonctions pures, testées sur des cas connus.
- **Persistance** — aller-retour d'écriture et de relecture dans un dossier temporaire, gestion d'un fichier corrompu, d'une version inconnue, d'un dossier incomplet.
- **Inventaire** — groupement et comptage par catégorie à partir de la fixture.
- **Vignette** — génération sur la fixture, vérification des dimensions et de la non-vacuité.

Non couvert automatiquement : le rendu RealityKit et l'écran de scan d'Apple. Vérification manuelle, sur simulateur avec la fixture pour la maquette, sur iPhone 15 Pro pour la chaîne complète.

Framework de test : Swift Testing.

## Prérequis et contraintes de développement

- Xcode 26.6, cible de déploiement iOS 26.0.
- Nom de projet et de cible : `RoomScan` — modifiable, sans incidence sur le design.
- Le scan exige un appareil physique équipé d'un LiDAR ; il faut donc une signature de développeur configurée pour déployer sur l'iPhone.
- La clé d'usage de la caméra doit figurer dans la configuration de l'application, faute de quoi le scan échoue au lancement.
- Le jeu de données d'exemple doit être produit tôt : sans lui, aucun travail sur la maquette n'est possible depuis le simulateur.

## Ordre de construction envisagé

1. Modèle de données et persistance, testés à vide.
2. Capture RoomPlan minimale sur appareil, jusqu'à l'enregistrement d'un scan réel exporté comme fixture.
3. Maquette et caméra sur simulateur, alimentées par la fixture.
4. Sélection, étiquettes, inventaire.
5. Bibliothèque, vignettes, renommage, suppression.
6. Traitement des cas d'erreur et finitions.

Le détail relève du plan d'implémentation, pas de cette spec.

## Évolution prévue

Le réaménagement virtuel — déplacer, pivoter, supprimer les meubles — reste la destination. Deux choix de ce design lui ouvrent la voie sans coûter quoi que ce soit aujourd'hui : le scan est traité comme immuable, et la maquette est construite à la main plutôt que déléguée à une visionneuse fermée. L'ajout consistera alors à introduire un agencement modifiable enregistré à côté du scan, et à attribuer un geste aux meubles sélectionnés. Rien d'autre du design ne devrait bouger.
