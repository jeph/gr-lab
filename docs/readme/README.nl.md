<p align="center">
  <img src="../icon.png" alt="Pictogram van GR Photo" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licentie: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platforms: iOS en Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <b>Nederlands</b> ·
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

**GR Photo** is een companion-app voor Ricoh GR-camera's (GR III, GR IIIx en GR IV) op iOS en
Android. Je bekijkt en downloadt er de foto's op je camera mee, gebruikt de app als
afstandsontspanner met live view en bewaart je Beeldregeling-looks op één plek. De app is gemaakt om
snel en eenvoudig te zijn en om de kleurprofielen van de camera goed te beheren: sla de look op
waarmee een foto is gemaakt, bewerk hem met een voorvertoning erbij en laad hem in de
Aangepast-plaatsen van de camera.

GR Photo is een onafhankelijk project en is niet verbonden aan Ricoh. De app communiceert met de
camera via een protocol dat door reverse-engineering uit Ricohs eigen apps en de camerafirmware is
afgeleid; de bevindingen staan beschreven in [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="De Bibliotheek: de foto's op de camera per dag, met filters voor JPEG, RAW en video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="De pagina Looks: de drie Aangepast-plaatsen van de camera boven de looks die op de telefoon zijn opgeslagen" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="De look-editor: een voorvertoning van voor en na boven de schuifregelaars van Beeldregeling" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Live view: het beeld van de camera met belichtingsgegevens en de ontspanknop" height="400">
</p>

<p align="center">
  <sub>Bibliotheek, Looks, de look-editor en live view, in de demomodus met de gesimuleerde camera.</sub>
</p>

## Inhoud

- [Functies](#functies)
- [Vereisten](#vereisten)
- [Installatie](#installatie)
- [Gebruik](#gebruik)
- [Ontwikkeling](#ontwikkeling)
- [Bijdragen](#bijdragen)
- [Dankbetuiging](#dankbetuiging)
- [Licentie](#licentie)

## Functies

Bij GR Photo staan drie dingen voorop: snel bij je foto's komen, je niet in de weg zitten en
Beeldregeling-looks behandelen als iets wat het beheren waard is.

- **Snel.** GR Photo maakt bij het openen via Bluetooth verbinding met je camera, als die in de
  buurt is. Als je de Bibliotheek opent, wordt de camera gewekt, gaat zijn Wi-Fi aan en maakt de
  telefoon er verbinding mee, alles in één keer. De Wi-Fi blijft daarna actief terwijl je tussen
  pagina's wisselt, zodat er niets twee keer verbinding maakt en een download gewoon doorloopt.
  Bestandslijsten, miniaturen en voorvertoningen worden op de telefoon in de cache bewaard, zodat de
  Bibliotheek snel opent. Op een GR IV HDF met een Android-telefoon stond een uitgeschakelde camera
  na ongeveer 13 seconden in zijn Bibliotheek.
- **Eenvoudig in gebruik.** Je camera's staan op één scherm, en Bibliotheek, Opname en Looks zijn
  daarvandaan één tik verwijderd. GR Photo zet de camera aan, schakelt zijn Wi-Fi in en maakt er
  voor je verbinding mee, zodat je na het koppelen niets meer op de camera hoeft in te stellen. Als
  er iets misgaat, zegt de app waarom en wat je kunt controleren, met Opnieuw proberen erbij. Een
  verbinding die wegvalt, komt vanzelf terug.
- **Looks die je kunt beheren.** Bij elke foto in de Bibliotheek zie je met welke Beeldregeling hij
  is gemaakt, en met één tik sla je die op als look. Looks staan op je telefoon, van welke camera ze
  ook komen, met hun instellingen, de foto waar ze vandaan komen en een label voor de
  Aangepast-plaats waarin ze staan.
- **Een look-editor met voorvertoning.** Wijzig het basisbeeld en alle parameters die erbij horen,
  gegroepeerd als Toon, Kleur, Detail en Effecten, en bekijk het resultaat op je eigen foto of op
  een voorbeeldfoto: schuif een scheidingslijn over voor en na, zet ze naast elkaar of tik om te
  wisselen. De voorvertoning benadert de beeldverwerking van de camera, afgeleid uit de firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Looks in de camera laden.** De pagina Looks laat zien wat er in de Aangepast-plaatsen C1 tot en
  met C3 van de camera staat. Sleep een opgeslagen look naar een plaats of kies Laden in het menu
  van de look, en de camera heeft hem. Het lezen en laden van de plaatsen werkt via Bluetooth
  alleen, zonder verbinding met de Wi-Fi van de camera.
- **Bibliotheek.** Blader per dag door de foto's en video's op de camera, filter op JPEG, RAW, video
  of Niet gedownload, en open elke opname op volledig scherm met de details erbij. Download één
  opname of een selectie, als JPEG, RAW of allebei, naar een GR Photo-album in de fotobibliotheek
  van je telefoon. Downloads gaan door terwijl je een andere app gebruikt of de telefoon
  vergrendelt: Android toont ze in een melding met Pauzeren en Alles annuleren, en iOS 26 of nieuwer
  toont de voortgang op het toegangsscherm en in het Dynamic Island. Video's worden in de app
  afgespeeld.
- **Afstandsontspanner.** Een grote ontspanknop via Bluetooth alleen, met de zelfontspanner, het
  opnametransport, de functiekiezer, het aantal opnamen dat over is en de batterij. Op Android
  maken ook de volumeknoppen de foto.
- **Live view.** Het beeld van de camera via Wi-Fi: tik om scherp te stellen, stel diafragma,
  sluitertijd, ISO en belichtingscorrectie in op een draaischijf met de waarden die de camera
  aanbiedt, en wijzig opnametransport, zelfontspanner, lichtmeting en Beeldregeling.
- **Geotagging.** GR-camera's hebben geen gps. Als Live geotagging voor een camera aanstaat, stuurt
  GR Photo de locatie van je telefoon er via Bluetooth naartoe zolang de camera aanstaat, en bewaart
  de camera die in elke foto. Het start zodra je GR Photo hebt geopend en gaat door terwijl je een
  andere app gebruikt of de telefoon vergrendelt. Geotagging op de achtergrond is het alternatief
  waarbij je niets hoeft te doen: de telefoon houdt een geschiedenis van 90 dagen bij van waar hij
  is geweest, en GR Photo voegt bij het downloaden van een foto de plaats toe die het dichtst bij
  het moment van de opname is vastgelegd, zowel aan JPEG- als aan RAW-bestanden. Beide staan uit
  totdat je ze voor een camera aanzet.
- **Meerdere camera's.** Koppel er zoveel als je hebt en wissel ertussen; geef elke camera een
  andere naam of vergeet hem.
- **Thema's en talen.** De thema's Licht, Donker, Doka, Papier en Cyanotypie, en de 21 talen van de
  menu's van de camera zelf.
- **Privé.** Geen accounts, analyses, advertenties of crashrapportage. GR Photo communiceert alleen
  met je camera en, voor de kaart van de plek waar een foto is gemaakt, met OpenFreeMap; zie het
  [privacybeleid](../../app/assets/privacy.md).

## Vereisten

- Een Ricoh GR III, GR IIIx of GR IV, inclusief de HDF-uitvoeringen en de GR IV Monochrome.
- Voor Looks is een GR IV met firmware 1.04 of hoger, een GR IV HDF of een GR IV Monochrome nodig.
  De firmware van de GR III en GR IIIx biedt geen manier om de instellingen van Beeldregeling vanaf
  een telefoon te lezen of te schrijven.
- Android 12 of nieuwer, of iOS 15.5 of nieuwer.

GR Photo is nog jong. Het hardwarelogboek bevat tests met een GR IV HDF met firmware 1.20: koppelen,
verbinden, de camera wekken, bladeren, downloaden, live view en wijzigingen van scherpstelling en
belichting. De ondersteuning voor de GR III en GR IIIx komt voort uit het protocolonderzoek en is
nog niet op een camera getest. Zie
[`research/hardware-validation.md`](../../research/hardware-validation.md) voor wat er is
waargenomen.

## Installatie

Op Android download je `gr-photo-v<version>.apk` uit de
[nieuwste release](https://github.com/jeph/gr-photo/releases/latest) op je telefoon en open je het
bestand. Android vraagt één keer om toestemming om apps vanuit je browser te installeren. Elke
release is met dezelfde sleutel ondertekend, dus een nieuwere wordt over de bestaande heen
geïnstalleerd en behoudt je camera's en instellingen.

Op iOS installeer je GR Photo vanuit de [App Store](https://apps.apple.com/app/id6833800832). Een
release komt in de App Store zodra Apple hem heeft beoordeeld, dus hij kan daar een dag of twee na
de Android-release verschijnen.

Voor het bouwen vanuit de broncode is [Flutter](https://flutter.dev) 3.47 of nieuwer nodig, met de
Android SDK of Xcode geïnstalleerd en ingesteld.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` installeert de app op de telefoon die op je computer is aangesloten. Voor iOS-builds
heb je een eigen signing-team nodig met de capabilities Hotspot Configuration en Access Wi-Fi
Information. Een Android-build vanuit de broncode is ondertekend met de debugsleutel van je
computer, niet met de releasesleutel, dus Android installeert geen van beide over de andere heen:
verwijder eerst de app die je hebt.

Wil je de app zonder camera uitproberen, start hem dan in de demomodus. Die gebruikt een
gesimuleerde GR IV met voorbeeldfoto's en werkt op de Android-emulator en de iOS-simulator:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Gebruik

1. **Koppel je camera.** Tik op Camera toevoegen en volg de aanwijzingen. Op de camera vind je het
   koppelen onder MENU, E6, Draadloze comm.: zet Actiemodus op Aan, open Bezig met koppelen en kies
   Koppelen uitvoeren. Bevestig daarna de code op de telefoon en druk op OK op de camera. Bij een GR
   III of GR IIIx vind je het koppelen onder MENU, E6, Bluetooth-instelling: zet Actiemodus op Aan
   als ingeschakeld of Altijd aan, en voer de code die de camera toont in op de telefoon in plaats
   van die te bevestigen. De camera staat dan op het scherm Camera's, en GR Photo maakt er vanzelf
   verbinding mee wanneer de app wordt geopend en de camera in de buurt is.
2. **Open de Bibliotheek.** GR Photo zet de camera aan als die uit staat en maakt verbinding met
   zijn Wi-Fi. Android vraagt je één keer om het netwerk van de camera goed te keuren. Tik op een
   opname om hem te bekijken, houd ingedrukt om er meerdere te selecteren en download wat je wilt
   bewaren.
3. **Opname.** Op afstand is een ontspanknop via Bluetooth. Live view maakt verbinding met de Wi-Fi
   van de camera en toont zijn beeld, met bediening voor scherpstelling en belichting.
4. **Sla een look op.** Open een foto in de Bibliotheek en tik op Look opslaan, of maak er zelf een
   vanaf nul met + op de pagina Looks. Tik op een look om hem te bewerken en sleep hem naar C1, C2
   of C3 om hem in de camera te laden.
5. **Voeg locaties toe.** Zet Live geotagging aan op de kaart van de camera, onder Bibliotheek,
   Opname en Looks. Je telefoon vraagt of GR Photo de locatie ervan mag gebruiken. Vanaf dan wordt
   de locatie verstuurd zolang GR Photo actief is en de camera aanstaat en binnen bereik is.
   Geotagging op de achtergrond staat onder ⋯ op de kaart van de camera, en daarvoor moet locatie
   altijd toegestaan zijn.

Automatisch verbreken in Instellingen verlaat de Wi-Fi van de camera nadat GR Photo een tijd niet is
gebruikt (standaard 5 minuten). [Hoe GR Photo zich gedraagt](../behaviour.md) beschrijft elk scherm
en elke verbindingsstatus in detail.

## Ontwikkeling

### Indeling

| Pad | Inhoud |
|---|---|
| `packages/gr_protocol` | BLE GATT, de HTTP-API via Wi-Fi, de WebSocket voor wijzigingen en de sessie voor verbinden en herstellen, in pure Dart |
| `packages/gr_camera` | De cameralaag die de app aanroept voor alles wat met de camera te maken heeft: Bluetooth- en Wi-Fi-adapters (met de Kotlin- en Swift-code voor het verbinden met Wi-Fi), sessie, koppelen, scannen, Bibliotheek, Opname en live view, en tracering van elke uitwisseling |
| `packages/gr_fake_camera` | Gesimuleerde GR IV (BLE, verbinden met Wi-Fi, HTTP-server op loopback) voor tests en de demomodus |
| `app` | De Flutter-app, met Kotlin- en Swift-code voor het opslaan in de fotobibliotheek |
| `research` | Protocolonderzoek: hoe elke route en characteristic is gevonden, bewijs uit de firmware, resultaten op hardware, open vragen |
| `tool` | `check.sh`, alle controles op codekwaliteit; de scripts die een release bouwen, ondertekenen en uploaden; `testflight.sh`, een iOS-upload vanaf een Mac |

### Uitvoeren

```sh
cd app
flutter run                                  # dev-build, echte camera (vereist een telefoon met Bluetooth)
flutter run --profile                        # hetzelfde, met de snelheid van een release-build
flutter run --flavor prod --release          # de build die gebruikers krijgen
flutter run --dart-define=GR_DEMO=true       # gesimuleerde camera, werkt op de Android-emulator en de iOS-simulator
```

Er zijn twee builds. `dev` (`io.jeph.grphoto.dev`, met de naam "GR Photo Dev") wordt naast `prod`
(`io.jeph.grphoto`, "GR Photo") geïnstalleerd. Zonder `--flavor` bouwen `flutter run` en `flutter
build` de `dev`-build.

`flutter run` zonder meer maakt een debug-build, die elk frame een aantal keer trager opbouwt dan
een profile- of release-build (3 tot 4 keer in de Bibliotheek op een Android-emulator, 2026-11-10).
Beoordeel hoe vloeiend een scherm is met `--profile` of `--release`.

De demomodus bewaart zijn gegevens in een aparte map `demo/`. Bij de eerste start vindt Camera
toevoegen de gesimuleerde camera, die het koppelen zelf bevestigt; bij latere starts staat de camera
uit, en dat blijft zo totdat je de Bibliotheek opent (het wekken hoort bij het verbinden met zijn
Wi-Fi) of op de aan/uit-knop van de kaart drukt. RAW-bestanden in de demo zijn JPEG-bytes met een
`.DNG`-naam.

### Controles

```sh
tool/check.sh            # formatter, analyzer, grens van de cameralaag, vertalingen, alle testsuites
tool/check.sh --static   # zonder de tests
```

De analyzer gebruikt `very_good_analysis`, waarbij infos als fouten gelden. Android- en iOS-builds
voeren eerst `tool/check.sh --static` uit en stoppen als dat mislukt. Waarschuwingen van Kotlin en
Swift zijn fouten. Zie [`AGENTS.md`](../../AGENTS.md) voor de regels.

### Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

De integratietest doorloopt het hele demoscenario (koppelen, verbinden, bladeren, twee opnamen
downloaden) op een apparaat, emulator of simulator. Een debug-build heeft op de emulator ongeveer
400 MB vrije ruimte nodig. Op Android haalt `flutter test` de standaardflavor en de ID van de app
niet uit het project, dus zijn `--flavor dev` en een vooraf gebouwde APK nodig; zonder die twee
stopt de opdracht met "No application found".

Op de iOS-simulator moet de app geïnstalleerd zijn op het moment dat toegang tot Foto's wordt
verleend, en `flutter test` verwijdert de app na afloop, waarmee ook die toestemming verdwijnt.
GR Photo vraagt om volledige toegang, om zijn album te kunnen bijhouden, en op de simulator van
iOS 26.3 was `simctl privacy grant photos` alleen niet genoeg om te voorkomen dat iOS het vroeg: de
toestemming die het vastlegt heeft `auth_version` 1, en iOS beschouwt die pas bij 2 als volledige
toegang. Verleen de toestemming en stel die waarde in vóór elke testrun:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Debuglog

GR Photo houdt debuglogs bij zolang Instellingen > Debuglog inschakelen aanstaat: alles wat de app
naar de camera stuurt en ervan ontvangt (Bluetooth-scans, lees- en schrijfacties en meldingen, elk
HTTP-verzoek en -antwoord, WebSocket-berichten, de grootte van live-view-frames en de stappen van
het verbinden met Wi-Fi), elke regel die de app afdrukt, niet-afgevangen fouten en de regels van de
native Wi-Fi-code. De instelling staat standaard aan in `dev` en uit in `prod`. Zolang ze uit staat,
wordt er niets gelogd, ook niet naar logcat of de console, met één uitzondering: de Flutter-engine
meldt niet-afgevangen fouten daar nog altijd zelf, zodat crashes zichtbaar blijven.
Instellingen > Debuglog exporteert de log via het deelpaneel als JSON Lines-bestanden en wist hem.
De log bewaart ongeveer 50 MB. Hij bevat het Wi-Fi-wachtwoord van de camera.

### Releases

Elke push naar `main` is een release, gemaakt door
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). De workflow nummert de
release 0.0.N, één hoger dan de vorige, voert `tool/check.sh` uit en bouwt de `prod`-flavor van
beide apps in releasemodus. De Android-APK wordt ondertekend met de releasesleutel van GR Photo en
gepubliceerd op de [releasepagina](https://github.com/jeph/gr-photo/releases) met de
SHA-256-checksum, een attestatie van de herkomst van de build en de R8-mapping waarmee je de
Kotlin-stacktraces ervan leest. De iOS-app wordt ondertekend voor de App Store en geüpload naar App
Store Connect. Zodra Apple de build heeft verwerkt, zet de workflow hem in een nieuwe App
Store-versie met de nieuwe functies (What's New) van de release en dient die in ter beoordeling; de
versie gaat live zodra Apple hem goedkeurt. Een versie die nog op beoordeling wacht, wordt uit de
beoordeling gehaald en door de nieuwe vervangen. De build gaat ook naar de openbare
TestFlight-groep, waarvoor de bètabeoordeling van Apple nodig is. De sleutels staan in
GitHub-omgevingen die alleen `main` kan gebruiken, en de jobs die de apps bouwen hebben er geen
enkele van.

Elke release heeft zijn What's New nodig in alle 21 talen, één bestand per taal in
`tool/app_store/whats_new/0.0.N/<locale>.txt`, met dezelfde namen als de ARB-bestanden. De workflow
stopt voordat hij iets bouwt als er een ontbreekt of leeg is, dus de notities worden geschreven in
dezelfde wijziging als het werk dat ze beschrijven.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` controleert of een APK door die
workflow vanuit deze repository is gebouwd.

```sh
tool/testflight.sh       # bouwt de prod-app voor iOS en uploadt die naar TestFlight
```

Het script zet vanaf een Mac een build die geen release is op TestFlight. Het bouwt de
`prod`-flavor met het tijdstip van de upload als buildnummer en stuurt die naar App Store Connect,
waar hij na verwerking onder TestFlight verschijnt. Interne testers installeren hem vanuit de
TestFlight-app, zonder kabel. Xcode ondertekent en uploadt de build met een API-sleutel
van App Store Connect, dus de configuratie op een Mac bestaat uit het bestand `AuthKey_<key id>.p8`
van de sleutel in `~/.appstoreconnect/private_keys`, en `ASC_KEY_ID` en `ASC_ISSUER_ID` in
`~/.appstoreconnect/gr-photo.env`. De sleutel heeft de rol Admin nodig: Apple staat niet toe dat een
sleutel met de rol App Manager het distributiecertificaat van het team gebruikt. Het archief wordt
zonder ondertekening gebouwd en bij het exporteren voor de App Store ondertekend
(`app/ios/ExportOptions.plist`), omdat voor het ondertekenen van het archief zelf een geregistreerd
testapparaat in het team nodig zou zijn.

## Bijdragen

Bugmeldingen en pull-requests zijn welkom. De meeste bugs komen alleen op echte hardware aan het
licht, dus als je [een issue opent](https://github.com/jeph/gr-photo/issues), vermeld dan je
cameramodel en firmwareversie, het model van je telefoon met de Android- of iOS-versie, en wat je
hebt gedaan. Een geëxporteerde debuglog (Instellingen, Debuglog, Log exporteren) laat meestal zien
wat er is gebeurd, maar bevat het serienummer en het Wi-Fi-wachtwoord van je camera; voeg hem dus
alleen toe als je er geen bezwaar tegen hebt die te delen.

Voer `tool/check.sh` uit voordat je een wijziging instuurt; alle controles moeten slagen.
[`AGENTS.md`](../../AGENTS.md) beschrijft hoe de code is georganiseerd en welke regels ze volgt.

Meld vermoedelijke beveiligingslekken niet in openbare issues. Volg het
[beveiligingsbeleid](../../.github/SECURITY.md) om een kwetsbaarheid vertrouwelijk te melden.

## Dankbetuiging

GR Photo is gebouwd met [Flutter](https://flutter.dev) en gebruikt
[universal_ble](https://pub.dev/packages/universal_ble) voor Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) en
[path_provider](https://pub.dev/packages/path_provider). De tekst is gezet in
[Inter](https://rsms.me/inter/) en [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Het protocolonderzoek steunt op Ricohs apps GR WORLD en Image Sync en op de GR-firmware, en op de
aantekeningen van het project [Ricoh3x](https://github.com/Trimz/Ricoh3x) over de
Beeldregeling-instellingen van de GR IIIx.

## Licentie

GR Photo wordt uitgebracht onder de [MIT-licentie](../../LICENSE). Pakketten en lettertypen van
derden die GR Photo bevat, behouden hun eigen licentie. De app toont ze onder **Instellingen › Over
› Licenties**, en de licentieteksten van de lettertypen staan in
[`app/assets/fonts/`](../../app/assets/fonts/).

De voorbeeldfoto's van de demomodus komen van [Unsplash](https://unsplash.com) en worden gebruikt
onder de
[Unsplash-licentie](https://unsplash.com/license), niet onder de MIT-licentie;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) vermeldt ze met hun fotografen.

De apps en firmware van Ricoh, waarnaar het onderzoek verwijst, zijn eigendom van Ricoh en maken
geen deel uit van deze repository.
