# Habillage photo — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Après le scan de structure, enchaîner un habillage qui capte le relief LiDAR réel et des photos nettes, puis afficher dans la fiche une vue **Réaliste** colorée par point, à côté de la maquette.

**Architecture:** Une seule `ARSession`, créée par l'app, sert à RoomPlan puis, après `stop(pauseARSession: false)`, à une configuration ARKit avec reconstruction du relief : le repère monde reste celui du `CapturedRoom`. Tout le calcul (sélection des photos, fusion des maillages, couverture, couleurs, enchaînement des phases) vit dans un nouveau module pur **RoomDressing**, testé sur macOS avec des données synthétiques. RoomCapture ne fait qu'adapter `ARFrame` / `ARMeshAnchor` vers ces types et piloter l'écran ; RoomViewer affiche le résultat dans RealityKit.

**Tech Stack:** Swift 6.3, SwiftUI, RealityKit (`LowLevelMesh`, `CustomMaterial`), ARKit, RoomPlan, Core Image, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-06-habillage-photo-design.md`

## Global Constraints

- Cible : **iOS 26.0** ; `swift-tools-version: 6.2`, `platforms: [.iOS("26.0"), .macOS("15.0")]`.
- Aucune dépendance externe. Le `.xcodeproj` est généré par XcodeGen et **jamais commité**.
- Code, commentaires et messages de commit en anglais ; textes affichés en français.
- Appareil de test : iPhone 15 Pro `00008130-000A2068029A001C`, équipe `46C337T7YN`. Simulateur : l'**iPhone 17** existant, jamais un nouveau.
- DerivedData : un chemin **fixe par worktree**, `<worktree>/build/dd`, jamais dans `/tmp`.
- Modules purs testés par `swift test` dans `RoomKit/` ; avant chaque commit touchant l'app, `xcodebuild` doit réussir.
- Piège vérifié : `import SwiftUI` + `import RealityKit` → écrire `SwiftUI.Scene`.
- La vue réaliste est **non éclairée** (les photos contiennent déjà la lumière) ; la maquette reste éclairée.
- Plafond : **200 photos** par habillage ; budget visé **150 Mo** par pièce ; calcul des couleurs visé **< 60 s**.
- Convention caméra ARKit, à respecter partout : `transform` va de la caméra au monde ; la caméra regarde vers −Z, +Y vers le haut. Pour un point `pc` en coordonnées caméra, `d = -pc.z`, `u = fx·pc.x/d + cx`, `v = -fy·pc.y/d + cy` (pixels de l'image capteur, paysage, origine en haut à gauche).
- Classification ARKit (`ARMeshClassification.rawValue`) : none 0, wall 1, floor 2, ceiling 3, table 4, seat 5, window 6, door 7.

## Review Focus

1. **Abandon en plein habillage ou pendant le calcul** (« Annuler ») : la session s'arrête, le dossier temporaire disparaît, aucun plantage. → test `discardRemovesWorkspace` (Task 4) et test `cancelDuringColouringEndsIdle` (Task 6).
2. **Habillage vide** (passé tout de suite, aucun relief, aucune photo) : la pièce s'enregistre sans vue réaliste. → tests `fuseEmptyGivesEmptyMesh` (Task 3), `colourizeWithoutViewsLeavesEverythingUnseen` (Task 7), `emptyDressingFinishesWithoutDressing` (Task 6).
3. **Ordre d'arrivée** : le résultat RoomPlan peut arriver avant ou après la fin de l'habillage, ou échouer pendant. → tests de `CaptureFlow` (Task 6) sur les trois ordres.
4. **Téléphone agité tout le long** : aucune photo acceptée, l'avertissement « trop rapide » s'affiche. → test `fastMotionRaisesWarning` (Task 4).
5. **Fichier réaliste corrompu ou tronqué** : la fiche n'offre que la maquette, sans plantage. → test `truncatedFileThrows` (Task 1), et `RoomDetailView` masque « Réaliste » si le décodage échoue (Task 10).

---

## Structure des fichiers

```
RoomKit/Sources/RoomDressing/          # nouveau module pur (macOS + iOS)
  DressedMesh.swift                    # maillage monde + couleurs + classes
  DressedMeshFile.swift                # format binaire realistic.mesh
  CameraPose.swift                     # pose + intrinsèques + projection
  DepthMap.swift                       # profondeur Float16 + fichier
  MeshFusion.swift                     # morceaux ARKit → DressedMesh
  WallAlignment.swift                  # écart relief ↔ murs du scan
  KeyframeSelector.swift               # choix des photos + avertissement
  KeyframeManifest.swift               # photos.json
  Sharpness.swift                      # netteté d'une image
  DressingWorkspace.swift              # dossier temporaire d'habillage
  Visibility.swift                     # « ce point est-il vu par cette photo ? »
  VertexColorizer.swift                # couleur par sommet
  CoverageTracker.swift                # jauge de couverture
  CaptureFlow.swift                    # enchaînement des phases (pur)
RoomKit/Sources/RoomCapture/
  RoomCaptureController.swift          # modifié : ARSession, phases d'habillage
  RoomCaptureScreen.swift              # modifié : session partagée
  DressingRecorder.swift               # délégué ARSession, photos, relief
  KeyframeWriter.swift                 # ARFrame → JPEG + profondeur
  DressingCaptureView.swift            # ARView + surimpression du relief
  ColouringJob.swift                   # calcul des couleurs en arrière-plan
