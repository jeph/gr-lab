<p align="center">
  <img src="../icon.png" alt="Icône de GR Photo" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licence : MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Plateformes : iOS et Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <b>Français</b> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <a href="README.da.md">Dansk</a> ·
  <a href="README.sv.md">Svenska</a> ·
  <a href="README.fi.md">Suomi</a> ·
  <a href="README.pl.md">Polski</a> ·
  <a href="README.cs.md">Čeština</a> ·
  <a href="README.hu.md">Magyar</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.el.md">Ελληνικά</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.th.md">ไทย</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.zh.md">中文简体</a> ·
  <a href="README.zh-Hant.md">中文繁體</a> ·
  <a href="README.ja.md">日本語</a>
</p>

**GR Photo** est une application compagnon pour les appareils photo Ricoh GR (GR III, GR IIIx et
GR IV), sur iOS et Android. Elle parcourt et télécharge les photos de votre appareil photo, sert de
déclencheur à distance avec visée directe et garde vos styles Contrôle de l'image au même endroit.
Elle est conçue pour être rapide et simple à utiliser, et pour gérer correctement les profils de
couleur de l'appareil photo : enregistrez le style avec lequel une photo a été prise, modifiez-le
avec un aperçu sous les yeux et chargez-le dans les emplacements Personnalisé de l'appareil photo.

GR Photo est un projet indépendant, sans lien avec Ricoh. L'application communique avec l'appareil
photo au moyen d'un protocole obtenu par rétro-ingénierie des applications de Ricoh et du firmware
de l'appareil photo ; les résultats sont consignés dans [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="La Bibliothèque : les photos de l'appareil photo classées par jour, avec des filtres JPEG, RAW et vidéo" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="La page Styles : les trois emplacements Personnalisé de l'appareil photo au-dessus des styles enregistrés sur le téléphone" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="L'éditeur de style : un aperçu avant/après au-dessus des curseurs Contrôle de l'image" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="La visée directe : l'image de l'appareil photo avec les valeurs d'exposition et le déclencheur" height="400">
</p>

<p align="center">
  <sub>Bibliothèque, Styles, l'éditeur de style et la visée directe, en mode démo avec l'appareil photo simulé.</sub>
