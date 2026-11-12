<p align="center">
  <img src="../icon.png" alt="GR Photo-ikon" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licens: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platforme: iOS og Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <b>Dansk</b> ·
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

**GR Photo** er en ledsagerapp til Ricoh GR-kameraer (GR III, GR IIIx og GR IV) til iOS og Android.
Med den kan du gennemse og downloade billederne på dit kamera, bruge telefonen som fjernudløser med
live view og samle dine looks til Billedkontrol ét sted. Appen er lavet til at være hurtig og nem at
bruge og til at håndtere kameraets farveprofiler ordentligt: Gem det look, et billede blev taget
med, rediger det med en forhåndsvisning, og indlæs det i kameraets Tilpasset-pladser.

GR Photo er et uafhængigt projekt og er ikke tilknyttet Ricoh. Appen kommunikerer med kameraet via
en protokol, der er fundet ved reverse engineering af Ricohs egne apps og kameraets firmware;
resultaterne er beskrevet i [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Bibliotek: kameraets billeder dag for dag med filtre for JPEG, RAW og video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Siden Looks: kameraets tre Tilpasset-pladser over de looks, der er gemt på telefonen" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Look-editoren: en før og efter-forhåndsvisning over skyderne til Billedkontrol" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Live view: kameraets billede med eksponeringsværdier og udløseren" height="400">
</p>

<p align="center">
  <sub>Bibliotek, Looks, look-editoren og live view i demotilstand med det simulerede kamera.</sub>
</p>

## Indhold

- [Funktioner](#funktioner)
- [Krav](#krav)
- [Installation](#installation)
- [Brug](#brug)
- [Udvikling](#udvikling)
- [Bidrag](#bidrag)
- [Tak](#tak)
- [Licens](#licens)

## Funktioner

GR Photo sætter tre ting først: at du hurtigt kommer til dine billeder, at appen ikke står i vejen,
og at looks til Billedkontrol er noget, det er værd at holde styr på.

- **Hurtig.** GR Photo opretter forbindelse til dit kamera via Bluetooth, når appen åbnes, hvis
  kameraet er i nærheden. Når du åbner Bibliotek, vækkes kameraet, dets Wi-Fi slås til, og telefonen
  kobler sig på i én arbejdsgang. Derefter bliver Wi-Fi-forbindelsen stående, mens du skifter mellem
  siderne, så der ikke skal forbindes to gange, og en download fortsætter. Fillister, miniaturer og
  forhåndsvisninger gemmes i en cache på telefonen, så Bibliotek åbner hurtigt. Med et GR IV HDF og
  en Android-telefon tog det ca. 13 sekunder at nå fra slukket kamera til dets Bibliotek.
- **Nem at bruge.** Ét skærmbillede viser dine kameraer, og Bibliotek, Optag og Looks er ét tryk
  derfra. GR Photo tænder kameraet, slår dets Wi-Fi til og opretter forbindelsen for dig, så der er
  intet at indstille på kameraet efter parringen. Når noget går galt, fortæller appen hvorfor, og
  hvad du skal kontrollere, og tilbyder Prøv igen. En forbindelse, der ryger, kommer tilbage af sig
  selv.
- **Looks, du kan holde styr på.** Hvert billede i Bibliotek viser den Billedkontrol, det blev taget
  med, og med ét tryk gemmer du den som et look. Looks ligger på din telefon, uanset hvilket kamera
  de kommer fra, med deres indstillinger, det billede, de stammer fra, og et mærke for den
  Tilpasset-plads, de ligger i.
- **En look-editor med forhåndsvisning.** Skift basisbilledet og alle dets parametre, grupperet som
  Tone, Farve, Detaljer og Effekter, og se resultatet på dit eget billede eller et eksempelbillede:
  Træk en skillelinje hen over før og efter, stil dem side om side, eller tryk for at skifte.
  Forhåndsvisningen er en tilnærmelse af kameraets billedbehandling, udledt af dets firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Indlæs looks i kameraet.** Siden Looks viser, hvad kameraets Tilpasset-pladser C1 til C3
  indeholder. Træk et gemt look til en plads, eller vælg Indlæs i dets menu, så har kameraet det.
  Pladserne læses og indlæses via Bluetooth alene, uden at telefonen kobler sig på kameraets Wi-Fi.
- **Bibliotek.** Gennemse kameraets billeder og videoer dag for dag, filtrer efter JPEG, RAW, video
  eller Ikke downloadet, og åbn en hvilken som helst optagelse i fuld skærm med dens detaljer.
  Download en enkelt optagelse eller et udvalg, som JPEG, RAW eller begge dele, til et
  GR Photo-album i telefonens fotobibliotek. Downloads fortsætter, mens du bruger en anden app eller
  låser telefonen: Android viser dem i en notifikation med Sæt på pause og Annuller alle, og iOS 26
  og nyere viser forløbet på låseskærmen og i Dynamic Island. Videoer afspilles i appen.
- **Fjernudløser.** En stor udløserknap via Bluetooth alene, med selvudløseren, motorfunktionen,
  funktionsvælgeren, billeder tilbage og batteri. På Android udløser lydstyrkeknapperne også
  lukkeren.
- **Live view.** Kameraets billede via Wi-Fi: Tryk for at fokusere, indstil blænde, lukkertid, ISO
  og eksponeringskompensation på en drejeskive med de værdier, kameraet tilbyder, og skift Motor,
  Selvudløser, Lysmåling og Billedkontrol.
- **Geotagging.** GR-kameraer har ingen GPS. Når Live-geotagging er slået til for et kamera, sender
  GR Photo din telefons lokalitet til det via Bluetooth, mens kameraet er tændt, og kameraet gemmer
  den i hvert billede. Det starter, når du har åbnet GR Photo, og fortsætter, mens du bruger en
  anden app eller låser telefonen. Geotagging i baggrunden er alternativet, der passer sig selv:
  Telefonen gemmer 90 dages historik over, hvor den har været, og når du downloader et billede,
  tilføjer GR Photo det sted, der blev registreret tættest på det tidspunkt, hvor billedet blev
  taget, i både JPEG- og RAW-filer. Begge er slået fra, indtil du slår dem til for et kamera.
- **Flere kameraer.** Par alle dem, du ejer, og skift mellem dem; hvert kamera kan omdøbes eller
  glemmes.
- **Temaer og sprog.** Temaerne Lyst, Mørkt, Mørkekammer, Papir og Cyanotypi og de 21 sprog fra
  kameraets egne menuer.
- **Privat.** Ingen konti, analyse, reklamer eller nedbrudsrapportering. GR Photo kommunikerer kun
  med dit kamera, og din lokalitet sendes kun til dit kamera og gemmes kun i dine egne billeder; se
  [privatlivspolitikken](../../app/assets/privacy.md).

## Krav

- Et Ricoh GR III, GR IIIx eller GR IV, herunder HDF-modellerne og GR IV Monochrome.
- Looks kræver et GR IV med firmware 1.04 eller nyere, et GR IV HDF eller et GR IV Monochrome.
  Firmwaren i GR III og GR IIIx giver ingen mulighed for at læse eller skrive indstillingerne for
  Billedkontrol fra en telefon.
- Android 12 eller nyere, eller iOS 15 eller nyere.

GR Photo er en ung app. Hardwareloggen dokumenterer kørsler med et GR IV HDF med firmware 1.20:
parring, forbindelse, vækning af kameraet, gennemsyn, download, live view samt ændring af fokus og
eksponering. Understøttelsen af GR III og GR IIIx bygger på protokolundersøgelserne og er endnu ikke
afprøvet på et kamera. Se [`research/hardware-validation.md`](../../research/hardware-validation.md)
for, hvad der er observeret.

## Installation

På Android henter du `gr-photo-v<version>.apk` fra den
[seneste udgivelse](https://github.com/jeph/gr-photo/releases/latest) på din telefon og åbner filen.
Android beder én gang om tilladelse til at installere apps fra din browser. Alle udgivelser er
signeret med den samme nøgle, så en nyere installeres oven på den, du har, og beholder dine kameraer
og indstillinger.

På iOS sendes alle udgivelser til TestFlight, indtil videre kun til projektets egne testere. Der
findes endnu intet offentligt TestFlight-link, så på en iPhone installeres GR Photo ved at bygge
appen fra kildekoden.

At bygge fra kildekoden kræver [Flutter](https://flutter.dev) 3.47 eller nyere med Android SDK eller
Xcode sat op.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` installerer på den telefon, der er sluttet til din computer. iOS-builds kræver dit
eget signeringsteam med capabilities Hotspot Configuration og Access Wi-Fi Information. Et
Android-build fra kildekoden er signeret med din computers debugnøgle, ikke med udgivelsesnøglen, så
Android installerer ingen af dem oven på den anden: Afinstaller først den, du har.

Vil du prøve appen uden et kamera, kan du køre den i demotilstand, som bruger et simuleret GR IV med
eksempelbilleder og virker på Android-emulatoren og iOS-simulatoren:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Brug

1. **Par dit kamera.** Tryk på Tilføj et kamera, og følg vejledningen. På kameraet ligger parringen
   under MENU, E6, Trådløs kommunikation: Indstil Funktionstilstand til Tændt, åbn Parring, og vælg
   Udfør parring. Bekræft derefter koden på telefonen, og tryk på OK på kameraet. Kameraet står
   herefter på skærmen Kameraer, og GR Photo opretter selv forbindelse til det, når appen åbnes med
   kameraet i nærheden.
2. **Åbn Bibliotek.** GR Photo tænder kameraet, hvis det er slukket, og kobler sig på dets Wi-Fi.
   Android beder dig godkende kameraets netværk én gang. Tryk på en optagelse for at se den, hold
   fingeren på en for at vælge flere, og download dem, du vil beholde.
3. **Optag.** Fjernbetjening er en udløser via Bluetooth. Live view kobler sig på kameraets Wi-Fi og
   viser dets billede med betjening af fokus og eksponering.
4. **Gem et look.** Åbn et billede i Bibliotek, og tryk på Gem look, eller opret et fra bunden med +
   på siden Looks. Tryk på et look for at redigere det, og træk det til C1, C2 eller C3 for at
   indlæse det i kameraet.
5. **Tilføj lokalitet.** Slå Live-geotagging til på kameraets kort, under Bibliotek, Optag og Looks.
   Din telefon spørger, om GR Photo må bruge dens lokalitet. Derefter sendes lokaliteten, mens GR
   Photo kører, og kameraet er tændt og inden for rækkevidde. Geotagging i baggrunden findes under ⋯
   på kameraets kort og kræver, at lokalitet altid er tilladt.

Afbryd automatisk i Indstillinger afbryder kameraets Wi-Fi, når GR Photo ikke har været i brug et
stykke tid (som standard 5 minutter). [Sådan opfører GR Photo sig](../behaviour.md) beskriver hvert
skærmbillede og hver forbindelsestilstand i detaljer.

## Udvikling

### Opbygning

| Sti | Indhold |
|---|---|
| `packages/gr_protocol` | BLE GATT, HTTP-API'et via Wi-Fi, WebSocket til ændringer og sessionen, der opretter og genopretter forbindelsen, i ren Dart |
| `packages/gr_camera` | Kameralaget, som appen kalder til alt, der har med kameraet at gøre: Bluetooth- og Wi-Fi-adaptere (med Kotlin- og Swift-koden, der opretter Wi-Fi-forbindelsen), session, parring, scanning, Bibliotek, Optag og live view samt sporing af al kommunikation |
| `packages/gr_fake_camera` | Simuleret GR IV (BLE, Wi-Fi-forbindelse, HTTP-server på loopback) til test og demotilstand |
| `app` | Flutter-appen med Kotlin- og Swift-kode til at gemme i fotobiblioteket |
| `research` | Protokolundersøgelser: hvordan hver rute og characteristic blev fundet, belæg fra firmwaren, resultater fra hardware, åbne spørgsmål |
| `tool` | `check.sh`, alle kontroller af kodekvaliteten; de scripts, der bygger, signerer og uploader en udgivelse; `testflight.sh`, en upload til iOS fra en Mac |

### Kørsel

```sh
cd app
flutter run                                  # dev-build, rigtigt kamera (kræver en telefon med Bluetooth)
flutter run --profile                        # det samme, med samme hastighed som et release-build
flutter run --flavor prod --release          # det build, brugerne får
flutter run --dart-define=GR_DEMO=true       # simuleret kamera, virker på Android-emulatoren og iOS-simulatoren
```

Der er to builds. `dev` (`io.jeph.grphoto.dev`, med navnet "GR Photo Dev") installeres ved siden af
`prod` (`io.jeph.grphoto`, "GR Photo"). Uden `--flavor` bygger `flutter run` og `flutter build`
`dev`.

`flutter run` alene laver et debug-build, som bygger hvert billede flere gange langsommere end et
profile- eller release-build (3 til 4 gange i Bibliotek på en Android-emulator, 2026-11-10). Bedøm,
hvor flydende et skærmbillede er, med `--profile` eller `--release`.

Demotilstanden opbevarer sine data i en separat `demo/`-mappe. Ved første start finder Tilføj et
kamera det simulerede kamera, og det bekræfter selv parringen; ved senere starter er kameraet
slukket, og det forbliver slukket, indtil du åbner Bibliotek (at vække det er en del af at koble sig
på dets Wi-Fi) eller trykker på tænd/sluk-knappen på kortet. RAW-filerne i demotilstand er
JPEG-bytes med et `.DNG`-navn.

### Kontroller

```sh
tool/check.sh            # formatering, analyzer, kameralagets grænse, oversættelser, alle testsuiter
tool/check.sh --static   # uden testene
```

Analyzeren bruger `very_good_analysis`, hvor infos behandles som fejl. Android- og iOS-builds kører
først `tool/check.sh --static` og stopper, hvis den fejler. Advarsler i Kotlin og Swift er fejl. Se
[`AGENTS.md`](../../AGENTS.md) for reglerne.

### Test

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Integrationstesten kører hele demoforløbet (par, forbind, gennemse, download to optagelser) på en
enhed, emulator eller simulator. Et debug-build kræver ca. 400 MB ledig plads på emulatoren. På
Android henter `flutter test` hverken standard-flavoren eller appens id fra projektet, så den kræver
`--flavor dev` og en APK, der er bygget på forhånd; uden dem stopper den med "No application found".

På iOS-simulatoren skal appen være installeret, når der gives adgang til Fotos, og `flutter test`
afinstallerer den bagefter, hvilket sletter tilladelsen. GR Photo beder om fuld adgang for at kunne
bevare sit album, og på iOS 26.3-simulatoren var `simctl privacy grant photos` alene ikke nok til at
forhindre iOS i at spørge: Den tilladelse, kommandoen registrerer, har `auth_version` 1, og iOS
opfatter den først som fuld adgang ved 2. Giv tilladelsen, og sæt værdien før hver kørsel:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Fejlfindingslog

GR Photo fører fejlfindingslog, mens Indstillinger > Aktiver fejlfindingslog er slået til: alt, hvad
appen sender til og modtager fra kameraet (Bluetooth-scanninger, læsninger, skrivninger og
notifikationer, hver HTTP-forespørgsel og hvert svar, WebSocket-beskeder, størrelsen på live
view-billederne og trinene i oprettelsen af Wi-Fi-forbindelsen), hver linje, appen udskriver,
uopfangede fejl og linjerne fra den native Wi-Fi-kode. Indstillingen er som standard slået til i
`dev` og fra i `prod`. Mens den er slået fra, logges der intet, heller ikke til logcat eller
konsollen, med én undtagelse: Flutter-motoren rapporterer stadig selv uopfangede fejl dér, så nedbrud
forbliver synlige. Indstillinger > Fejlfindingslog eksporterer loggen via delingsarket som JSON
Lines-filer og rydder den. Loggen rummer ca. 50 MB. Den indeholder kameraets Wi-Fi-adgangskode.

### Udgivelser

Hvert push til `main` er en udgivelse, som laves af
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Workflowet giver udgivelsen
nummeret 0.0.N, én højere end den forrige, kører `tool/check.sh` og bygger flavoren `prod` af begge
apps i release-tilstand. Android-APK'en signeres med udgivelsesnøglen til GR Photo og offentliggøres
på [udgivelsessiden](https://github.com/jeph/gr-photo/releases) med sin SHA-256-kontrolsum, en
attestering af buildets oprindelse og den R8-mapping, der gør dens Kotlin-stack traces læselige.
iOS-appen signeres til App Store og uploades til TestFlight. Nøglerne ligger i GitHub-miljøer, som
kun `main` kan bruge, og de job, der bygger de to apps, har ingen af dem.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` kontrollerer, at en APK er
bygget af dette workflow fra dette repository.

```sh
tool/testflight.sh       # bygger prod-appen til iOS og uploader den til TestFlight
```

Scriptet lægger et build, der ikke er en udgivelse, på TestFlight fra en Mac. Det bygger flavoren
`prod` med tidspunktet for uploaden som buildnummer og sender den til App Store Connect, hvor den
dukker op under TestFlight, når den er behandlet. Interne testere installerer den fra
TestFlight-appen, uden kabel. Xcode signerer og uploader buildet med en API-nøgle til App
Store Connect, så opsætningen på en Mac består af nøglens fil `AuthKey_<key id>.p8` i
`~/.appstoreconnect/private_keys` samt `ASC_KEY_ID` og `ASC_ISSUER_ID` i
`~/.appstoreconnect/gr-photo.env`. Nøglen skal have rollen Admin: Apple lader ikke en nøgle med
rollen App Manager bruge teamets distributionscertifikat. Arkivet bygges usigneret og signeres til
App Store ved eksporten (`app/ios/ExportOptions.plist`), fordi signering af selve arkivet ville
kræve en registreret testenhed i teamet.

## Bidrag

Fejlrapporter og pull requests er velkomne. De fleste fejl viser sig kun på rigtig hardware, så når
du [opretter en issue](https://github.com/jeph/gr-photo/issues), må du meget gerne oplyse din
kameramodel og firmwareversion, din telefonmodel og dens Android- eller iOS-version, og hvad du
gjorde. En eksporteret fejlfindingslog (Indstillinger, Fejlfindingslog, Eksporter log) viser som
regel, hvad der skete, men den indeholder dit kameras serienummer og Wi-Fi-adgangskode, så vedhæft
den kun, hvis du er tryg ved at dele dem.

Kør `tool/check.sh`, før du sender en ændring; alle kontroller skal bestås.
[`AGENTS.md`](../../AGENTS.md) beskriver, hvordan koden er organiseret, og hvilke regler den følger.

Rapportér ikke formodede sikkerhedssårbarheder i offentlige issues. Følg
[sikkerhedspolitikken](../../.github/SECURITY.md) for at indsende en privat sårbarhedsrapport.

## Tak

GR Photo er bygget med [Flutter](https://flutter.dev) og bruger
[universal_ble](https://pub.dev/packages/universal_ble) til Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) og
[path_provider](https://pub.dev/packages/path_provider). Teksten er sat med
[Inter](https://rsms.me/inter/) og [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Protokolundersøgelserne bygger på Ricohs apps GR WORLD og Image Sync og på GR-firmwaren samt på
[Ricoh3x](https://github.com/Trimz/Ricoh3x)-projektets noter om indstillingerne for Billedkontrol i
GR IIIx.

## Licens

GR Photo er udgivet under [MIT-licensen](../../LICENSE). Tredjepartspakker og skrifttyper, som
GR Photo indeholder, beholder deres egne licenser. Appen viser dem under **Indstillinger › Om ›
Licenser**, og skrifttypernes licenstekster ligger i [`app/assets/fonts/`](../../app/assets/fonts/).

Demotilstandens eksempelbilleder kommer fra [Unsplash](https://unsplash.com) og bruges under
[Unsplash-licensen](https://unsplash.com/license), ikke MIT-licensen;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) viser dem med deres fotografer.

Ricohs apps og firmware, som undersøgelserne henviser til, tilhører Ricoh og er ikke en del af dette
repository.