RoomKit/Sources/RoomViewer/
  RealisticMeshEntity.swift            # DressedMesh → ModelEntity
  DressedColor.metal                   # matériau non éclairé, couleur de sommet
  RealisticRoomView.swift              # vue réaliste, orbite + hauteur d'yeux
RoomKit/Sources/RoomGeometry/FirstPersonCamera.swift
RoomKit/Sources/RoomModel/ScannedRoom.swift   # + floorHeight
RoomKit/Sources/RoomStore/RoomStore.swift     # + DressingOutput, realisticMeshURL
App/ScanFlowView.swift, App/RoomDetailView.swift, App/RoomScanApp.swift
Scripts/run-device.sh, Scripts/pull-rooms.sh, project.yml, .gitignore
```

---

### Task 1: Module RoomDressing, maillage habillé et son fichier

**Files:**
- Modify: `RoomKit/Package.swift`, `project.yml`, `.gitignore`
- Create: `RoomKit/Sources/RoomDressing/DressedMesh.swift`, `DressedMeshFile.swift`, `Scripts/run-device.sh`, `Scripts/pull-rooms.sh`
- Test: `RoomKit/Tests/RoomDressingTests/DressedMeshFileTests.swift`

**Interfaces:**
- Produces:
  - `public struct DressedMesh: Equatable, Sendable { var positions: [SIMD3<Float>]; var normals: [SIMD3<Float>]; var colors: [SIMD4<UInt8>]; var indices: [UInt32]; var faceClasses: [UInt8]; var vertexCount: Int; var triangleCount: Int; static let empty; static let unseenColor = SIMD4<UInt8>(128, 128, 128, 0) }` — `colors.w == 255` : sommet vu par une photo, `0` : non vu.
  - `public enum DressedMeshFile { static let fileName = "realistic.mesh"; static func encode(_: DressedMesh) -> Data; static func decode(_: Data) throws -> DressedMesh }`
  - `public enum DressedMeshFileError: Error, Equatable { case badMagic, unsupportedVersion(UInt32), truncated }`

- [ ] **Step 1: Préparer le module et l'outillage**
  - `Package.swift` : produit et cible `RoomDressing` (dépend de `RoomModel`), cible de test `RoomDressingTests`.
  - `project.yml` : dépendance `RoomDressing` pour l'app ; `settings.base.DEVELOPMENT_TEAM: 46C337T7YN` sur la cible.
  - `.gitignore` : ajouter `build/` et `.claude/`.
  - `Scripts/run-device.sh` : `xcodegen generate`, `xcodebuild … -destination id=$DEVICE -derivedDataPath "$ROOT/build/dd" -allowProvisioningUpdates build`, `devicectl device install app`, puis `devicectl device process launch`. Le chemin vient de `ROOT`, jamais de `/tmp`.
  - `Scripts/pull-rooms.sh <dest>` : `devicectl device copy from … --domain-type appDataContainer --domain-identifier com.thibautmottet.RoomScan --source Documents/Rooms --destination <dest>`.

- [ ] **Step 2: Écrire les tests qui échouent**

```swift
@Test func encodedMeshDecodesIdentically() throws {
    let mesh = DressedMesh.sampleTriangle   // fixture de test : 3 sommets, 1 face, classe 5
    #expect(try DressedMeshFile.decode(DressedMeshFile.encode(mesh)) == mesh)
}
@Test func wrongMagicThrows() {
    #expect(throws: DressedMeshFileError.badMagic) { try DressedMeshFile.decode(Data("XXXX".utf8) + Data(count: 32)) }
}
@Test func truncatedFileThrows() {
    let data = DressedMeshFile.encode(.sampleTriangle)
    #expect(throws: DressedMeshFileError.truncated) { try DressedMeshFile.decode(data.prefix(data.count - 5)) }
}
@Test func emptyMeshRoundTrips() throws {
    #expect(try DressedMeshFile.decode(DressedMeshFile.encode(.empty)) == .empty)
}
```

- [ ] **Step 3: Lancer** `cd RoomKit && swift test --filter RoomDressingTests` → échec (types absents).
- [ ] **Step 4: Implémenter** `DressedMesh` et `DressedMeshFile`. Format petit-boutiste : `"RSDM"`, `UInt32` version `1`, `UInt32` nombre de sommets, `UInt32` nombre de faces, puis positions (3×Float32), normales (3×Float32), couleurs (4×UInt8), indices (3×UInt32 par face), classes (UInt8 par face). Une longueur incohérente donne `truncated`.
- [ ] **Step 5: Lancer** `swift test --filter RoomDressingTests` → PASS ; `xcodegen generate && xcodebuild -scheme RoomScan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build` → BUILD SUCCEEDED.
- [ ] **Step 6: Commit** `feat(dressing): add dressed mesh model and binary file format`

---

### Task 2: Afficher un maillage coloré par sommet (risque 1)

**Files:**
- Create: `RoomKit/Sources/RoomViewer/RealisticMeshEntity.swift`, `RoomKit/Sources/RoomViewer/DressedColor.metal`, `RoomKit/Sources/RoomViewer/RealisticRoomView.swift`, `RoomKit/Sources/RoomDressing/DressedMesh+Demo.swift`
- Modify: `RoomKit/Package.swift` (RoomViewer dépend de RoomDressing, ressource Metal), `App/RoomScanApp.swift`

**Interfaces:**
- Consumes: `DressedMesh` (Task 1).
- Produces:
  - `@MainActor public enum RealisticMeshEntity { static func make(_ mesh: DressedMesh) throws -> ModelEntity }`
  - `public struct RealisticRoomView: View { init(mesh: DressedMesh, room: ScannedRoom?) }` — orbite seulement à ce stade (réutilise `OrbitCamera`, `FrameFitting` et la couche de gestes de `RoomMaquetteView`).
  - `extension DressedMesh { static func demoCube(size: Float) -> DressedMesh }` — 6 faces de couleurs pures (rouge, vert, bleu, jaune, cyan, magenta), alpha 255.

- [ ] **Step 1: Implémenter `RealisticMeshEntity.make`** : `LowLevelMesh` avec attributs position (`float3`), normale (`float3`), couleur (`uchar4Normalized`, sémantique `.color`), une partie triangles ; matériau `CustomMaterial(surfaceShader:lightingModel: .unlit)` dont la fonction `dressedVertexColor` de `DressedColor.metal` écrit `params.geometry().color().rgb` en couleur de base / émissive. La bibliothèque Metal se charge par `device.makeDefaultLibrary(bundle: .module)`.
- [ ] **Step 2: Brancher une démo** : lancée avec l'argument `-demoRealistic`, l'app affiche `RealisticRoomView(mesh: .demoCube(size: 1), room: nil)` en plein écran.
- [ ] **Step 3: Vérifier sur le simulateur** : `Scripts/run-sim.sh build/realistic-demo.png` avec l'argument de lancement → le cube montre six faces aux couleurs franches, sans dégradé d'éclairage. Envoyer la capture à l'utilisateur.
- [ ] **Step 4: Vérifier sur l'iPhone** (`Scripts/run-device.sh`, même argument) → même rendu.
- [ ] **Repli si l'étape 3 ou 4 échoue** (couleur de sommet ignorée, bibliothèque Metal introuvable) : remplacer l'intérieur de `RealisticMeshEntity`/`RealisticRoomView` par SceneKit (`SCNGeometrySource(semantic: .color)`, `lightingModel = .constant`) dans un `SCNView` ; les interfaces ci-dessus ne changent pas. Noter le choix dans le message de commit.
- [ ] **Step 5: Commit** `feat(viewer): render per-vertex coloured meshes unlit`

---

### Task 3: Fusion des morceaux de relief et écart aux murs

**Files:**
- Create: `RoomKit/Sources/RoomDressing/MeshFusion.swift`, `RoomKit/Sources/RoomDressing/WallAlignment.swift`
- Test: `RoomKit/Tests/RoomDressingTests/MeshFusionTests.swift`, `WallAlignmentTests.swift`

**Interfaces:**
- Produces:
  - `public struct MeshPiece: Sendable { var localPositions: [SIMD3<Float>]; var localNormals: [SIMD3<Float>]; var indices: [UInt32]; var faceClasses: [UInt8]; var transform: simd_float4x4 }`
  - `public enum MeshFusion { static func fuse(_ pieces: [MeshPiece]) -> DressedMesh }` — positions et normales en monde (normales tournées par la partie 3×3 puis normalisées), indices décalés, couleurs `DressedMesh.unseenColor`.
  - `public enum WallAlignment { static func medianDistance(of mesh: DressedMesh, to walls: [Wall]) -> Float? }` — seuls les sommets de faces classées mur (1) comptent ; distance au plan vertical du mur le plus proche, pour les points situés dans son étendue (largeur ±0,10 m, hauteur ±0,10 m) ; médiane ; `nil` sans point de mur.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
@Test func fuseEmptyGivesEmptyMesh() { #expect(MeshFusion.fuse([]) == .empty) }
@Test func fuseAppliesTransformAndOffsetsIndices() {
    // deux triangles identiques, le second translaté de (2, 0, 0)
    let mesh = MeshFusion.fuse([.unitTriangle(at: .zero), .unitTriangle(at: [2, 0, 0])])
    #expect(mesh.vertexCount == 6)
    #expect(mesh.indices == [0, 1, 2, 3, 4, 5])
    #expect(mesh.positions[3] == [2, 0, 0])
}
@Test func fuseRotatesNormals() { /* rotation de 90° autour de Y : normale +Z → +X */ }
@Test func wallPointsThreeCentimetresOffGiveThreeCentimetres() {
    // mur de 4 m centré en (0, 1.3, 0), yaw 0 ; grille de points de mur à z = 0.03
    #expect(abs(WallAlignment.medianDistance(of: grid, to: [wall])! - 0.03) < 0.001)
}
@Test func meshWithoutWallFacesGivesNil() { /* toutes les faces classées sol */ }
```