</p>

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Configuration requise](#configuration-requise)
- [Installation](#installation)
- [Utilisation](#utilisation)
- [Développement](#développement)
- [Contribuer](#contribuer)
- [Remerciements](#remerciements)
- [Licence](#licence)

## Fonctionnalités

GR Photo a trois priorités : vous amener vite à vos photos, se faire oublier et traiter les styles
Contrôle de l'image comme quelque chose qui mérite d'être géré.

- **Rapide.** À l'ouverture, GR Photo se connecte à votre appareil photo en Bluetooth s'il est à
  proximité. Ouvrir la Bibliothèque réveille l'appareil photo, active son Wi-Fi et le rejoint d'une
  seule traite ; le Wi-Fi reste ensuite actif quand vous passez d'une page à l'autre, si bien que
  rien ne se connecte deux fois et qu'un téléchargement se poursuit. Les listes de fichiers, les
  vignettes et les aperçus sont mis en cache sur le téléphone pour que la Bibliothèque s'ouvre
  rapidement. Avec un GR IV HDF et un téléphone Android, un appareil photo éteint a affiché sa
  Bibliothèque en 13 secondes environ.
- **Simple à utiliser.** Un seul écran réunit vos appareils photo, et Bibliothèque, Prise de vue et
  Styles en sont à un toucher. GR Photo allume l'appareil photo, active son Wi-Fi et le rejoint pour
  vous : après le jumelage, il n'y a plus rien à régler sur l'appareil photo. En cas d'échec,
  l'application indique pourquoi et ce qu'il faut vérifier, avec un bouton Réessayer. Une connexion
  qui tombe se rétablit toute seule.
- **Des styles que vous pouvez gérer.** Chaque photo de la Bibliothèque indique le Contrôle de
  l'image avec lequel elle a été prise, et un toucher suffit pour l'enregistrer comme style. Les
  styles sont conservés sur votre téléphone, quel que soit l'appareil photo dont ils proviennent,
  avec leurs réglages, la photo dont ils sont issus et une étiquette indiquant l'emplacement
  Personnalisé qui les contient.
- **Un éditeur de style avec aperçu.** Changez l'image de base et chacun de ses paramètres,
  regroupés en Tons, Couleur, Détail et Effets, et voyez le résultat sur votre propre photo ou sur
  une photo d'exemple : faites glisser un séparateur entre l'avant et l'après, affichez-les côte à
  côte ou touchez pour passer de l'un à l'autre. L'aperçu est une approximation du rendu de
  l'appareil photo, établie à partir de son firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Chargez des styles dans l'appareil photo.** La page Styles montre ce que contiennent les
  emplacements Personnalisé C1 à C3 de l'appareil photo. Faites glisser un style enregistré sur un
  emplacement, ou choisissez Charger dans son menu, et l'appareil photo le reçoit. La lecture et le
  chargement des emplacements passent par le Bluetooth seul, sans rejoindre le Wi-Fi de l'appareil
  photo.
- **Bibliothèque.** Parcourez les photos et les vidéos de l'appareil photo par jour, filtrez par
  JPEG, RAW, vidéo ou non téléchargées, et ouvrez n'importe quelle vue en plein écran avec ses
  détails. Téléchargez une vue ou une sélection, en JPEG, en RAW ou les deux, dans un album GR Photo
  de la photothèque de votre téléphone. Les téléchargements continuent pendant que vous utilisez une
  autre application ou verrouillez le téléphone : Android les affiche dans une notification avec
  Mettre en pause et Tout annuler, et iOS 26 ou version ultérieure affiche leur progression sur
  l'écran verrouillé et dans la Dynamic Island. Les vidéos se lisent dans l'application.
- **Déclencheur à distance.** Un grand bouton de déclenchement qui passe par le Bluetooth seul, avec
  le retardateur, le mode de déclenchement, la position de la molette de mode, les vues restantes et
  la batterie. Sur Android, les boutons de volume déclenchent aussi.
- **Visée directe.** L'image de l'appareil photo par le Wi-Fi : touchez pour faire la mise au point,
  réglez l'ouverture, la vitesse, la sensibilité ISO et la correction d'exposition sur une molette
  qui reprend les valeurs proposées par l'appareil photo, et changez le déclenchement, le
  retardateur, la mesure et le Contrôle de l'image.
- **Géolocalisation.** Les appareils photo GR n'ont pas de GPS. Lorsque la Géolocalisation est
  activée pour un appareil photo, GR Photo lui envoie la position de votre téléphone en Bluetooth
  tant que l'appareil photo est allumé, et l'appareil photo l'enregistre dans chaque photo. Elle
  continue pendant que vous utilisez une autre application ou verrouillez le téléphone, démarre
  toute seule quand vous allumez l'appareil photo si vous autorisez toujours l'accès à la position,
  et maintient l'horloge de l'appareil photo à l'heure de votre téléphone. La Géolocalisation en
  arrière-plan est l'alternative sans intervention : le téléphone conserve pendant 90 jours un
  historique des lieux où il s'est trouvé, et GR Photo ajoute à une photo, quand vous la
  téléchargez, le lieu enregistré au plus près de l'heure de la prise de vue, dans les fichiers JPEG
  comme RAW.
- **Plusieurs appareils photo.** Jumelez tous ceux que vous possédez et passez de l'un à l'autre ;
  renommez ou oubliez chacun d'eux.
- **Thèmes et langues.** Les thèmes Clair, Sombre, Chambre noire, Papier et Cyanotype, et les
  21 langues des menus de l'appareil photo.
- **Respect de la vie privée.** Ni compte, ni mesure d'audience, ni publicité, ni rapport de
  plantage. GR Photo ne communique qu'avec votre appareil photo, et votre position ne va qu'à votre
  appareil photo et dans vos propres photos ; consultez la
  [politique de confidentialité](../../app/assets/privacy.md).

## Configuration requise

- Un Ricoh GR III, GR IIIx ou GR IV, y compris les boîtiers HDF et le GR IV Monochrome.
- Les styles nécessitent un GR IV avec le firmware 1.04 ou ultérieur, un GR IV HDF ou un GR IV
  Monochrome. Le firmware des GR III et GR IIIx n'offre aucun moyen de lire ou d'écrire les réglages
  Contrôle de l'image depuis un téléphone.
- Android 12 ou version ultérieure, ou iOS 15 ou version ultérieure.

GR Photo est un projet jeune. Le journal des essais sur matériel consigne des sessions avec un GR IV
HDF sous firmware 1.20 : jumelage, connexion, réveil de l'appareil photo, navigation,
téléchargement, visée directe, mise au point et changements d'exposition. La prise en charge des
GR III et GR IIIx découle de l'étude du protocole et n'a pas encore été testée sur un appareil
photo. Voir [`research/hardware-validation.md`](../../research/hardware-validation.md) pour ce qui a
été observé.

## Installation

Sur Android, téléchargez `gr-photo-v<version>.apk` depuis la
[dernière version](https://github.com/jeph/gr-photo/releases/latest) sur votre téléphone et
ouvrez-le. Android demande une fois l'autorisation d'installer des applications depuis votre
navigateur. Toutes les versions sont signées avec la même clé : une version plus récente s'installe
donc par-dessus celle que vous avez et conserve vos appareils photo et vos réglages.

Sur iOS, chaque version est envoyée à TestFlight, pour l'instant uniquement aux testeurs du projet.
Il n'existe pas encore de lien TestFlight public : sur un iPhone, GR Photo s'installe donc en le
compilant à partir des sources.

La compilation à partir des sources nécessite [Flutter](https://flutter.dev) 3.47 ou ultérieur,
avec le SDK Android ou Xcode configuré.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` installe l'application sur le téléphone connecté à votre ordinateur. Les builds iOS
nécessitent votre propre équipe de signature, avec les capacités Hotspot Configuration et Access
Wi-Fi Information. Un build Android compilé à partir des sources est signé avec la clé de débogage
de votre ordinateur, et non avec la clé de publication : Android n'installe donc aucun des deux
par-dessus l'autre. Désinstallez d'abord celui que vous avez.

Pour essayer l'application sans appareil photo, lancez-la en mode démo : il utilise un GR IV simulé
avec des photos d'exemple et fonctionne sur l'émulateur Android et le simulateur iOS :

```sh
flutter run --dart-define=GR_DEMO=true
```

## Utilisation

1. **Jumelez votre appareil photo.** Touchez Ajouter un appareil photo et suivez le guide. Sur
   l'appareil photo, le jumelage se trouve sous MENU, E6, Communication sans fil : réglez Mode de
   fonctionnement sur Marche, ouvrez Jumelage et choisissez Exécuter le jumelage, puis confirmez le
   code sur le téléphone et appuyez sur OK sur l'appareil photo. L'appareil photo figure alors sur
   l'écran Appareils photo, et GR Photo s'y connecte tout seul lorsqu'il s'ouvre avec l'appareil
   photo à proximité.
2. **Ouvrez la Bibliothèque.** GR Photo allume l'appareil photo s'il est éteint et rejoint son
   Wi-Fi. Android vous demande une fois d'approuver le réseau de l'appareil photo. Touchez une vue
   pour l'afficher, maintenez l'appui pour en sélectionner plusieurs, et téléchargez ce que vous
   voulez garder.
3. **Prenez des photos.** Télécommande est un déclencheur qui passe par le Bluetooth. Visée directe
   rejoint le Wi-Fi de l'appareil photo et affiche son image, avec les commandes de mise au point et
   d'exposition.
4. **Enregistrez un style.** Ouvrez une photo dans la Bibliothèque et touchez Enregistrer le style,
   ou créez-en un de toutes pièces avec + sur la page Styles. Touchez un style pour le modifier, et
   faites-le glisser sur C1, C2 ou C3 pour le charger dans l'appareil photo.
5. **Ajoutez la position.** GR Photo propose la Géolocalisation une fois pour chaque appareil
   photo ; vous pouvez aussi l'activer plus tard en touchant la pastille sur la carte de l'appareil
   photo. Votre téléphone demande si GR Photo peut utiliser sa position. Dès lors, la position est
   envoyée chaque fois que l'appareil photo est allumé et à portée. La Géolocalisation en
   arrière-plan se trouve dans Réglages, Position, et nécessite que l'accès à la position soit
   toujours autorisé.

L'option Déconnexion automatique des Réglages quitte le Wi-Fi de l'appareil photo lorsque GR Photo
est resté inutilisé un certain temps (5 minutes par défaut). [Le comportement de
GR Photo](../behaviour.md) décrit en détail chaque écran et chaque état de connexion.

## Développement

### Organisation

| Chemin | Contenu |
|---|---|
| `packages/gr_protocol` | BLE GATT, API HTTP par Wi-Fi, WebSocket des changements et session de connexion et de reprise, en Dart pur |
| `packages/gr_camera` | La couche appareil photo que l'application appelle pour tout ce qui touche à l'appareil photo : adaptateurs Bluetooth et Wi-Fi (avec le code Kotlin et Swift de connexion au Wi-Fi), session, jumelage, recherche, Bibliothèque, Prise de vue et visée directe, et traçage de chaque échange |
| `packages/gr_fake_camera` | GR IV simulé (BLE, connexion Wi-Fi, serveur HTTP sur l'interface de bouclage) pour les tests et le mode démo |
| `app` | L'application Flutter, avec le code Kotlin et Swift d'enregistrement dans la photothèque |
| `research` | Étude du protocole : comment chaque route et chaque caractéristique a été trouvée, éléments tirés du firmware, résultats sur matériel, questions ouvertes |
| `tool` | `check.sh`, toutes les vérifications de qualité du code ; les scripts qui compilent, signent et envoient une version ; `testflight.sh`, un envoi iOS depuis un Mac |

### Exécution

```sh
cd app
flutter run                                  # build dev, appareil photo réel (nécessite un téléphone avec Bluetooth)
flutter run --profile                        # la même chose, à la vitesse d'un build release
flutter run --flavor prod --release          # le build destiné aux utilisateurs
flutter run --dart-define=GR_DEMO=true       # appareil photo simulé, fonctionne sur l'émulateur Android et le simulateur iOS
```

Il existe deux builds. `dev` (`io.jeph.grphoto.dev`, nommé « GR Photo Dev ») s'installe à côté de
`prod` (`io.jeph.grphoto`, « GR Photo »). Sans `--flavor`, `flutter run` et `flutter build`
produisent `dev`.

`flutter run` seul produit un build debug, qui met plusieurs fois plus de temps à construire chaque
image qu'un build profile ou release (3 à 4 fois dans la Bibliothèque sur un émulateur Android,
2026-11-10). Jugez de la fluidité d'un écran avec `--profile` ou `--release`.

Le mode démo conserve ses données dans un dossier `demo/` séparé. Au premier lancement, Ajouter un
appareil photo trouve l'appareil photo simulé, qui confirme le jumelage tout seul ; aux lancements
suivants, l'appareil photo est éteint au départ et le reste jusqu'à ce que vous ouvriez la
Bibliothèque (le réveiller fait partie de la connexion à son Wi-Fi) ou que vous appuyiez sur le
bouton d'alimentation de la carte. Les fichiers RAW de démo sont des octets JPEG portant un nom en
`.DNG`.

### Vérifications

```sh
tool/check.sh            # formateur, analyseur, frontière de la couche appareil photo, traductions, toutes les suites de tests
tool/check.sh --static   # sans les tests
```

L'analyseur utilise `very_good_analysis`, les infos étant traitées comme des erreurs. Les builds
Android et iOS exécutent d'abord `tool/check.sh --static` et s'arrêtent en cas d'échec. Les
avertissements Kotlin et Swift sont des erreurs. Voir [`AGENTS.md`](../../AGENTS.md) pour les
règles.

### Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Le test d'intégration déroule tout le parcours de démo (jumeler, connecter, parcourir, télécharger
deux vues) sur un appareil, un émulateur ou un simulateur. Un build debug nécessite environ 400 Mo
libres sur l'émulateur. Sur Android, `flutter test` ne reprend du projet ni le flavor par défaut ni
l'identifiant de l'application : il lui faut donc `--flavor dev` et un APK compilé au préalable ;
sans eux, il s'arrête sur « No application found ».

Sur le simulateur iOS, l'application doit être installée au moment où l'accès à Photos est accordé,
et `flutter test` la désinstalle ensuite, ce qui supprime l'autorisation. GR Photo demande l'accès
complet, afin de conserver son album, et sur le simulateur iOS 26.3, `simctl privacy grant photos`
seul n'a pas empêché iOS de poser la question : l'autorisation qu'il enregistre a un `auth_version`
de 1, et iOS ne la considère comme un accès complet qu'à 2. Accordez-la et réglez cette valeur avant
chaque exécution :

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Journal de débogage

GR Photo tient des journaux de débogage tant que Réglages > Activer le journal de débogage est
activé : tout ce qu'il envoie à l'appareil photo et en reçoit (recherches, lectures, écritures et
notifications Bluetooth, chaque requête HTTP et sa réponse, messages WebSocket, tailles des images
de la visée directe et étapes de la connexion au Wi-Fi), chaque ligne affichée par l'application,
les erreurs non interceptées et les lignes du code Wi-Fi natif. Le réglage est activé par défaut
dans `dev` et désactivé dans `prod`. Tant qu'il est désactivé, rien n'est journalisé, pas même dans
logcat ou la console, à une exception près : le moteur Flutter y signale toujours lui-même les
erreurs non interceptées, de sorte que les plantages restent visibles. Réglages > Journal de
débogage exporte le journal par la feuille de partage sous forme de fichiers JSON Lines, puis
l'efface. Le journal conserve environ 50 Mo. Il contient le mot de passe Wi-Fi de l'appareil photo.

### Versions

Chaque push sur `main` est une version, produite par
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Le workflow numérote la
version 0.0.N, soit un de plus que la précédente, exécute `tool/check.sh` et compile le flavor
`prod` des deux applications en mode release. L'APK Android est signé avec la clé de publication de
GR Photo et publié sur la [page des versions](https://github.com/jeph/gr-photo/releases) avec sa
somme de contrôle SHA-256, une attestation de provenance du build et le mapping R8 qui permet de
lire ses traces de pile Kotlin. L'application iOS est signée pour l'App Store et envoyée à
TestFlight. Les clés sont conservées dans des environnements GitHub que seule `main` peut utiliser,
et les jobs qui compilent les applications n'en détiennent aucune.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` vérifie qu'un APK a été compilé
par ce workflow à partir de ce dépôt.

```sh
tool/testflight.sh       # compile l'application iOS prod et l'envoie à TestFlight
```

Le script met sur TestFlight, depuis un Mac, un build qui n'est pas une version. Il compile le
flavor `prod` avec l'heure de l'envoi comme numéro de build et l'envoie à App
Store Connect, où il apparaît sous TestFlight une fois traité. Les testeurs internes l'installent
depuis l'application TestFlight, sans câble. Xcode signe et envoie le build avec une clé d'API App
Store Connect : la configuration sur un Mac se résume donc au fichier `AuthKey_<key id>.p8` de la
clé dans `~/.appstoreconnect/private_keys`, ainsi qu'à `ASC_KEY_ID` et `ASC_ISSUER_ID` dans
`~/.appstoreconnect/gr-photo.env`. La clé doit avoir le rôle Admin : Apple ne permet pas à une clé
Gestionnaire d'apps d'utiliser le certificat de distribution de l'équipe. L'archive est compilée
sans signature et signée pour l'App Store à l'exportation (`app/ios/ExportOptions.plist`), car
signer l'archive elle-même exigerait un appareil de test enregistré dans l'équipe.

## Contribuer

Les rapports de bug et les pull requests sont les bienvenus. La plupart des bugs n'apparaissent que
sur du matériel réel : lorsque vous [ouvrez une issue](https://github.com/jeph/gr-photo/issues),
merci d'indiquer le modèle de votre appareil photo et la version de son firmware, le modèle de votre
téléphone et sa version d'Android ou d'iOS, et ce que vous avez fait. Un journal de débogage exporté
(Réglages, Journal de débogage, Exporter le journal) montre généralement ce qui s'est passé, mais il
contient le numéro de série et le mot de passe Wi-Fi de votre appareil photo : ne le joignez que si
vous acceptez de les partager.

Avant d'envoyer une modification, exécutez `tool/check.sh` ; toutes les vérifications doivent
réussir. [`AGENTS.md`](../../AGENTS.md) décrit l'organisation du code et les règles qu'il suit.

Ne signalez pas de failles de sécurité présumées dans des issues publiques. Suivez la
[politique de sécurité](../../.github/SECURITY.md) pour soumettre un signalement de vulnérabilité
privé.

## Remerciements

GR Photo est développé avec [Flutter](https://flutter.dev) et utilise
[universal_ble](https://pub.dev/packages/universal_ble) pour le Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) et
[path_provider](https://pub.dev/packages/path_provider). Ses textes sont composés en
[Inter](https://rsms.me/inter/) et en [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

L'étude du protocole s'appuie sur les applications GR WORLD et Image Sync de Ricoh et sur le
firmware des GR, ainsi que sur les notes du projet [Ricoh3x](https://github.com/Trimz/Ricoh3x)
concernant les réglages Contrôle de l'image du GR IIIx.

## Licence

GR Photo est publié sous [licence MIT](../../LICENSE). Les paquets et les polices tiers que GR Photo
intègre conservent leurs propres licences. L'application les répertorie sous
**Réglages › À propos › Licences**, et les textes des licences des polices se trouvent dans
[`app/assets/fonts/`](../../app/assets/fonts/).

Les photos d'exemple du mode démo proviennent d'[Unsplash](https://unsplash.com) et sont utilisées
sous
[licence Unsplash](https://unsplash.com/license), et non sous licence MIT ;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) les répertorie avec leurs
photographes.

Les applications et le firmware de Ricoh, que l'étude cite, appartiennent à Ricoh et ne font pas
partie de ce dépôt.
