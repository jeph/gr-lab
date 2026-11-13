<p align="center">
  <img src="../icon.png" alt="A GR Photo ikonja" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licenc: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platformok: iOS és Android">
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
  <a href="README.sv.md">Svenska</a> ·
  <a href="README.fi.md">Suomi</a> ·
  <a href="README.pl.md">Polski</a> ·
  <a href="README.cs.md">Čeština</a> ·
  <b>Magyar</b> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.el.md">Ελληνικά</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.th.md">ไทย</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.zh.md">中文简体</a> ·
  <a href="README.zh-Hant.md">中文繁體</a> ·
  <a href="README.ja.md">日本語</a>
</p>

A **GR Photo** a Ricoh GR kamerák (GR III, GR IIIx és GR IV) társalkalmazása iOS és Android
rendszerre. Böngészheti és letöltheti vele a kamerán lévő fotókat, élőképes távkioldóként
használhatja, és egy helyen tarthatja benne a Képvezérlés stílusait. Úgy készült, hogy gyors és
könnyen kezelhető legyen, és rendesen kezelje a kamera színprofiljait: elmentheti azt a stílust,
amellyel egy fotó készült, előnézet mellett szerkesztheti, és betöltheti a kamera egyéni helyeire.

A GR Photo független projekt, nem áll kapcsolatban a Ricoh vállalattal. A kamerával olyan
protokollon kommunikál, amelyet a Ricoh saját alkalmazásaiból és a kamera firmware-éből fejtettünk
vissza; az eredmények leírása a [`research/`](../../research/README.md) mappában található.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="A Könyvtár: a kamera fotói napok szerint, JPEG-, RAW- és videószűrőkkel" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="A Stílusok oldal: a kamera három egyéni helye a telefonra mentett stílusok fölött" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="A stílusszerkesztő: előtte-utána előnézet a Képvezérlés csúszkái fölött" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Élőkép: a kamera képe az expozíciós értékekkel és a zárkioldóval" height="400">
</p>

<p align="center">
  <sub>A Könyvtár, a Stílusok, a stílusszerkesztő és az élőkép demó módban, a szimulált kamerával.</sub>
</p>

## Tartalom