- [ ] **Step 2: Lancer** `swift test --filter MeshFusionTests` et `--filter WallAlignmentTests` → échec.
- [ ] **Step 3: Implémenter** `MeshFusion.fuse` et `WallAlignment.medianDistance`. Plan du mur : point `center`, normale horizontale `(sin yaw, 0, cos yaw)`, direction `(cos yaw, 0, −sin yaw)`.
- [ ] **Step 4: Lancer** les deux filtres → PASS.
- [ ] **Step 5: Commit** `feat(dressing): fuse ARKit mesh pieces and measure wall alignment`

---

### Task 4: Choix des photos, poses, profondeur, netteté, dossier temporaire

**Files:**
- Create: `RoomKit/Sources/RoomDressing/CameraPose.swift`, `DepthMap.swift`, `KeyframeSelector.swift`, `KeyframeManifest.swift`, `Sharpness.swift`, `DressingWorkspace.swift`
- Test: `RoomKit/Tests/RoomDressingTests/KeyframeSelectorTests.swift`, `CameraPoseTests.swift`, `DepthMapTests.swift`, `SharpnessTests.swift`, `DressingWorkspaceTests.swift`

**Interfaces:**
- Produces:
  - `public struct CameraPose: Codable, Equatable, Sendable { var transform: simd_float4x4; var intrinsics: simd_float3x3; var resolution: SIMD2<Int>; var position: SIMD3<Float>; func project(_ world: SIMD3<Float>) -> (pixel: SIMD2<Float>, depth: Float)?; func scaled(by factor: Float) -> CameraPose }` — Codable en `transform` (16 floats, colonne par colonne), `intrinsics` (9 floats), `resolution` ([w, h]), comme `poses.json` du test. `project` suit la convention des contraintes globales et rend `nil` derrière la caméra.
  - `public struct DepthMap: Equatable, Sendable { var width: Int; var height: Int; var values: [Float]; func depth(atPixel p: SIMD2<Float>, imageResolution: SIMD2<Int>) -> Float? }` — `0` = invalide → `nil` ; `public enum DepthMapFile { static func encode(_:) -> Data; static func decode(_:) throws -> DepthMap }` (en-tête `UInt32` largeur, hauteur, puis `Float16`).
  - `public struct KeyframeSelector: Sendable { struct Thresholds { maxAngularSpeed: Float = 0.5 /* rad/s */; maxLinearSpeed: Float = 0.3 /* m/s */; minTranslation: Float = 0.25; minRotation: Float = 0.35 /* ~20° */; cap: Int = 200; evaluationInterval: TimeInterval = 0.1 }; enum Decision: Equatable { case accept, skippedInterval, insufficientHistory, trackingLimited, tooFast, notNovel, capReached }; mutating func evaluate(time: TimeInterval, transform: simd_float4x4, trackingNormal: Bool) -> Decision; private(set) var accepted: [simd_float4x4]; var isMovingTooFast: Bool }` — vitesse mesurée entre l'échantillon courant et celui d'il y a au moins 0,1 s ; nouveauté = translation > `minTranslation` **ou** angle entre axes −Z > `minRotation`, par rapport à **chaque** photo gardée ; `isMovingTooFast` vrai quand au moins 5 des 10 dernières décisions évaluées sont `tooFast`.
  - `public struct KeyframeRecord: Codable, Equatable, Sendable { var file: String /* "photos/007.jpg" */; var depthFile: String /* "depth/007.f16" */; var pose: CameraPose; var timestamp: Double; var sharpness: Float; var orientation: String = "landscapeRight" }` ; `public struct KeyframeManifest: Codable, Equatable, Sendable { var schemaVersion = 1; var keyframes: [KeyframeRecord]; static let fileName = "photos.json" }`.
  - `public enum Sharpness { static func varianceOfLaplacian(luma: [UInt8], width: Int, height: Int) -> Float }`.
  - `public struct DressingWorkspace: Sendable { static func create(in parent: URL) throws -> DressingWorkspace; let root: URL; var photosDirectory: URL; var depthDirectory: URL; var manifestURL: URL; var meshURL: URL; func discard() }`.

