# RoomScan — scanner LiDAR et maquette réaménageable

Design validé le 2026-07-31.

## Objectif

Application iOS permettant de scanner une pièce de l'appartement avec le LiDAR d'un iPhone 15 Pro, d'en obtenir une maquette 3D consultable, puis d'y réaménager les meubles détectés : les déplacer, les pivoter, les supprimer. Les pièces scannées sont conservées entre les sessions.

## Périmètre

Dans le périmètre :

- Scan d'une pièce avec détection des murs, portes, fenêtres, ouvertures et meubles.
- Maquette 3D consultable façon maison de poupée, orbitable et zoomable.
- Meubles représentés par des volumes colorés par catégorie, aux dimensions mesurées.
- Déplacement au sol, rotation autour de l'axe vertical, suppression, retour à la position d'origine.
- Bibliothèque locale de pièces enregistrées, avec agencement conservé.

Hors périmètre, explicitement :

- Ajouter des meubles absents du scan.
- Collisions ou aimantation entre meubles et murs.
- Assemblage de plusieurs pièces en un appartement complet.
- Export de fichier (USDZ, OBJ, plan 2D) et partage.
- Réalité augmentée après le scan.
- Synchronisation iCloud, comptes, multi-appareils.
- Variantes multiples d'agencement par pièce.

## Décisions de cadrage

| Question | Décision |
| --- | --- |
| Usage principal | Réaménager virtuellement |
| Lieu de l'édition | Maquette 3D hors-site, pas d'AR |
| Rendu des meubles | Volumes colorés par catégorie, étiquetés |
| Ajout de meubles | Aucun |
| Persistance | Bibliothèque locale, un agencement par pièce |
| Règles de déplacement | Meuble maintenu au sol, aucune contrainte de collision |
| Approche technique | RoomPlan clé en main + maquette RealityKit maison |

## Approche technique

L'application s'appuie sur **RoomPlan**, qui fournit la capture guidée et la classification des meubles, et sur une maquette **RealityKit** écrite à la main pour l'édition.

L'écran de scan est `RoomCaptureView`, la vue fournie par Apple : guidage à l'écran, surlignage des surfaces et des objets pendant la capture, animation de fin. En sortie, un `CapturedRoom` contient les surfaces (murs, portes, fenêtres, ouvertures, sol) et les objets, chacun avec un identifiant, des dimensions, une transformation et un indice de confiance. Les meubles sont classés dans le vocabulaire fermé de RoomPlan : rangement, réfrigérateur, cuisinière, lit, évier, lave-linge, WC, baignoire, four, lave-vaisselle, table, canapé, chaise, cheminée, télévision, escalier.

Conséquences acceptées de ce choix : un bureau sera classé « table », un meuble atypique peut être manqué, mal découpé ou fusionné avec un voisin. C'est le compromis en échange d'une détection que l'on n'écrit pas soi-même.

Alternatives écartées :

- **Session de capture pilotée à la main** (`RoomCaptureSession` + vue AR custom) : contrôle esthétique du scan, mais il faut réécrire le guidage, le retour temps réel et la gestion des états. Bénéfice cosmétique, coût élevé. À reconsidérer seulement si l'écran d'Apple s'avère insuffisant à l'usage.
- **ARKit brut** : reconstruction et classification maison. Réécrit des années de travail d'Apple pour un résultat inférieur.
- **Export USDZ + visionneuse QuickLook** : trivial, mais les meubles ne sont plus manipulables individuellement. Ne répond pas au besoin.

Le rendu utilise RealityKit et non SceneKit : SceneKit est déprécié. Le prix à payer est une caméra orbitale à écrire soi-même, environ une centaine de lignes bien cernées et testables.

## Architecture

Contrainte structurante : **RoomPlan ne fonctionne pas sur simulateur**, faute de LiDAR. Si l'éditeur dépendait du scanner, chaque ajustement d'ergonomie exigerait de brancher l'iPhone, compiler et rescanner une vraie pièce. L'éditeur ne connaît donc que le modèle de données interne, jamais RoomPlan. Un scan réel est enregistré une fois et conservé comme jeu de données d'exemple ; toute l'itération sur la maquette se fait sur simulateur.