- [Funkciók](#funkciók)
- [Követelmények](#követelmények)
- [Telepítés](#telepítés)
- [Használat](#használat)
- [Fejlesztés](#fejlesztés)
- [Közreműködés](#közreműködés)
- [Köszönetnyilvánítás](#köszönetnyilvánítás)
- [Licenc](#licenc)

## Funkciók

A GR Photo számára három dolog a legfontosabb: hogy gyorsan eljusson a fotóihoz, hogy az alkalmazás
ne legyen útban, és hogy a Képvezérlés stílusait érdemes legyen benne kezelni.

- **Gyors.** A GR Photo megnyitáskor Bluetooth-kapcsolaton csatlakozik a kamerához, ha az a közelben
  van. A Könyvtár megnyitása egyetlen lépésben felébreszti a kamerát, bekapcsolja a Wi-Fi-jét és
  csatlakozik hozzá, a Wi-Fi-kapcsolat pedig megmarad, amíg Ön az oldalak között vált, így semmi sem
  csatlakozik kétszer, és a letöltés nem szakad meg. A fájllistákat, a bélyegképeket és az
  előnézeteket az alkalmazás a telefonon gyorsítótárazza, ezért a Könyvtár gyorsan megnyílik. Egy
  GR IV HDF és egy androidos telefon esetében a kikapcsolt kamera Könyvtára körülbelül
  13 másodperc alatt jelent meg.
- **Könnyen kezelhető.** A kamerái egyetlen képernyőn láthatók, ahonnan a Könyvtár, a Fotózás és a
  Stílusok egy koppintással elérhető. A GR Photo bekapcsolja a kamerát, bekapcsolja a Wi-Fi-jét, és
  csatlakozik hozzá Ön helyett, így a párosítás után semmit sem kell beállítani a kamerán. Ha
  valami nem sikerül, megmondja, miért, és mit érdemes ellenőrizni, és felkínálja a Próbálja újra
  gombot. A megszakadt kapcsolat magától helyreáll.
- **Kezelhető stílusok.** A Könyvtár minden fotójánál látható, milyen Képvezérlés-beállítással
  készült, és ez egyetlen koppintással stílusként menthető. A stílusok a telefonján vannak,
  bármelyik kameráról származnak is, a beállításaikkal, a forrásul szolgáló fotóval és az őket
  tartalmazó egyéni hely címkéjével együtt.
- **Stílusszerkesztő előnézettel.** Módosíthatja az alapképet és annak minden paraméterét, Tónus,
  Szín, Részletek és Effektusok csoportokba rendezve, az eredményt pedig a saját fotóján vagy egy
  mintafotón láthatja: húzzon elválasztót az előtte és az utána állapot között, tegye őket egymás
  mellé, vagy koppintással váltson közöttük. Az előnézet a kamera képfeldolgozását közelíti, amelyet
  a firmware-éből vezettünk le
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Stílusok betöltése a kamerába.** A Stílusok oldal megmutatja, mit tartalmaznak a kamera C1–C3
  egyéni helyei. Húzzon egy mentett stílust egy helyre, vagy válassza a menüjéből a Betöltés
  parancsot, és a stílus már a kamerán is van. A helyek beolvasása és a betöltés kizárólag
  Bluetooth-kapcsolaton működik, a kamera Wi-Fi-hálózatához nem kell csatlakozni.
- **Könyvtár.** Böngészheti a kamera fotóit és videóit napok szerint, szűrhet a JPEG, a RAW, a Videó
  és a Nincs letöltve szűrővel, és bármelyik felvételt megnyithatja teljes képernyőn, a részleteivel
  együtt. Letölthet egyetlen felvételt vagy egy kijelölést, JPEG-ként, RAW-ként vagy mindkettőként,
  a telefon fotókönyvtárának GR Photo albumába. A letöltések akkor is folytatódnak, ha másik
  alkalmazást használ vagy lezárja a telefont: az Android értesítésben mutatja őket Szüneteltetés és
  Összes megszakítása gombbal, az iOS 26 vagy újabb pedig a zárolási képernyőn és a Dynamic Islanden
  mutatja az állapotukat. A videók az alkalmazásban játszhatók le.
- **Távkioldó.** Nagy zárkioldó gomb, kizárólag Bluetooth-kapcsolaton, az önkioldóval, a meghajtási
  móddal, a módválasztó tárcsa állásával, a hátralévő képek számával és az akkumulátor
  töltöttségével. Androidon a hangerőgombok is exponálnak.
- **Élőkép.** A kamera képe Wi-Fi-kapcsolaton: koppintson a fókuszáláshoz, állítsa be a rekeszt, a
  záridőt, az ISO-értéket és az expozíciókompenzációt egy tárcsán, amely a kamera által kínált
  értékeket mutatja, és módosítsa a meghajtást, az önkioldót, a fénymérést és a Képvezérlést.
- **Geocímkézés.** A GR kamerákban nincs GPS. Ha egy kameránál be van kapcsolva az Élő geocímkézés,
  a GR Photo Bluetooth-kapcsolaton elküldi neki a telefonja helyzetét, amíg a kamera be van
  kapcsolva, a kamera pedig minden fotóba elmenti. A GR Photo megnyitása után indul el, és akkor is
  folytatódik, ha másik alkalmazást használ vagy zárolja a telefont. A Háttérbeli geocímkézés a
  beavatkozást nem igénylő alternatíva: a telefon 90 napos előzményeket vezet arról, hol járt, és a
  GR Photo a fotó letöltésekor azt a helyet adja hozzá, amelyet a telefon a készítés időpontjához
  legközelebb rögzített, JPEG- és RAW-fájlokhoz egyaránt. Mindkettő ki van kapcsolva, amíg be nem
  kapcsolja egy kameránál.
- **Több kamera.** Annyi kamerát párosíthat, ahány van, és válthat közöttük; mindegyiket
  átnevezheti vagy elfelejtetheti.
- **Témák és nyelvek.** Világos, Sötét, Sötétkamra, Papír és Cianotípia téma, valamint a kamera
  saját menüinek 21 nyelve.
- **Bizalmas.** Nincs fiók, analitika, hirdetés vagy összeomlás-jelentés. A GR Photo kizárólag az Ön
  kamerájával kommunikál, valamint a fotó készítési helyének térképéhez az OpenFreeMap
  szolgáltatással; lásd az [adatvédelmi irányelveket](../../app/assets/privacy.md).

## Követelmények

- Ricoh GR III, GR IIIx vagy GR IV, beleértve a HDF változatokat és a GR IV Monochrome modellt.
- A stílusokhoz GR IV (1.04-es vagy újabb firmware-rel), GR IV HDF vagy GR IV Monochrome
  szükséges. A GR III és a GR IIIx firmware-e nem ad lehetőséget a Képvezérlés beállításainak
  telefonról történő olvasására vagy írására.
- Android 12 vagy újabb, illetve iOS 15.5 vagy újabb.

A GR Photo fiatal projekt. A hardvernapló 1.20-s firmware-rel futó GR IV HDF kamerával végzett
próbákat rögzít: párosítás, csatlakozás, a kamera felébresztése, böngészés, letöltés, élőkép, a
fókusz és az expozíció módosítása. A GR III és a GR IIIx támogatása a protokollkutatásból
származik, kamerán még nem teszteltük. A megfigyelt eredményeket lásd itt:
[`research/hardware-validation.md`](../../research/hardware-validation.md).

## Telepítés

Androidon töltse le a telefonjára a `gr-photo-v<version>.apk` fájlt a
[legújabb kiadásból](https://github.com/jeph/gr-photo/releases/latest), és nyissa meg. Az Android
egyszer engedélyt kér ahhoz, hogy a böngészőjéből alkalmazásokat telepíthessen. Minden kiadás
ugyanazzal a kulccsal van aláírva, így az újabb a meglévőre települ, és megőrzi a kameráit és a
beállításait.

iOS-en minden kiadás a TestFlightra kerül, egyelőre csak a projekt saját tesztelőihez. Nyilvános
TestFlight-hivatkozás még nincs, ezért iPhone-on a GR Photo úgy telepíthető, hogy a forráskódból
lefordítja.

A forráskódból történő fordításhoz [Flutter](https://flutter.dev) 3.47 vagy újabb szükséges,
beállított Android SDK-val vagy Xcode-dal.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

A `flutter run` a számítógéphez csatlakoztatott telefonra telepít. Az iOS-buildekhez saját aláíró
csapatra van szükség, a Hotspot Configuration és az Access Wi-Fi Information képességgel. A
forráskódból készült Android-buildet a számítógépe hibakeresési kulcsa írja alá, nem a kiadási
kulcs, ezért az Android egyiket sem telepíti a másikra: előbb távolítsa el a meglévőt.

Ha kamera nélkül szeretné kipróbálni az alkalmazást, futtassa demó módban, amely mintafotókkal
ellátott, szimulált GR IV kamerát használ, és az Android-emulátoron és az iOS-szimulátoron is
működik:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Használat

1. **Párosítsa a kameráját.** Koppintson a Kamera hozzáadása gombra, és kövesse az útmutatót. A
   kamerán a párosítás itt található: MENU → E6 → Vez. nélk. kom. Állítsa a Működési mód beállítást
   Be értékre, nyissa meg a Párosítás menüpontot, és válassza a Párosítás végrehajtása lehetőséget,
   majd erősítse meg a kódot a telefonon, és nyomja meg a kamerán az OK gombot. A kamera ezután
   megjelenik a Kamerák képernyőn, és a GR Photo magától csatlakozik hozzá, ha megnyitáskor a kamera
   a közelben van.
2. **Nyissa meg a Könyvtárat.** A GR Photo bekapcsolja a kamerát, ha ki van kapcsolva, és
   csatlakozik a Wi-Fi-hálózatához. Az Android egyszer a jóváhagyását kéri a kamera hálózatához.
   Koppintson egy felvételre a megtekintéséhez, tartsa nyomva több felvétel kijelöléséhez, és töltse
   le, amit meg szeretne tartani.
3. **Fotózzon.** A Távkioldó Bluetooth-kapcsolaton működő zárkioldó. Az Élőkép csatlakozik a kamera
   Wi-Fi-hálózatához, és megjeleníti a kamera képét, fókusz- és expozícióvezérlőkkel.
4. **Mentsen egy stílust.** Nyisson meg egy fotót a Könyvtárban, és koppintson a Stílus mentése
   gombra, vagy készítsen egyet a nulláról a Stílusok oldal + gombjával. Koppintson egy stílusra a
   szerkesztéséhez, és húzza a C1, C2 vagy C3 helyre, ha be szeretné tölteni a kamerába.
5. **Adjon hozzá helyadatokat.** Kapcsolja be az Élő geocímkézést a kamera kártyáján, a Könyvtár, a
   Fotózás és a Stílusok gomb alatt. A telefon megkérdezi, hogy a GR Photo használhatja-e a
   helyzetét. Ettől kezdve a GR Photo akkor küldi el a helyzetet, amikor fut, a kamera pedig be van
   kapcsolva és a közelben van. A Háttérbeli geocímkézés a kamera kártyáján lévő ⋯ gomb alatt
   található, és ehhez mindig engedélyezni kell a helyhozzáférést.

A Beállítások Automatikus leválasztás funkciója kilép a kamera Wi-Fi-hálózatából, ha a GR Photo egy
ideje nincs használatban (alapértelmezés szerint 5 perc után). [A GR Photo
működése](../behaviour.md) részletesen leírja az egyes képernyőket és minden kapcsolati állapotot.

## Fejlesztés

### Felépítés

| Útvonal | Tartalom |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi HTTP API, változásjelző WebSocket és a csatlakozást, illetve helyreállítást végző munkamenet, tiszta Dart nyelven |
| `packages/gr_camera` | A kameraréteg, amelyet az alkalmazás minden kamerával kapcsolatos művelethez hív: Bluetooth- és Wi-Fi-adapterek (a Wi-Fi-csatlakozás Kotlin- és Swift-kódjával), munkamenet, párosítás, keresés, Könyvtár, Fotózás és élőkép, valamint minden adatcsere nyomkövetése |
| `packages/gr_fake_camera` | Szimulált GR IV (BLE, Wi-Fi-csatlakozás, HTTP-kiszolgáló a loopback interfészen) a tesztekhez és a demó módhoz |
| `app` | A Flutter-alkalmazás, a fotókönyvtárba mentést végző Kotlin- és Swift-kóddal |
| `research` | Protokollkutatás: hogyan találtuk meg az egyes útvonalakat és karakterisztikákat, firmware-bizonyítékok, hardveres eredmények, nyitott kérdések |
| `tool` | `check.sh`, az összes kódminőségi ellenőrzés; a kiadást lefordító, aláíró és feltöltő szkriptek; `testflight.sh`, iOS-feltöltés Macről |

### Futtatás

```sh
cd app
flutter run                                  # dev build, valódi kamera (Bluetooth-képes telefon kell hozzá)
flutter run --profile                        # ugyanez, a kiadási build sebességével
flutter run --flavor prod --release          # a felhasználóknak szánt build
flutter run --dart-define=GR_DEMO=true       # szimulált kamera, Android-emulátoron és iOS-szimulátoron is működik
```

Két build létezik. A `dev` (`io.jeph.grphoto.dev`, a neve „GR Photo Dev”) a `prod`
(`io.jeph.grphoto`, „GR Photo”) mellé települ. `--flavor` nélkül a `flutter run` és a `flutter
build` a `dev` változatot fordítja.

A `flutter run` önmagában hibakeresési buildet készít, amely az egyes képkockákat többször
lassabban állítja elő, mint a profil- vagy a kiadási build (a Könyvtárban, Android-emulátoron
3–4-szer lassabban, 2026-11-10). Azt, hogy egy képernyő mennyire gördülékeny, a `--profile` vagy a
`--release` kapcsolóval ítélje meg.

A demó mód külön `demo/` mappában tartja az adatait. Az első indításkor a Kamera hozzáadása
megtalálja a szimulált kamerát, amely magától megerősíti a párosítást; a későbbi indítások
kikapcsolt kamerával kezdődnek, és az kikapcsolva is marad, amíg meg nem nyitja a Könyvtárat (a
felébresztése a Wi-Fi-csatlakozás része), vagy meg nem nyomja a kártya bekapcsológombját. A demó
RAW-fájlok `.DNG` nevű JPEG-bájtok.

### Ellenőrzések

```sh
tool/check.sh            # formázó, elemző, a kameraréteg határa, fordítások, az összes tesztkészlet
tool/check.sh --static   # a tesztek nélkül
```

Az elemző a `very_good_analysis` csomagot használja, az info szintű jelzéseket hibaként kezelve. Az
Android- és iOS-buildek először a `tool/check.sh --static` parancsot futtatják, és leállnak, ha az
hibát jelez. A Kotlin- és Swift-figyelmeztetések hibának számítanak. A szabályokat lásd itt:
[`AGENTS.md`](../../AGENTS.md).

### Tesztek

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Az integrációs teszt a teljes demófolyamatot (párosítás, csatlakozás, böngészés, két felvétel
letöltése) végigfuttatja egy eszközön, emulátoron vagy szimulátoron. A hibakeresési buildnek
körülbelül 400 MB szabad helyre van szüksége az emulátoron. Androidon a `flutter test` sem az
alapértelmezett flavort, sem az alkalmazás azonosítóját nem veszi át a projektből, ezért szükség
van a `--flavor dev` kapcsolóra és egy előre lefordított APK-ra; ezek nélkül a „No application
found” üzenettel leáll.

Az iOS-szimulátoron az alkalmazásnak telepítve kell lennie, amikor megkapja a Fotók-hozzáférést, a
`flutter test` pedig utána eltávolítja, ami az engedélyt is törli. A GR Photo teljes hozzáférést
kér, hogy megtarthassa az albumát, és az iOS 26.3-as szimulátoron a `simctl privacy grant photos`
önmagában nem akadályozta meg, hogy az iOS rákérdezzen: az általa rögzített engedélyben az
`auth_version` értéke 1, az iOS pedig csak 2-es értéknél tekinti teljes hozzáférésnek. Minden
futtatás előtt adja meg az engedélyt, és állítsa be ezt az értéket:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Hibakeresési napló

A GR Photo hibakeresési naplót vezet, amíg a Beállítások > Hibakeresési naplózás bekapcsolása
beállítás be van kapcsolva: mindent, amit a kamerának küld és tőle fogad (Bluetooth-keresések,
olvasások, írások és értesítések, minden HTTP-kérés és -válasz, WebSocket-üzenetek, az élőkép
képkockáinak mérete és a Wi-Fi-csatlakozás lépései), az alkalmazás által kiírt minden sort, a
kezeletlen hibákat és a natív Wi-Fi-kód sorait. A beállítás a `dev` buildben alapértelmezés szerint
be, a `prod` buildben ki van kapcsolva. Amíg ki van kapcsolva, semmi sem kerül naplóba, még a
logcatbe vagy a konzolra sem, egyetlen kivétellel: a kezeletlen hibákat a Flutter-motor továbbra is
maga jelenti ott, így az összeomlások láthatók maradnak. A Beállítások > Hibakeresési napló a
megosztási lapon keresztül JSON Lines fájlokként exportálja a naplót, majd törli. A napló
körülbelül 50 MB-ot őriz meg. Tartalmazza a kamera Wi-Fi-jelszavát.

### Kiadások

A `main` ágra érkező minden push egy kiadás, amelyet a
[`.github/workflows/release.yml`](../../.github/workflows/release.yml) készít el. A munkafolyamat a
kiadásnak a 0.0.N számot adja, eggyel nagyobbat az előzőnél, lefuttatja a `tool/check.sh` szkriptet,
és mindkét alkalmazás `prod` flavorját kiadási módban fordítja le. Az Android APK-t a GR Photo
kiadási kulcsa írja alá, és a [kiadások oldalán](https://github.com/jeph/gr-photo/releases) jelenik
meg, az SHA-256 ellenőrzőösszegével, a build eredetét igazoló tanúsítással és azzal az
R8-leképezéssel együtt, amellyel a Kotlin-veremkiírásai olvashatók. Az iOS-alkalmazás az App Store
számára van aláírva, és a TestFlightra kerül feltöltésre. A kulcsok olyan GitHub-környezetekben
vannak, amelyeket csak a `main` használhat, és az alkalmazásokat fordító feladatok egyiket sem
kapják meg.

A `gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` azt ellenőrzi, hogy egy APK-t
ez a munkafolyamat fordított-e le ebből a tárolóból.

```sh
tool/testflight.sh       # lefordítja a prod iOS-alkalmazást, és feltölti a TestFlightra
```

A szkript olyan buildet tesz fel Macről a TestFlightra, amely nem kiadás. A `prod` flavort fordítja
le, buildszámként a feltöltés időpontját használva, és elküldi az App Store Connectnek, ahol a
feldolgozás után megjelenik a TestFlight alatt. A belső tesztelők a TestFlight alkalmazásból
telepítik, kábel nélkül. Az Xcode egy App Store Connect API-kulccsal írja
alá és tölti fel a buildet, így a Macen a beállítás a kulcs `AuthKey_<key id>.p8` fájljából áll a
`~/.appstoreconnect/private_keys` mappában, valamint az `ASC_KEY_ID` és az `ASC_ISSUER_ID`
értékéből a `~/.appstoreconnect/gr-photo.env` fájlban. A kulcsnak Admin szerepkörre van szüksége: az
Apple nem engedi, hogy egy App Manager szerepkörű kulcs a csapat terjesztési tanúsítványát
használja. Az archívum aláírás nélkül készül, és exportáláskor kap App Store-aláírást
(`app/ios/ExportOptions.plist`), mert magának az archívumnak az aláírásához regisztrált
teszteszközre volna szükség a csapatban.

## Közreműködés

A hibajelentéseket és a pull requesteket szívesen fogadjuk. A legtöbb hiba csak valódi hardveren
jelentkezik, ezért amikor [hibajegyet nyit](https://github.com/jeph/gr-photo/issues), kérjük, adja
meg a kamera típusát és firmware-verzióját, a telefon típusát és Android- vagy iOS-verzióját,
valamint azt, hogy mit csinált. Egy exportált hibakeresési napló (Beállítások, Hibakeresési napló,
Napló exportálása) általában megmutatja, mi történt, de tartalmazza a kamera gyári számát és
Wi-Fi-jelszavát, ezért csak akkor csatolja, ha ezeket nyugodt szívvel megosztja.

Mielőtt módosítást küld be, futtassa a `tool/check.sh` szkriptet; minden ellenőrzésnek sikeresnek
kell lennie. Az [`AGENTS.md`](../../AGENTS.md) leírja, hogyan épül fel a kód, és milyen szabályokat
követ.

A feltételezett biztonsági réseket ne nyilvános hibajegyben jelentse. Kövesse a
[biztonsági szabályzatot](../../.github/SECURITY.md), és küldjön privát sebezhetőségi jelentést.

## Köszönetnyilvánítás

A GR Photo [Flutter](https://flutter.dev) keretrendszerrel készült, a Bluetooth-kapcsolathoz a
[universal_ble](https://pub.dev/packages/universal_ble) csomagot használja, emellett az
[image](https://pub.dev/packages/image), a [video_player](https://pub.dev/packages/video_player),
a [share_plus](https://pub.dev/packages/share_plus) és a
[path_provider](https://pub.dev/packages/path_provider) csomagot. A szövege
[Inter](https://rsms.me/inter/) és [JetBrains Mono](https://www.jetbrains.com/lp/mono/) betűtípussal
jelenik meg.

A protokollkutatás a Ricoh GR WORLD és Image Sync alkalmazására, a GR firmware-re, valamint a
[Ricoh3x](https://github.com/Trimz/Ricoh3x) projektnek a GR IIIx Képvezérlés-beállításairól szóló
jegyzeteire támaszkodik.

## Licenc

A GR Photo az [MIT-licenc](../../LICENSE) alatt jelenik meg. A GR Photo által tartalmazott, harmadik
féltől származó csomagokra és betűtípusokra a saját licencük vonatkozik. Az alkalmazás ezeket a
**Beállítások › Névjegy › Licencek** alatt sorolja fel, a betűtípusok licencszövegei pedig az
[`app/assets/fonts/`](../../app/assets/fonts/) mappában találhatók.

A demó mód mintafotói az [Unsplash](https://unsplash.com) oldalról származnak, és nem az
MIT-licenc, hanem az
[Unsplash-licenc](https://unsplash.com/license) vonatkozik rájuk; az
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) fájl sorolja fel őket
a fotósaikkal együtt.

A Ricoh alkalmazásai és firmware-e, amelyekre a kutatás hivatkozik, a Ricoh tulajdonát képezik, és
nem részei ennek a tárolónak.