- [ ] **Step 1: Écrire les tests qui échouent** (extraits ; un fichier par type)

```swift
@Test func stillCameraIsAcceptedOnceThenNotNovel() {
    var s = KeyframeSelector()
    #expect(s.evaluate(time: 0, transform: .identity, trackingNormal: true) == .insufficientHistory)
    #expect(s.evaluate(time: 0.1, transform: .identity, trackingNormal: true) == .accept)
    #expect(s.evaluate(time: 0.2, transform: .identity, trackingNormal: true) == .notNovel)
}
@Test func slowThirtyCentimetreMoveIsAcceptedAgain() { /* 0,3 m en 3 s → second .accept */ }
@Test func ninetyDegreesPerSecondIsTooFast() { /* rotation Y de 0,157 rad par 0,1 s → .tooFast */ }
@Test func limitedTrackingIsRejected() { /* trackingNormal false → .trackingLimited */ }
@Test func capStopsAcceptingAt200() { /* 200 positions espacées de 0,3 m → 201e .capReached */ }
@Test func fastMotionRaisesWarning() { /* 10 décisions tooFast → isMovingTooFast == true */ }
@Test func projectsPointStraightAheadToPrincipalPoint() {
    // caméra identité, fx = fy = 1000, cx = 960, cy = 720, point (0, 0, -2)
    let hit = pose.project([0, 0, -2])!
    #expect(hit.pixel == [960, 720]); #expect(hit.depth == 2)
}
@Test func pointAboveCentreProjectsAbove() { /* (0, 0.5, -2) → v < 720 */ }
@Test func pointBehindCameraDoesNotProject() { #expect(pose.project([0, 0, 2]) == nil) }
@Test func poseDecodesProbeJSON() { /* une entrée de poses.json du test (16 + 9 floats) se décode */ }
@Test func depthRoundTripsWithinHalfPrecision() { /* écart < 0.002 m sur 0.5…4 m */ }
@Test func zeroDepthReadsAsNil() { }
@Test func checkerboardIsSharperThanFlatGrey() { }
@Test func discardRemovesWorkspace() throws {
    let w = try DressingWorkspace.create(in: tmp); w.discard()
    #expect(!FileManager.default.fileExists(atPath: w.root.path))
}
```