Cinq modules, dans un projet Xcode unique :

- **RoomModel** — types purs : pièce, mur, ouverture, meuble, catégorie, agencement. Aucune dépendance à RoomPlan ni à RealityKit. C'est le vocabulaire commun.
- **RoomCapture** — la seule zone qui importe RoomPlan. Enveloppe `RoomCaptureView` dans SwiftUI, gère le cycle de vie de la session, traduit `CapturedRoom` vers `RoomModel`.
- **RoomStore** — la bibliothèque : lecture, écriture, suppression, renommage sur le disque.
- **RoomEditor** — la maquette : construction de la scène RealityKit, caméra orbitale, sélection, gestes, projection écran vers sol.
- **App** — assemblage SwiftUI et navigation.

Les dépendances pointent toutes vers `RoomModel`, qui ne dépend de personne. `RoomCapture`, `RoomStore` et `RoomEditor` s'ignorent mutuellement ; seul le module `App` les compose.

## Modèle de données

Distinction centrale : **le scan est immuable, l'agencement est modifiable.** La capture d'origine n'est jamais réécrite. À côté, l'agencement enregistre, pour chaque meuble, sa position au sol, son orientation et sa visibilité. Deux bénéfices : « Réinitialiser » redevient trivial, et réaménager ne peut jamais détruire les mesures réelles.

Types de `RoomModel` :

- `RoomScan` — capture immuable : version de schéma, murs, ouvertures, meubles, et emprise du sol. L'emprise est le polygone de sol fourni par RoomPlan lorsqu'il existe ; à défaut, le rectangle englobant des murs. Elle sert au cadrage de la caméra et au dessin de la vignette.
- `Wall` — identifiant, centre, largeur, hauteur, orientation.
- `Opening` — identifiant, nature (porte, fenêtre, ouverture), mur porteur, centre, largeur, hauteur.
- `FurniturePiece` — identifiant, catégorie, empreinte au sol (largeur, profondeur), hauteur, position d'origine, orientation d'origine, indice de confiance.
- `FurnitureCategory` — énumération reprenant les catégories RoomPlan, plus un cas inconnu pour absorber sans casse une catégorie ajoutée par une future version d'iOS.
- `Layout` — version de schéma et, par identifiant de meuble, position au sol (deux coordonnées), orientation et visibilité. Un meuble absent du dictionnaire est à sa position d'origine et visible.
- `RoomMetadata` — identifiant, nom, date de création, date de modification, version de schéma.

Les meubles restant posés au sol, l'agencement se réduit à trois nombres par meuble. La hauteur reste celle mesurée.

Repère : celui d'ARKit, axe vertical vers le haut, origine au point de départ du scan. L'orientation d'un élément est extraite de sa matrice de transformation sous forme d'un angle unique autour de la verticale.

## Persistance

Une pièce est un dossier dans le répertoire Documents de l'application, nommé par l'identifiant de la pièce, contenant quatre fichiers :

- `room.json` — métadonnées (nom, dates, version).
- `scan.json` — capture immuable.
- `layout.json` — agencement courant.
- `thumbnail.png` — vignette pour la bibliothèque.

Chaque fichier JSON porte un numéro de version de schéma, ce qui permet de faire évoluer le format sans invalider les scans existants. Une pièce dont les fichiers sont illisibles ou d'une version inconnue apparaît dans la liste comme non ouvrable, avec la possibilité de la supprimer. Elle ne provoque jamais de plantage et n'empêche pas le chargement des autres.

La vignette est un plan vu de dessus dessiné en Core Graphics à partir du modèle : contour des murs et empreintes des meubles. Ce choix évite de capturer une image de la scène 3D, reste déterministe et se teste sans écran.

L'agencement est enregistré automatiquement à chaque modification, sans bouton de sauvegarde.

## Parcours utilisateur

1. **Bibliothèque** — liste des pièces avec vignette, nom et date. Bouton pour lancer un nouveau scan. Balayage pour supprimer, appui pour renommer.
2. **Scan** — écran RoomPlan d'Apple. À la fin, un aperçu du résultat, un champ pour nommer la pièce, puis enregistrer ou recommencer.
3. **Maquette** — l'éditeur. Retour à la bibliothèque par la navigation standard.

