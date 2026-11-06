# RoomScan — habillage photo réaliste d'une pièce

Design du 2026-11-06, en attente de validation. Fait suite à la spec
`2026-07-31-scanner-piece-lidar-design.md`, dont il lève une partie des exclusions.

## Intention

La maquette actuelle donne des dimensions justes mais des volumes gris : rien sur les couleurs,
les matières, l'ambiance. Le but est de **redécorer toute la pièce**. Pour cela il faut :

1. **Pour Claude** : une matière riche pour proposer une déco concrète — vraies photos de chaque
   mur, du sol et de chaque meuble, rattachées à leur place dans la pièce.
2. **Pour l'utilisateur** : l'**immersion** — se promener dans une copie 3D de sa pièce, sur le
   téléphone, avec sa **vraie forme** (relief LiDAR réel : accoudoirs, coussins, pieds) habillée
   de ses **vraies couleurs**.

Ce n'est **pas** de la réalité augmentée dans la vraie pièce : on regarde une copie sur l'écran.

## Ce qu'un test sur appareil a établi

Test jetable du 2026-11-06 sur iPhone 15 Pro (branche `worktree-spike-ar-probe`, fichier
`RoomKit/Sources/RoomCapture/CaptureProbe.swift`), scan de 3 min du Salon :

- `RoomCaptureView(frame:arSession:)` accepte une `ARSession` créée par l'app ; le scan RoomPlan
  fonctionne normalement dessus.
- Pendant le scan, `session.currentFrame` est lisible en permanence : image 1920×1440, pose et
  intrinsèques de la caméra, `sceneDepth` sur chaque image.
- **`frame.anchors` reste vide tout le scan** : RoomPlan calcule son relief en interne
  (`sceneReconstruction` rawValue 24, bits privés) et ne publie aucun `ARMeshAnchor`.
- Les poses caméra et le `CapturedRoom` partagent le même repère monde : 37 positions de caméra
  sur 40 tombent à l'intérieur du polygone des murs du scan « Salon 2 ».
- Plusieurs photos prises pendant le scan de structure sont floues : on y suit le guidage
  d'Apple, donc on bouge vite.

Conséquence : le relief réel d'Apple n'est disponible que **dans un second temps**, après
l'arrêt de RoomPlan. L'utilisateur a choisi ce **scan en deux temps enchaînés** plutôt qu'un
passage unique avec reconstruction maison (voir « Évolutions possibles »).

## Objectifs

- Après le scan de structure, enchaîner **sans quitter la caméra** sur un **habillage** :
  l'utilisateur repasse lentement autour de la pièce et devant chaque meuble.
- Pendant l'habillage, montrer en direct le relief capté et **ce qui est déjà couvert** par des
  photos nettes, avec une jauge en pourcentage.
- À la fin, calculer sur le téléphone un **modèle réaliste** : le relief réel, chaque point coloré
  d'après la meilleure photo qui le voit.
- Dans la fiche d'une pièce, un sélecteur **Maquette / Réaliste**. La vue réaliste s'orbite comme
  la maquette et propose une vue **à hauteur d'yeux** pour regarder autour de soi et se déplacer.
- Conserver les **photos retenues avec leurs poses** dans le dossier de la pièce, récupérables par
  câble (`xcrun devicectl device copy from …`) pour que Claude les analyse.

## Hors périmètre

- Réalité augmentée dans la vraie pièce (superposer une couleur de mur, un meuble virtuel).
- Traitement sur un serveur : tout se fait sur l'iPhone.
- Images plaquées nettes façon photo (atlas de textures) : c'est l'**étape 2**, après validation
  du rendu en couleurs par point.
- Habiller les pièces déjà scannées : seules les nouvelles pièces ont une vue réaliste.
- Toute édition dans la vue réaliste (déplacer, supprimer, sélectionner un meuble).
- Le passage unique avec reconstruction du relief par l'app (voie écartée pour l'instant).

## À éviter absolument

- **Dégrader le scan de structure** : guidage, détection des murs et des meubles, maquette et
  inventaire doivent rester identiques.
- **Rendre l'habillage obligatoire** : il doit pouvoir être passé ; la pièce est alors enregistrée
  comme aujourd'hui, sans vue réaliste.
- **Remplacer la maquette** : la sélection des meubles et l'inventaire restent sur la maquette.
- **Perdre un scan** sur une fin d'habillage ratée (mémoire, calcul en échec) : la structure doit
  être sauvegardable même si l'habillage échoue.

## Parcours utilisateur