- [ ] **Step 2: Lancer** `swift test --filter RoomDressingTests` → échec.
- [ ] **Step 3: Implémenter** les six types. Laplacien : noyau 4-voisins sur l'image, variance des réponses.
- [ ] **Step 4: Lancer** → PASS.
- [ ] **Step 5: Commit** `feat(dressing): select keyframes and describe camera poses and depth`

---

### Task 5: Enchaînement réel sur l'iPhone : relief, photos, alignement (risques 2 et 3)

**Files:**
- Modify: `RoomKit/Sources/RoomCapture/RoomCaptureController.swift`, `RoomCaptureScreen.swift`, `RoomKit/Package.swift` (RoomCapture dépend de RoomDressing), `App/ScanFlowView.swift`
- Create: `RoomKit/Sources/RoomCapture/DressingRecorder.swift`, `KeyframeWriter.swift`, `DressingCaptureView.swift`

**Interfaces:**
- Consumes: `KeyframeSelector`, `KeyframeRecord`, `KeyframeManifest`, `DressingWorkspace`, `DepthMapFile`, `Sharpness`, `MeshPiece`, `MeshFusion`, `WallAlignment`, `RealisticMeshEntity`.
- Produces:
  - `RoomCaptureController.arSession: ARSession` (créée dans `init`, passée à `RoomCaptureView(frame:arSession:)`).
  - Nouvelle phase `.dressing` ; `finish()` appelle `captureSession.stop(pauseARSession: false)` puis lance l'habillage ; `finishDressing()` et `skipDressing()` publics.
  - `@MainActor final class DressingRecorder: NSObject, ARSessionDelegate { init(session: ARSession, workspace: DressingWorkspace); func start(); func stop() -> (pieces: [MeshPiece], manifest: KeyframeManifest); private(set) var acceptedCount: Int; private(set) var isMovingTooFast: Bool }` — `start()` lance `ARWorldTrackingConfiguration` (`sceneReconstruction = .meshWithClassification`, `frameSemantics = [.sceneDepth]`) **sans** options de réinitialisation et devient délégué de la session.
  - `struct KeyframeWriter { init(workspace: DressingWorkspace); func write(image: CVPixelBuffer, depth: CVPixelBuffer, confidence: CVPixelBuffer, pose: CameraPose, timestamp: Double, index: Int) throws -> KeyframeRecord }` — JPEG qualité 0,75 en pleine résolution ; profondeur à 0 là où la confiance est inférieure à `.medium` ; netteté calculée sur le plan Y réduit à 320×240. Appelé sur une file série d'arrière-plan, au plus 2 écritures en attente (sinon la photo est sautée).
  - `struct DressingCaptureView: UIViewRepresentable` — `ARView(frame:cameraMode: .ar, automaticallyConfigureSession: false)` dont `session` est `arSession` ; surimpression du relief fusionné, gris translucide, rafraîchie toutes les secondes.

