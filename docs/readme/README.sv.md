<p align="center">
  <img src="../icon.png" alt="Ikon för GR Photo" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licens: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Plattformar: iOS och Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <a href="README.da.md">Dansk</a> ·
  <b>Svenska</b> ·
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

**GR Photo** är en följeslagarapp till Ricoh GR-kameror (GR III, GR IIIx och GR IV) för iOS och
Android. Med den bläddrar du bland och hämtar bilderna på kameran, använder telefonen som
fjärrutlösare med livevisning och samlar dina stilar för Bildkontroll på ett ställe. Appen är byggd
för att vara snabb och lätt att använda, och för att hantera kamerans färgprofiler ordentligt: spara
stilen som en bild togs med, redigera den mot en förhandsvisning och lägg in den i kamerans
Egen-platser.

GR Photo är ett fristående projekt och har ingen koppling till Ricoh. Appen kommunicerar med kameran
via ett protokoll som har kartlagts genom reverse engineering av Ricohs egna appar och kamerans
firmware; resultaten finns dokumenterade i [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Bibliotek: kamerans bilder dag för dag, med filter för JPEG, RAW och video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Sidan Stilar: kamerans tre Egen-platser ovanför stilarna som är sparade på telefonen" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Stilredigeraren: en förhandsvisning med före och efter ovanför reglagen för Bildkontroll" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Livevisning: kamerans bild med exponeringsvärden och avtryckaren" height="400">
</p>

<p align="center">
  <sub>Bibliotek, Stilar, stilredigeraren och livevisning, i demoläge med den simulerade kameran.</sub>
</p>

## Innehåll

- [Funktioner](#funktioner)
- [Krav](#krav)
- [Installation](#installation)
- [Användning](#användning)
- [Utveckling](#utveckling)
- [Bidra](#bidra)
- [Tack](#tack)
- [Licens](#licens)

## Funktioner

GR Photo sätter tre saker främst: att du snabbt kommer åt dina bilder, att appen inte är i vägen och
att stilar för Bildkontroll är något värt att hålla ordning på.

- **Snabb.** GR Photo ansluter till kameran via Bluetooth när appen öppnas, om kameran är i
  närheten. När du öppnar Bibliotek väcks kameran, dess Wi-Fi slås på och telefonen ansluter till
  det i ett enda svep. Wi-Fi-anslutningen ligger sedan kvar medan du rör dig mellan sidorna, så
  inget ansluts två gånger och en hämtning fortsätter. Fillistor, miniatyrer och förhandsvisningar
  cachas på telefonen så att Bibliotek öppnas snabbt. Med en GR IV HDF och en Android-telefon tog
  det ungefär 13 sekunder från avstängd kamera till dess Bibliotek.
- **Lätt att använda.** Dina kameror finns på en enda skärm, och Bibliotek, Fota och Stilar är ett
  tryck därifrån. GR Photo slår på kameran, aktiverar dess Wi-Fi och ansluter till det åt dig, så
  efter parkopplingen behöver du inte ställa in något på kameran. När något misslyckas talar appen
  om varför och vad du ska kontrollera, med knappen Försök igen. En anslutning som bryts kommer
  tillbaka av sig själv.
- **Stilar du kan hålla ordning på.** Varje bild i Bibliotek visar vilken Bildkontroll den togs
  med, och med ett tryck sparar du den som en stil. Stilarna ligger på telefonen, oavsett vilken
  kamera de kommer från, med sina inställningar, bilden de kommer från och en etikett för den
  Egen-plats som innehåller dem.
- **En stilredigerare med förhandsvisning.** Ändra basbilden och alla parametrar den har, grupperade
  som Ton, Färg, Detalj och Effekter, och se resultatet på din egen bild eller en exempelbild: dra
  en avdelare mellan före och efter, lägg dem sida vid sida eller tryck för att växla.
  Förhandsvisningen efterliknar kamerans bildbehandling, som har härletts ur dess firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Lägg in stilar i kameran.** Sidan Stilar visar vad kamerans Egen-platser C1 till C3 innehåller.
  Dra en sparad stil till en plats, eller välj Lägg in i dess meny, så har kameran den. Att läsa
  och fylla platserna fungerar med enbart Bluetooth, utan att ansluta till kamerans Wi-Fi.
- **Bibliotek.** Bläddra bland kamerans bilder och videor dag för dag, filtrera på JPEG, RAW, video
  eller ej hämtade, och öppna valfri bild i helskärm med dess detaljer. Hämta en bild eller ett
  urval, som JPEG, RAW eller båda, till ett GR Photo-album i telefonens bildbibliotek. Hämtningar
  fortsätter medan du använder en annan app eller låser telefonen: Android visar dem i en avisering
  med Pausa och Avbryt alla, och iOS 26 eller senare visar förloppet på låsskärmen och i Dynamic
  Island. Videor spelas upp i appen.
- **Fjärrutlösare.** En stor avtryckare med enbart Bluetooth, med självutlösaren,
  exponeringsmetoden, lägesratten, antal bilder kvar och batterinivån. På Android tar även
  volymknapparna bilden.
- **Livevisning.** Kamerans bild via Wi-Fi: tryck för att fokusera, ställ in bländare, slutartid,
  ISO och exponeringskompensation på en ratt med de värden kameran erbjuder, och ändra Exponering,
  Självutlösare, Exponeringsmätning och Bildkontroll.
- **Geotaggning.** GR-kameror har ingen GPS. Med Live-geotaggning på för en kamera skickar GR Photo
  telefonens plats till den via Bluetooth medan kameran är på, och kameran sparar den i varje bild.
  Den startar när du har öppnat GR Photo och fortsätter medan du använder en annan app eller låser
  telefonen. Geotaggning i bakgrunden är alternativet som sköter sig självt: telefonen sparar 90
  dagars historik över var den har varit, och när du hämtar en bild lägger GR Photo till den plats
  som registrerades närmast tidpunkten då bilden togs, i både JPEG- och RAW-filer. Båda är av tills
  du slår på dem för en kamera.
- **Flera kameror.** Parkoppla så många du äger och växla mellan dem; byt namn på eller glöm var
  och en.
- **Teman och språk.** Temana Ljust, Mörkt, Mörkrum, Papper och Cyanotypi, och de 21 språken i
  kamerans egna menyer.
- **Privat.** Inga konton, ingen analys, ingen reklam och ingen kraschrapportering. GR Photo
  kommunicerar bara med din kamera, och din plats skickas bara till din kamera och sparas bara i
  dina egna bilder; se [integritetspolicyn](../../app/assets/privacy.md).

## Krav

- En Ricoh GR III, GR IIIx eller GR IV, inklusive HDF-modellerna och GR IV Monochrome.
- Stilar kräver en GR IV med firmware 1.04 eller senare, en GR IV HDF eller en GR IV Monochrome.
  Firmware för GR III och GR IIIx ger ingen möjlighet att läsa eller skriva inställningar för
  Bildkontroll från en telefon.
- Android 12 eller senare, eller iOS 15 eller senare.

GR Photo är ungt. Hårdvaruloggen innehåller körningar med en GR IV HDF med firmware 1.20:
parkoppling, anslutning, väckning av kameran, bläddring, hämtning, livevisning samt ändringar av
fokus och exponering. Stödet för GR III och GR IIIx bygger på protokollforskningen och har ännu inte
testats på en kamera. Se [`research/hardware-validation.md`](../../research/hardware-validation.md)
för vad som har observerats.

## Installation

På Android laddar du ned `gr-photo-v<version>.apk` från den
[senaste utgåvan](https://github.com/jeph/gr-photo/releases/latest) på telefonen och öppnar filen.
Android ber en gång om tillåtelse att installera appar från din webbläsare. Varje utgåva är signerad
med samma nyckel, så en nyare installeras över den du har och behåller dina kameror och
inställningar.

På iOS går varje utgåva till TestFlight, än så länge bara till projektets egna testare. Det finns
ingen offentlig TestFlight-länk än, så på en iPhone installeras GR Photo genom att byggas från
källkoden.

För att bygga från källkoden behövs [Flutter](https://flutter.dev) 3.47 eller senare med Android SDK
eller Xcode installerat.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` installerar appen på den telefon som är ansluten till datorn. iOS-byggen kräver ett
eget signeringsteam med funktionerna Hotspot Configuration och Access Wi-Fi Information. Ett
Android-bygge från källkoden är signerat med datorns debug-nyckel, inte med releasenyckeln, så
Android installerar inte det ena över det andra: avinstallera först den app du har.

Vill du prova appen utan kamera kör du den i demoläge, som använder en simulerad GR IV med
exempelbilder och fungerar i Android-emulatorn och iOS-simulatorn:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Användning

1. **Parkoppla kameran.** Tryck på Lägg till en kamera och följ guiden. På kameran finns
   parkopplingen under MENU → E6 → Trådlös komm.: välj På under Funktionsläge, öppna Länkning och
   välj Utför länkning, bekräfta sedan koden på telefonen och tryck på OK på kameran. Därefter finns
   kameran på skärmen Kameror, och GR Photo ansluter till den av sig självt när appen öppnas med
   kameran i närheten.
2. **Öppna Bibliotek.** GR Photo slår på kameran om den är av och ansluter till dess Wi-Fi. Android
   ber dig godkänna kamerans nätverk en gång. Tryck på en bild för att visa den, håll intryckt för
   att markera flera och hämta det du vill behålla.
3. **Fota.** Fjärrstyrning är en avtryckare via Bluetooth. Livevisning ansluter till kamerans Wi-Fi
   och visar dess bild, med reglage för fokus och exponering.
4. **Spara en stil.** Öppna en bild i Bibliotek och tryck på Spara stil, eller skapa en från
   grunden med + på sidan Stilar. Tryck på en stil för att redigera den, och dra den till C1, C2
   eller C3 för att lägga in den i kameran.
5. **Lägg till plats.** Slå på Live-geotaggning på kamerans kort, under Bibliotek, Fota och Stilar.
   Telefonen frågar om GR Photo får använda dess plats. Därefter skickas platsen medan GR Photo körs
   och kameran är påslagen och inom räckhåll. Geotaggning i bakgrunden finns under ⋯ på kamerans
   kort och kräver att plats alltid är tillåten.

Med Koppla från automatiskt i Inställningar lämnar GR Photo kamerans Wi-Fi när appen inte har
använts på ett tag (5 minuter som standard). [Så beter sig GR Photo](../behaviour.md) beskriver
varje skärm och varje anslutningstillstånd i detalj.

## Utveckling

### Struktur

| Sökväg | Innehåll |
|---|---|
| `packages/gr_protocol` | BLE GATT, HTTP-API:et över Wi-Fi, WebSocket för ändringar och sessionen för anslutning och återhämtning, i ren Dart |
| `packages/gr_camera` | Kameralagret som appen anropar för allt som rör kameran: adaptrar för Bluetooth och Wi-Fi (med Kotlin- och Swift-koden för Wi-Fi-anslutning), session, parkoppling, sökning, Bibliotek, Fota och livevisning samt spårning av varje utbyte |
| `packages/gr_fake_camera` | Simulerad GR IV (BLE, Wi-Fi-anslutning, HTTP-server på loopback) för tester och demoläge |
| `app` | Flutter-appen, med Kotlin- och Swift-kod för att spara i bildbiblioteket |
| `research` | Protokollforskning: hur varje rutt och karakteristik hittades, belägg från firmware, hårdvaruresultat, öppna frågor |
| `tool` | `check.sh`, alla kodkvalitetskontroller; skripten som bygger, signerar och laddar upp en utgåva; `testflight.sh`, en uppladdning för iOS från en Mac |

### Köra

```sh
cd app
flutter run                                  # dev-bygge, riktig kamera (kräver en telefon med Bluetooth)
flutter run --profile                        # samma sak, med ett release-bygges hastighet
flutter run --flavor prod --release          # bygget som användarna får
flutter run --dart-define=GR_DEMO=true       # simulerad kamera, fungerar i Android-emulatorn och iOS-simulatorn
```

Det finns två byggen. `dev` (`io.jeph.grphoto.dev`, med namnet ”GR Photo Dev”) installeras bredvid
`prod` (`io.jeph.grphoto`, ”GR Photo”). Utan `--flavor` bygger `flutter run` och `flutter build`
`dev`.

Enbart `flutter run` ger ett debug-bygge, som bygger varje bildruta flera gånger långsammare än ett
profile- eller release-bygge (3 till 4 gånger i Bibliotek i en Android-emulator, 2026-11-10). Bedöm
hur mjukt en skärm flyter med `--profile` eller `--release`.

Demoläget har sina data i en separat mapp, `demo/`. Vid första starten hittar Lägg till en kamera
den simulerade kameran, och den bekräftar parkopplingen själv; senare starter börjar med kameran
avstängd, och den förblir av tills du öppnar Bibliotek (att väcka den ingår i att ansluta till dess
Wi-Fi) eller trycker på kortets strömknapp. RAW-filerna i demoläget är JPEG-byte med ett
`.DNG`-namn.

### Kontroller

```sh
tool/check.sh            # formaterare, analysator, kameralagrets gräns, översättningar, alla testsviter
tool/check.sh --static   # utan testerna
```

Analysatorn använder `very_good_analysis` där även info-meddelanden behandlas som fel. Byggen för
Android och iOS kör först `tool/check.sh --static` och avbryts om den misslyckas. Varningar i Kotlin
och Swift är fel. Reglerna finns i [`AGENTS.md`](../../AGENTS.md).

### Tester

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Integrationstestet kör hela demoflödet (parkoppla, ansluta, bläddra, hämta två bilder) på en enhet,
emulator eller simulator. Ett debug-bygge kräver ungefär 400 MB ledigt utrymme i emulatorn. På
Android hämtar `flutter test` varken standard-flavor eller appens ID från projektet, så kommandot
behöver `--flavor dev` och en APK som har byggts i förväg; utan dem avbryts det med ”No application
found”.

I iOS-simulatorn måste appen vara installerad när åtkomst till Bilder beviljas, och `flutter test`
avinstallerar den efteråt, vilket tar bort behörigheten. GR Photo ber om full åtkomst, för att kunna
behålla sitt album, och i simulatorn för iOS 26.3 räckte inte `simctl privacy grant photos` för att
iOS skulle sluta fråga: behörigheten som registreras har `auth_version` 1, och iOS räknar den som
full åtkomst först vid 2. Bevilja den och ställ in det värdet före varje körning:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Felsökningslogg

GR Photo för felsökningsloggar så länge Inställningar > Aktivera felsökningslogg är på: allt som
appen skickar till och tar emot från kameran (Bluetooth-sökningar, läsningar, skrivningar och
notifieringar, varje HTTP-förfrågan och svar, WebSocket-meddelanden, bildrutornas storlek i
livevisningen och stegen i Wi-Fi-anslutningen), varje rad som appen skriver ut, ohanterade fel och
raderna från den inbyggda Wi-Fi-koden. Inställningen är på som standard i `dev` och av i `prod`.
När den är av loggas ingenting, inte ens till logcat eller konsolen, med ett undantag:
Flutter-motorn rapporterar fortfarande själv ohanterade fel där, så krascher syns ändå.
Inställningar > Felsökningslogg exporterar loggen via delningsbladet som JSON Lines-filer och rensar
den. Loggen rymmer ungefär 50 MB. Den innehåller kamerans Wi-Fi-lösenord.

### Utgåvor

Varje push till `main` är en utgåva, som görs av
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Arbetsflödet ger utgåvan
numret 0.0.N, ett högre än den förra, kör `tool/check.sh` och bygger flavor `prod` av båda apparna i
release-läge. Android-APK:n signeras med releasenyckeln för GR Photo och publiceras på
[sidan med utgåvor](https://github.com/jeph/gr-photo/releases) med sin SHA-256-kontrollsumma, ett
intyg om byggets ursprung och den R8-mappning som gör dess stackspår i Kotlin läsbara. iOS-appen
signeras för App Store och laddas upp till TestFlight. Nycklarna förvaras i GitHub-miljöer som bara
`main` kan använda, och jobben som bygger apparna har ingen av dem.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` kontrollerar att en APK har
byggts av det arbetsflödet från det här repot.

```sh
tool/testflight.sh       # bygger iOS-appen i prod-utförande och laddar upp den till TestFlight
```

Skriptet lägger upp ett bygge som inte är en utgåva på TestFlight från en Mac. Det bygger flavor
`prod` med uppladdningens tidpunkt som byggnummer och skickar bygget till App Store Connect, där det
visas under TestFlight när det har bearbetats. Interna testare installerar det från
TestFlight-appen, utan kabel. Xcode signerar och laddar upp bygget med en API-nyckel för
App Store Connect, så det som behövs på en Mac är nyckelns fil `AuthKey_<key id>.p8` i
`~/.appstoreconnect/private_keys` samt `ASC_KEY_ID` och `ASC_ISSUER_ID` i
`~/.appstoreconnect/gr-photo.env`. Nyckeln måste ha rollen Admin: Apple låter inte en nyckel med
rollen App Manager använda teamets distributionscertifikat. Arkivet byggs osignerat och signeras
för App Store vid exporten (`app/ios/ExportOptions.plist`), eftersom en signering av själva arkivet
skulle kräva en registrerad testenhet i teamet.

## Bidra

Felrapporter och pull requests är välkomna. De flesta fel visar sig bara på riktig hårdvara, så när
du [öppnar ett ärende](https://github.com/jeph/gr-photo/issues) får du gärna ange kameramodell och
firmwareversion, telefonmodell och dess Android- eller iOS-version samt vad du gjorde. En exporterad
felsökningslogg (Inställningar, Felsökningslogg, Exportera loggen) visar oftast vad som hände, men
den innehåller kamerans serienummer och Wi-Fi-lösenord, så bifoga den bara om du är bekväm med att
dela dem.

Kör `tool/check.sh` innan du skickar in en ändring; alla kontroller måste gå igenom.
[`AGENTS.md`](../../AGENTS.md) beskriver hur koden är organiserad och vilka regler den följer.

Rapportera inte misstänkta säkerhetsluckor i offentliga ärenden. Följ
[säkerhetspolicyn](../../.github/SECURITY.md) för att skicka in en privat sårbarhetsrapport.

## Tack

GR Photo är byggt med [Flutter](https://flutter.dev) och använder
[universal_ble](https://pub.dev/packages/universal_ble) för Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) och
[path_provider](https://pub.dev/packages/path_provider). Texten är satt i
[Inter](https://rsms.me/inter/) och [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Protokollforskningen vilar på Ricohs appar GR WORLD och Image Sync och på GR-kamerornas firmware,
samt på anteckningarna i projektet [Ricoh3x](https://github.com/Trimz/Ricoh3x) om inställningarna
för Bildkontroll i GR IIIx.

## Licens

GR Photo ges ut under [MIT-licensen](../../LICENSE). Tredjepartspaket och typsnitt som ingår i
GR Photo behåller sina egna licenser. Appen listar dem under **Inställningar › Om › Licenser**, och
typsnittens licenstexter finns i [`app/assets/fonts/`](../../app/assets/fonts/).

Demolägets exempelbilder kommer från [Unsplash](https://unsplash.com) och används under
[Unsplash-licensen](https://unsplash.com/license), inte MIT-licensen;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) listar dem med deras fotografer.

Ricohs appar och firmware, som forskningen hänvisar till, tillhör Ricoh och ingår inte i det här
repot.