1. **Nouveau scan** → scan de structure inchangé, avec le guidage RoomPlan.
2. **« Terminer »** → RoomPlan s'arrête sans couper la caméra ; son post-traitement tourne en
   arrière-plan. L'écran passe à **« Habillage »** :
   - flux caméra plein écran, relief capté en surimpression semi-transparente ;
   - le relief passe du gris à une teinte « couvert » à mesure que des photos nettes le voient ;
   - jauge « Pièce couverte : 64 % » ;
   - consigne courte : « Avancez lentement, approchez-vous de chaque meuble » ;
   - avertissement si l'appareil bouge trop vite (photos refusées) ;
   - boutons **« Terminer l'habillage »** et **« Passer »**.
3. **Fin de l'habillage** → calcul avec barre de progression, puis l'écran de résultat existant
   (nom de la pièce, enregistrement).
4. **Fiche de la pièce** → sélecteur **Maquette | Réaliste** (« Réaliste » n'apparaît que si la
   pièce a été habillée). Vue réaliste : orbite par défaut, bouton **« À hauteur d'yeux »**.

## Approche technique

### Une seule session ARKit pour les deux temps

L'app crée l'`ARSession` et la passe à `RoomCaptureView(frame:arSession:)`, comme dans le test.

À « Terminer » : `captureSession.stop(pauseARSession: false)`. Le délégué reçoit ensuite le
`CapturedRoom` comme aujourd'hui (traduction et export paramétrique inchangés). Sur la **même**
session, on lance une `ARWorldTrackingConfiguration` avec
`sceneReconstruction = .meshWithClassification` et `frameSemantics = [.sceneDepth]`, **sans**
`.resetTracking` ni `.removeExistingAnchors`, pour que le repère monde reste celui du
`CapturedRoom`. L'affichage de l'habillage passe par une vue RealityKit liée à cette session.

### Choix des photos

Évaluer les images à environ 10 Hz. En garder une si :

- le suivi est `normal` ;
- l'appareil est presque immobile (vitesses angulaire et linéaire estimées sur les poses des
  ~100 dernières ms, sous des seuils à régler pour éliminer le flou) ;
- elle apporte un point de vue nouveau : à plus de ~25 cm ou ~20° de toutes les photos déjà
  gardées.

Pour chaque photo retenue, écrire **sur disque au fil de l'eau** (pas en mémoire) : JPEG pleine
résolution, carte de profondeur (`sceneDepth`, 256×192) et sa confiance, pose caméra → monde,
intrinsèques, horodatage et une mesure de netteté de l'image. Plafond : environ 200 photos.

### Couverture

Un point du relief est « couvert » s'il est vu par au moins une photo retenue : dans le cadre, à
moins de ~3 m, sous un angle de moins de ~60° avec sa normale, et non masqué (test contre la carte
de profondeur de la photo). La jauge donne la part de la **surface** du relief couverte. Le calcul
tourne hors du fil principal, rafraîchi environ une fois par seconde.

### Calcul des couleurs (étape 1 : couleur par point)

À « Terminer l'habillage » :

1. Fusionner les `ARMeshAnchor` en un seul maillage en coordonnées monde ; conserver la
   classification ARKit par face (mur, sol, siège, table…).