## Éditeur maquette

La pièce apparaît comme une maquette posée devant l'utilisateur : sol plein, murs en dalles claires, ouvertures marquées en creux, un volume coloré par meuble aux dimensions réelles.

**Caméra.** Un doigt qui glisse fait orbiter autour du centre de la pièce, le pincement rapproche ou éloigne, deux doigts translatent le point de visée. Un bouton ramène à la vue de dessus, un autre recadre sur la pièce entière. L'angle vertical est borné entre le ras du sol et la verticale pour éviter les renversements de caméra.

**Occultation des murs.** Vue de l'extérieur, les murs situés entre la caméra et la pièce masquent tout l'intérieur. Les murs qui tournent le dos à la caméra sont donc masqués, recalculé à chaque mouvement de caméra. Sans ce traitement, la maquette est une boîte fermée et inutilisable.

**Sélection.** Un tap sur un meuble le surligne, affiche son étiquette (nom de catégorie et dimensions au sol en centimètres) et fait apparaître un panneau en bas : rotation par quarts de tour dans les deux sens, rotation fine par pas de quinze degrés, suppression, retour à la position d'origine. Les étiquettes ne s'affichent que pour la sélection ; les afficher toutes transformerait la maquette en mur de texte. Un tap dans le vide désélectionne.

**Déplacement.** Un glissement déplace un meuble uniquement s'il **démarre sur un meuble déjà sélectionné** ; partout ailleurs il oriente la caméra. Cette règle résout le conflit entre les deux gestes au prix d'un tap supplémentaire, sans mode à mémoriser et sans déplacement accidentel. Le meuble suit le doigt projeté sur le plan du sol : le rayon issu du point touché est intersecté avec le plan horizontal du sol, ce qui conserve une correspondance naturelle entre le geste et le déplacement à tous les niveaux de zoom.

Un meuble supprimé n'est pas effacé du scan : il est marqué invisible dans l'agencement, donc récupérable par la réinitialisation.

Aucune contrainte de collision : un meuble peut chevaucher un autre meuble ou déborder d'un mur. C'est délibéré — les mesures sont approximatives, et un blocage à deux centimètres près serait plus frustrant qu'utile.

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
- **Géométrie de l'éditeur** — orbite de caméra, bornes d'angle, cadrage automatique, projection d'un point d'écran sur le plan du sol, sélection des murs à masquer : fonctions pures, testées sur des cas connus.
- **Persistance** — aller-retour d'écriture et de relecture dans un dossier temporaire, gestion d'un fichier corrompu, d'une version inconnue, d'un dossier incomplet.
- **Vignette** — génération sur la fixture, vérification des dimensions et de la non-vacuité.

Non couvert automatiquement : le rendu RealityKit et l'écran de scan d'Apple. Vérification manuelle, sur simulateur avec la fixture pour l'ergonomie de la maquette, sur iPhone 15 Pro pour la chaîne complète.

Framework de test : Swift Testing.

## Prérequis et contraintes de développement

- Xcode 26.6, cible de déploiement iOS 18.0.
- Nom de projet et de cible : `RoomScan` — modifiable, sans incidence sur le design.
- Le scan exige un appareil physique équipé d'un LiDAR ; il faut donc une signature de développeur configurée pour déployer sur l'iPhone.
- La clé d'usage de la caméra doit figurer dans la configuration de l'application, faute de quoi le scan échoue au lancement.
- Le jeu de données d'exemple doit être produit tôt : sans lui, aucun travail sur l'éditeur n'est possible depuis le simulateur.

## Ordre de construction envisagé

1. Modèle de données et persistance, testés à vide.
2. Capture RoomPlan minimale sur appareil, jusqu'à l'enregistrement d'un scan réel exporté comme fixture.
3. Maquette et caméra sur simulateur, alimentées par la fixture.
4. Sélection, déplacement, rotation, suppression, réinitialisation.
5. Bibliothèque, vignettes, renommage, suppression.
6. Traitement des cas d'erreur et finitions.

Le détail relève du plan d'implémentation, pas de cette spec.