- [ ] **Step 1: Implémenter** le passage structure → habillage dans le contrôleur et l'écran (la `RoomCaptureView` est masquée pendant l'habillage), `DressingRecorder`, `KeyframeWriter` et `DressingCaptureView`. Dans `ScanFlowView`, pendant `.dressing` : consigne « Avancez lentement, approchez-vous de chaque meuble », compteur de photos, avertissement « Trop rapide : ralentissez » quand `isMovingTooFast`, boutons « Passer » et « Terminer l'habillage ». À la fin de l'habillage, écrire dans `diagnostics` : nombre de photos, nombre de sommets, `WallAlignment.medianDistance` et `os_proc_available_memory()`.
- [ ] **Step 2: Vérifier la compilation** : `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build` → BUILD SUCCEEDED.
- [ ] **Step 3: Vérifier sur l'iPhone** (`Scripts/run-device.sh`, l'utilisateur scanne le Salon puis habille pendant 3 min) :
  - relief visible en surimpression qui se densifie ;
  - écart médian aux murs **≤ 0,05 m** ;
  - l'app n'est pas tuée et `photos/` + `depth/` + `photos.json` sont écrits (contrôle par `Scripts/pull-rooms.sh`, l'espace de travail étant gardé dans `Documents/Dressing/` pour cette vérification) ;
  - capture de l'écran d'habillage envoyée à l'utilisateur.
- [ ] **Si l'écart dépasse 0,05 m** : s'arrêter et signaler (le choix des deux temps repose sur cette hypothèse).
- [ ] **Step 4: Commit** `feat(capture): chain a dressing pass on the shared ARKit session`

---

### Task 6: Enchaînement des phases, pur et testé

**Files:**
- Create: `RoomKit/Sources/RoomDressing/CaptureFlow.swift`
- Modify: `RoomKit/Sources/RoomCapture/RoomCaptureController.swift`
- Test: `RoomKit/Tests/RoomDressingTests/CaptureFlowTests.swift`

**Interfaces:**
- Produces:
  - `public struct CaptureFlow<Room: Equatable & Sendable>: Equatable, Sendable` avec `enum Phase: Equatable { case idle, scanning, dressing, colouring(progress: Double), waitingForStructure, finished(Room, dressed: Bool), failed(String) }` et `mutating func handle(_ event: Event)` pour `enum Event { case started, structureFinishRequested, structureArrived(Room), structureFailed(String), dressingFinished(hasContent: Bool), dressingSkipped, colouringProgressed(Double), colouringSucceeded, colouringFailed, cancelled }`.
  - Règles : `dressingFinished(hasContent: false)` se comporte comme `dressingSkipped` ; `colouringFailed` mène à `finished(room, dressed: false)` ; `structureFailed` à n'importe quelle étape mène à `failed` ; `cancelled` mène à `idle` depuis toute phase.
  - `RoomCaptureController.phase` devient `CaptureFlow<ScannedRoom>.Phase` ; le contrôleur ne fait plus que traduire les événements ARKit, RoomPlan et UI en `Event`.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
@Test func structureBeforeDressingEndsFinishedAfterColouring() { /* started, finishRequested, structureArrived, dressingFinished(true), colouringSucceeded → finished(room, dressed: true) */ }
@Test func structureAfterColouringWaitsThenFinishes() { /* … colouringSucceeded → waitingForStructure ; structureArrived → finished(room, dressed: true) */ }
@Test func structureFailureDuringDressingFails() { }
@Test func colouringFailureFinishesUndressed() { }
@Test func emptyDressingFinishesWithoutDressing() { /* dressingFinished(hasContent: false) → finished(room, dressed: false) */ }
@Test func skipDressingFinishesWithoutDressing() { }
@Test func cancelDuringColouringEndsIdle() { }
```

- [ ] **Step 2: Lancer** `swift test --filter CaptureFlowTests` → échec.
- [ ] **Step 3: Implémenter** `CaptureFlow` et faire passer le contrôleur dessus. `cancel()` arrête la session et appelle `DressingWorkspace.discard()`.
- [ ] **Step 4: Lancer** `swift test` → PASS ; `xcodebuild` simulateur → BUILD SUCCEEDED.
- [ ] **Step 5: Commit** `refactor(capture): drive scan phases through a pure capture flow`

---

### Task 7: Couleur par sommet

**Files:**
- Create: `RoomKit/Sources/RoomDressing/Visibility.swift`, `VertexColorizer.swift`
- Test: `RoomKit/Tests/RoomDressingTests/VertexColorizerTests.swift`, `VisibilityTests.swift`

**Interfaces:**
- Consumes: `DressedMesh`, `CameraPose`, `DepthMap`.
- Produces:
  - `public struct RGBImage: Sendable { var width: Int; var height: Int; var pixels: [UInt8] /* RGB */; func bilinear(at p: SIMD2<Float>) -> SIMD3<Float>? }`
  - `public struct ColorView: Sendable { var pose: CameraPose; var depth: DepthMap; var sharpness: Float }`
  - `public enum Visibility { static let maxDistance: Float = 3.0; static let minCosine: Float = 0.5; static let depthTolerance: Float = 0.05; static func weight(of point: SIMD3<Float>, normal: SIMD3<Float>, in view: ColorView) -> Float? }` — `nil` si hors cadre (marge 2 px), derrière, trop loin, trop rasant ou masqué (profondeur stockée valide et écart > 0,05 m) ; sinon `cos²θ / max(d, 0.3)²`.
  - `public enum VertexColorizer { static func colourize(_ mesh: inout DressedMesh, views: [ColorView], loadImage: (Int) throws -> RGBImage, progress: (Double) -> Void) throws }`
    - boucle **extérieure sur les photos** : une seule image chargée à la fois ;
    - pour chaque sommet, on garde les 3 meilleurs échantillons, avec un poids égal à `Visibility.weight × sharpness / max(sharpness)` ;
    - couleur finale = moyenne pondérée, alpha 255 ;
    - les sommets jamais vus prennent la moyenne de leurs voisins vus (3 passes au plus), sinon `unseenColor`.
  - Les images sont lues à demi-résolution (960×720), avec `pose.scaled(by: 0.5)`.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
@Test func cubeFacesGetTheirCameraColours() throws {
    // cube de 1 m ; 6 caméras à 1,5 m face à chaque face, chacune voit une image unie de couleur différente
    try VertexColorizer.colourize(&mesh, views: views, loadImage: { solidImages[$0] }, progress: { _ in })
    // chaque sommet d'une face prend la couleur de la caméra de cette face (±2) ; alpha 255
}
@Test func occludedVertexIgnoresTheView() { /* profondeur stockée à 1 m devant un sommet à 2 m → poids nil */ }
@Test func grazingAngleIsRejected() { /* angle de 70° → nil */ }
@Test func sharperViewWins() { /* deux vues égales, l'une 4× plus nette → couleur proche de la nette */ }
@Test func colourizeWithoutViewsLeavesEverythingUnseen() { /* views vide → toutes les couleurs == unseenColor */ }
@Test func unseenVertexBorrowsNeighbourColour() { }
@Test func progressReachesOne() { }
```

- [ ] **Step 2: Lancer** `swift test --filter VertexColorizerTests` → échec.
- [ ] **Step 3: Implémenter** `Visibility` et `VertexColorizer`.
- [ ] **Step 4: Lancer** → PASS. Mesurer avec un maillage synthétique de 200 000 sommets et 200 vues en `swift test -c release` : sous 60 s, ou noter le temps dans le commit.
- [ ] **Step 5: Commit** `feat(dressing): colour mesh vertices from the best keyframes`

---

### Task 8: Jauge de couverture en direct

**Files:**
- Create: `RoomKit/Sources/RoomDressing/CoverageTracker.swift`
- Modify: `RoomKit/Sources/RoomCapture/DressingRecorder.swift`, `DressingCaptureView.swift`, `App/ScanFlowView.swift`
- Test: `RoomKit/Tests/RoomDressingTests/CoverageTrackerTests.swift`

**Interfaces:**
- Consumes: `Visibility`, `ColorView`, `DressedMesh`.
- Produces: `public struct CoverageTracker: Sendable { static let cellSize: Float = 0.05; mutating func markSeen(by view: ColorView, mesh: DressedMesh); func fraction(of mesh: DressedMesh) -> Float; func isCovered(triangle: Int, in mesh: DressedMesh) -> Bool }`
  - Chaque photo acceptée marque une fois, sur le maillage du moment, les cellules de 5 cm (centre des triangles) qu'elle voit.
  - `fraction` = aire des triangles dont la cellule est marquée / aire totale.
  - Le relief peut changer entre deux mises à jour sans tout recalculer.

- [ ] **Step 1: Écrire les tests qui échouent** : `unseenMeshIsZeroPercent`, `fullyViewedPlaneIsOneHundredPercent`, `halfViewedPlaneIsAboutFiftyPercent` (±5 %), `coverageSurvivesMeshRetriangulation` (même plan, triangulé autrement après le marquage → même fraction ±5 %).
- [ ] **Step 2: Lancer** `swift test --filter CoverageTrackerTests` → échec.
- [ ] **Step 3: Implémenter** `CoverageTracker`. Le brancher : le marquage se fait à chaque photo acceptée, sur la file d'arrière-plan. Dans la surimpression, les triangles couverts passent du gris à la teinte `#2BB3D9`. La jauge « Pièce couverte : NN % » se met à jour une fois par seconde.
- [ ] **Step 4: Lancer** `swift test` → PASS ; vérifier sur l'iPhone que la jauge monte et que les zones se teintent ; envoyer la capture.
- [ ] **Step 5: Commit** `feat(capture): show live dressing coverage`

---

### Task 9: Calcul des couleurs en arrière-plan et enregistrement

**Files:**
- Create: `RoomKit/Sources/RoomCapture/ColouringJob.swift`
- Modify: `RoomKit/Sources/RoomStore/RoomStore.swift`, `RoomKit/Package.swift` (RoomStore dépend de RoomDressing), `RoomKit/Sources/RoomCapture/RoomCaptureController.swift`, `App/ScanFlowView.swift`
- Test: `RoomKit/Tests/RoomStoreTests/RoomStoreDressingTests.swift`

**Interfaces:**
- Consumes: `CaptureFlow`, `VertexColorizer`, `MeshFusion`, `DressingWorkspace` (Task 4), `KeyframeManifest`, `DressedMeshFile`.
- Produces:
  - `struct ColouringJob { static func run(pieces: [MeshPiece], workspace: DressingWorkspace, progress: @Sendable (Double) -> Void) async throws }` : fusion, couleurs (JPEG décodé à 960×720 par Core Image), puis écriture de `workspace.meshURL`.
  - `RoomCaptureController.dressing: DressingWorkspace?` : non nul seulement si le calcul des couleurs a réussi.
  - `RoomStore.save(_:named:modelURL:dressing: DressingWorkspace? = nil)` : copie `realistic.mesh`, `photos/` et `photos.json` dans le dossier de la pièce, **sans** `depth/`. En cas d'échec, le dossier de la pièce est supprimé, comme aujourd'hui.
  - `RoomStore.realisticMeshURL(for id: UUID) -> URL?`
  - Après l'enregistrement ou l'abandon, `ScanFlowView` appelle `workspace.discard()`.

- [ ] **Step 1: Écrire les tests qui échouent** : `savingWithDressingCopiesMeshAndPhotosButNotDepth`, `realisticMeshURLIsNilWithoutDressing`, `failedDressingCopyLeavesNoFolder` (espace de travail sans `realistic.mesh` → erreur, aucun dossier).
- [ ] **Step 2: Lancer** `swift test --filter RoomStoreDressingTests` → échec.
- [ ] **Step 3: Implémenter** `RoomStore`, `ColouringJob` et le branchement : pendant `.colouring(progress:)`, un `ProgressView(value:)` affiche « Mise en couleurs… NN % ». Si le calcul échoue, l'écran de résultat affiche « Vue réaliste indisponible : la pièce sera enregistrée sans elle. »
- [ ] **Step 4: Lancer** `swift test` → PASS. Sur l'iPhone, faire un scan avec habillage puis l'enregistrer. Récupérer le dossier avec `Scripts/pull-rooms.sh` et vérifier qu'il contient `realistic.mesh`, `photos/` et `photos.json`, pas de `depth/`, et qu'il fait moins de 150 Mo.
- [ ] **Step 5: Commit** `feat(store): save the coloured mesh and keyframes with the room`

---

### Task 10: Fiche Maquette / Réaliste et vue à hauteur d'yeux

**Files:**
- Create: `RoomKit/Sources/RoomGeometry/FirstPersonCamera.swift`
- Modify: `RoomKit/Sources/RoomModel/ScannedRoom.swift`, `RoomKit/Sources/RoomViewer/RealisticRoomView.swift`, `App/RoomDetailView.swift`
- Test: `RoomKit/Tests/RoomGeometryTests/FirstPersonCameraTests.swift`, `RoomKit/Tests/RoomModelTests/ScannedRoomTests.swift`

**Interfaces:**
- Consumes: `RealisticRoomView`, `RoomStore.realisticMeshURL(for:)`, `DressedMeshFile`.
- Produces:
  - `ScannedRoom.floorHeight: Float` : moyenne de `center.y − height/2` sur les murs, 0 sans mur.
  - `public struct FirstPersonCamera: Equatable, Sendable`
    - constantes `eyeHeight: Float = 1.6` et `maxPitch: Float = 1.4` ;
    - `init(floorPoint: SIMD2<Float>, floorHeight: Float, yaw: Float)` ;
    - propriétés `position: SIMD3<Float>`, `yaw`, `pitch`, `forward: SIMD3<Float>` ;
    - méthodes `mutating func look(deltaYaw: Float, deltaPitch: Float)`, `mutating func walk(to floorPoint: SIMD2<Float>, within outline: FloorOutline)`, et `func floorHit(normalizedScreenPoint: SIMD2<Float>, verticalFieldOfView: Float, aspectRatio: Float) -> SIMD2<Float>?`.
  - `RealisticRoomView` passe en vue « À hauteur d'yeux » par un bouton. Dans ce mode :
    - glisser fait regarder autour de soi ;
    - toucher le sol amène la caméra au point touché (`floorHit` puis `walk`) ;
    - le point de départ est le centre de la pièce.
  - `RoomDetailView` affiche un `Picker` segmenté « Maquette | Réaliste » quand `realisticMeshURL` existe **et** que le fichier se décode ; la maquette est la vue par défaut.

- [ ] **Step 1: Écrire les tests qui échouent** :
  - `floorHeightIsWallBase` ;
  - `eyesStartAtOneSixtyAboveFloor` ;
  - `pitchIsClamped` ;
  - `walkStaysInsideOutline` (destination hors du sol : la caméra est ramenée au bord) ;
  - `tapBelowHorizonHitsFloorAhead` ;
  - `tapAboveHorizonHitsNothing`.
- [ ] **Step 2: Lancer** `swift test --filter FirstPersonCameraTests` et `--filter ScannedRoomTests` → échec.
- [ ] **Step 3: Implémenter** `floorHeight`, `FirstPersonCamera`, le mode hauteur d'yeux et le sélecteur.
- [ ] **Step 4: Lancer** `swift test` → PASS ; `xcodebuild` simulateur → BUILD SUCCEEDED.
- [ ] **Step 5: Vérifier sur l'iPhone, de bout en bout, sur le Salon habillé** :
  - en vue Réaliste, on reconnaît les tomettes, le canapé gris avec ses coussins bleus et la bibliothèque ;
  - les déplacements à hauteur d'yeux sont fluides ;
  - une pièce ancienne n'affiche pas le sélecteur ;
  - envoyer des captures de la vue Réaliste, en orbite et à hauteur d'yeux.
- [ ] **Step 6: Commit** `feat(viewer): switch between maquette and realistic views with eye-level walking`

---

## Commits

1. `feat(dressing): add dressed mesh model and binary file format`
2. `feat(viewer): render per-vertex coloured meshes unlit`
3. `feat(dressing): fuse ARKit mesh pieces and measure wall alignment`
4. `feat(dressing): select keyframes and describe camera poses and depth`
5. `feat(capture): chain a dressing pass on the shared ARKit session`
6. `refactor(capture): drive scan phases through a pure capture flow`
7. `feat(dressing): colour mesh vertices from the best keyframes`
8. `feat(capture): show live dressing coverage`
9. `feat(store): save the coloured mesh and keyframes with the room`
10. `feat(viewer): switch between maquette and realistic views with eye-level walking`

Tout se fait dans un worktree dédié. À la fin, on rebase sur `main` puis on fusionne en avance rapide. La branche `worktree-spike-ar-probe` est supprimée une fois la Task 5 vérifiée.