2. Pour chaque sommet, chercher les photos qui le voient (cadre, angle, distance, test
   d'occultation avec la profondeur stockée).
3. Pondérer chaque photo par l'angle de vue, la distance et la netteté ; prendre la moyenne
   pondérée des meilleurs échantillons, lus par interpolation bilinéaire dans l'image.
4. Sommets vus par aucune photo : gris neutre, ou couleur des voisins.

Pièges connus : l'image ARKit est en YUV et dans l'orientation du capteur (paysage) ;
l'exposition automatique varie d'une photo à l'autre, d'où des raccords visibles.

Le calcul doit tourner en arrière-plan, avec une progression affichée, et ne pas bloquer la
sauvegarde de la structure s'il échoue.

### Fichiers dans le dossier de la pièce

En plus de `room.json`, `scan.json`, `thumbnail.png` et `model.usdz` existants :

- le modèle réaliste (maillage avec couleurs par sommet et classification) ;
- `photos/NNN.jpg` et `photos.json` (fichier, pose caméra → monde en 4×4 colonne par colonne,
  intrinsèques, résolution, horodatage, netteté) : c'est le matériau de travail de Claude ;
- les cartes de profondeur ne servent qu'au calcul et sont supprimées ensuite.

La présence du modèle réaliste suffit à savoir qu'une pièce est habillée : pas de changement de
`schemaVersion`.

### Vue réaliste

RealityKit, comme la maquette. Les couleurs viennent de photos qui contiennent déjà la lumière de
la pièce : rendu **non éclairé**, contrairement à la maquette. Orbite existante, plus une vue à
hauteur d'yeux (~1,60 m) où l'on regarde autour de soi et où l'on peut se déplacer.

## Cas limites

- **Pendant l'habillage**, la `RoomCaptureView` est masquée : son animation de fin ne doit pas se
  superposer à la caméra.
- **Photos en cours de capture** : écrites dans un dossier temporaire, déplacées dans le dossier
  de la pièce à l'enregistrement, supprimées si le scan est abandonné.
- **« Passer »** : la session ARKit s'arrête, les photos déjà prises sont jetées, la pièce
  s'enregistre comme aujourd'hui.
- **Échec du post-traitement RoomPlan** pendant l'habillage : l'erreur actuelle s'affiche à la fin
  et l'habillage est jeté, puisqu'il n'y a pas de structure à laquelle le rattacher.
- **Échec du calcul des couleurs** : la pièce s'enregistre sans vue réaliste, avec un message.
- **Orientation des photos** : elles sont gardées telles que le capteur les donne (paysage) et
  `photos.json` l'indique ; les intrinsèques s'appliquent à cette orientation.
- **Hauteur des yeux** : mesurée depuis le sol du `CapturedRoom`, pas depuis l'origine du repère.

## Découpage par modules

- **RoomCapture** : enchaînement structure → habillage → calcul, propriété de l'`ARSession`,
  écran d'habillage, adaptateurs `ARFrame` / `ARMeshAnchor` → types neutres.
- **RoomDressing** (nouveau module, pur, testable sur macOS) : sélection des photos, couverture,
  fusion des maillages, projection et calcul des couleurs, sur des types sans ARKit.
- **RoomStore** : écriture et lecture du modèle réaliste et des photos.
- **RoomViewer** : vue réaliste.
- **App** : sélecteur dans `RoomDetailView`, nouvelle étape dans le flux de scan.

## Risques à lever en premier

À vérifier sur l'iPhone avant de construire le reste :

1. **Affichage des couleurs par sommet dans RealityKit.** Les matériaux standard ignorent la
   couleur de sommet ; il faut un `LowLevelMesh` avec un matériau qui la lit, ou un import USD qui
   la prend en compte. Prouver qu'un maillage coloré par sommet s'affiche avant tout le reste.
2. **Continuité du repère.** Après `stop(pauseARSession: false)` puis la nouvelle configuration,
   le relief ARKit doit retomber sur les murs du `CapturedRoom` à ~5 cm près.
3. **Mémoire et taille.** Un habillage de 3 min avec ~200 photos doit tenir sans être tué par le
   système. Viser moins de 150 Mo par pièce.

## Tests

- **RoomDressing**, tests unitaires sur données synthétiques : un cube vu par des caméras
  synthétiques dont chaque face a une couleur connue → couleurs retrouvées ; seuils de sélection
  des photos ; calcul de couverture ; occultation.
- **Sur l'iPhone**, protocole manuel sur le Salon :
  - relief aligné sur la maquette ;
  - couverture supérieure à 90 % atteignable ;
  - calcul en moins d'une minute ;
  - pièce enregistrée en moins de 150 Mo ;
  - vue réaliste fluide ;
  - photos récupérées par câble et lisibles.
- **Critère de réussite** : en vue réaliste, on reconnaît le Salon — carrelage de tomettes
  hexagonales, canapé gris et ses coussins bleus, bibliothèque noir et bois.

## Choix faits par Claude (à vérifier par l'utilisateur)

- Étape 1 en **couleurs par point** (fiable, un peu doux sur les détails fins), images plaquées
  nettes repoussées à l'étape 2.
- Sélecteur Maquette / Réaliste dans la fiche, la maquette restant la vue par défaut.
- Vue à hauteur d'yeux en plus de l'orbite, pour l'immersion.
- Environ 200 photos au maximum et 150 Mo par pièce.
- Habillage facultatif (bouton « Passer »).
- Les photos restent dans le dossier de la pièce, sans partage ni export depuis l'app : la
  récupération passe par le câble.

## Laissé au développeur

- Valeurs exactes des seuils (flou, nouveauté du point de vue, angle, distance).
- Format du modèle réaliste sur disque et technique d'affichage des couleurs, une fois le risque 1
  levé.
- Compensation des écarts d'exposition entre photos.
- Commandes exactes de la vue à hauteur d'yeux (glisser pour regarder, toucher le sol pour s'y
  rendre, ou équivalent).
- Le code du test (`CaptureProbe`) peut servir de point de départ pour l'écriture des photos et
  des poses ; la branche du test elle-même ne sera pas fusionnée.

## Évolutions possibles

- **Étape 2** : atlas de textures, avec de vraies images plaquées et une netteté de photo.
- **Passage unique** : reconstruire le relief à partir de `sceneDepth` pendant le scan de
  structure (fusion dans une grille de voxels), pour supprimer le second passage. Plus de travail
  et un risque de surfaces dédoublées quand ARKit corrige sa position.
