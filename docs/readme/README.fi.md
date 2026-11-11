<p align="center">
  <img src="../icon.png" alt="GR Labin kuvake" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Lisenssi: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Alustat: iOS ja Android">
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
  <b>Suomi</b> ·
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

**GR Lab** on Ricoh GR ‑kameroiden (GR III, GR IIIx ja GR IV) kumppanisovellus iOS:lle ja
Androidille. Sillä selaat ja lataat kamerassa olevia kuvia, käytät puhelinta kaukolaukaisimena
live-kuvan kera ja pidät Kuvansäätö-tyylisi yhdessä paikassa. Sovellus on tehty nopeaksi ja
helppokäyttöiseksi, ja se hallitsee kameran väriprofiileja kunnolla: tallenna tyyli, jolla kuva
otettiin, muokkaa sitä esikatselun avulla ja siirrä se kameran Mukautettu-paikkoihin.

GR Lab on itsenäinen projekti, eikä sillä ole yhteyttä Ricohiin. Se viestii kameran kanssa
protokollalla, joka on selvitetty takaisinmallintamalla Ricohin omia sovelluksia ja kameran
laiteohjelmistoa; havainnot on kirjattu kansioon [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Kirjasto: kameran kuvat päivittäin ryhmiteltyinä sekä suodattimet JPEG-kuville, RAW-kuville ja videoille" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Tyylit-sivu: kameran kolme Mukautettu-paikkaa puhelimeen tallennettujen tyylien yläpuolella" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Tyylieditori: ennen ja jälkeen ‑esikatselu Kuvansäätö-liukusäätimien yläpuolella" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Live-kuva: kameran kuva, valotuslukemat ja laukaisin" height="400">
</p>

<p align="center">
  <sub>Kirjasto, Tyylit, tyylieditori ja live-kuva esittelytilassa simuloidun kameran kanssa.</sub>
</p>

## Sisällys

- [Ominaisuudet](#ominaisuudet)
- [Vaatimukset](#vaatimukset)
- [Asennus](#asennus)
- [Käyttö](#käyttö)
- [Kehitys](#kehitys)
- [Osallistuminen](#osallistuminen)
- [Kiitokset](#kiitokset)
- [Lisenssi](#lisenssi)

## Ominaisuudet

GR Labissa kolme asiaa on etusijalla: kuviin pääsee käsiksi nopeasti, sovellus pysyy poissa
tieltäsi, ja Kuvansäätö-tyylejä kohdellaan asiana, jota kannattaa hallita.

- **Nopea.** GR Lab yhdistää kameraan Bluetoothilla heti avautuessaan, jos kamera on lähellä.
  Kirjaston avaaminen herättää kameran, kytkee sen Wi-Fin päälle ja liittyy siihen yhdellä kertaa,
  ja Wi-Fi pysyy sen jälkeen päällä, kun siirryt sivulta toiselle, joten mihinkään ei liitytä
  kahdesti ja lataus jatkuu keskeytyksettä. Tiedostoluettelot, pienoiskuvat ja esikatselukuvat
  tallennetaan puhelimen välimuistiin, joten Kirjasto avautuu nopeasti. GR IV HDF ‑kameralla ja
  Android-puhelimella sammutetusta kamerasta päästiin Kirjastoon noin 13 sekunnissa.
- **Helppokäyttöinen.** Kamerasi ovat yhdellä näytöllä, ja Kirjasto, Kuvaus ja Tyylit ovat siltä
  yhden napautuksen päässä. GR Lab käynnistää kameran, kytkee sen Wi-Fin päälle ja liittyy siihen
  puolestasi, joten kamerasta ei tarvitse säätää mitään parinmuodostuksen jälkeen. Kun jokin
  epäonnistuu, sovellus kertoo syyn ja sen, mitä kannattaa tarkistaa, ja tarjoaa painikkeen Yritä
  uudelleen. Katkennut yhteys palautuu itsestään.
- **Tyylit, joita voi hallita.** Jokaisen Kirjaston kuvan kohdalla näkyy Kuvansäätö, jolla se
  otettiin, ja yksi napautus tallentaa sen tyyliksi. Tyylit säilyvät puhelimessasi riippumatta
  siitä, mistä kamerasta ne ovat peräisin, ja niiden mukana säilyvät asetukset, lähdekuva ja
  merkintä siitä, missä Mukautettu-paikassa tyyli on.
- **Tyylieditori esikatselulla.** Vaihda pohjana olevaa Kuvansäätöä ja muuta sen jokaista
  parametria, jotka on ryhmitelty otsikoiden Valo, Väri, Piirto ja Tehosteet alle, ja katso tulos
  omasta kuvastasi tai esimerkkikuvasta: liu'uta jakajaa ennen- ja jälkeen-kuvan yli, aseta ne
  rinnakkain tai vaihda niiden välillä napauttamalla. Esikatselu jäljittelee kameran
  kuvankäsittelyä, joka on selvitetty sen laiteohjelmistosta
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Siirrä tyylejä kameraan.** Tyylit-sivu näyttää, mitä kameran Mukautettu-paikoissa C1–C3 on.
  Vedä tallennettu tyyli paikan päälle tai valitse sen valikosta Siirrä paikkaan C1, C2 tai C3,
  niin tyyli on kamerassa. Paikkojen lukeminen ja tyylien siirtäminen onnistuu pelkällä
  Bluetoothilla, liittymättä kameran Wi-Fi-verkkoon.
- **Kirjasto.** Selaa kameran kuvia ja videoita päivittäin ryhmiteltyinä, suodata valinnoilla JPEG,
  RAW, Video tai Lataamatta ja avaa mikä tahansa otos koko näytölle tietoineen. Lataa yksi otos tai
  valitsemasi joukko JPEG- tai RAW-muodossa tai molempina GR Lab ‑albumiin puhelimesi
  kuvakirjastoon. Videot toistetaan sovelluksessa.
- **Kaukolaukaisin.** Suuri laukaisinpainike pelkällä Bluetoothilla sekä ajastin, kuvaustapa,
  tilanvalitsimen asento, jäljellä olevien kuvien määrä ja akun varaus. Androidissa myös
  äänenvoimakkuuspainikkeet laukaisevat kameran.
- **Live-kuva.** Kameran kuva Wi-Fin kautta: tarkenna napauttamalla, aseta aukko, suljinaika, ISO
  ja valotuksen korjaus valitsimella, jossa ovat kameran tarjoamat arvot, ja vaihda kuvaustapaa,
  ajastinta, mittausta ja Kuvansäätöä.
- **Useita kameroita.** Muodosta pari niin monen kameran kanssa kuin omistat ja vaihda niiden
  välillä; voit nimetä jokaisen uudelleen tai unohtaa sen.
- **Teemat ja kielet.** Teemat Vaalea, Tumma, Pimiö, Paperi ja Sinikopio sekä kameran omien
  valikoiden 21 kieltä.
- **Yksityinen.** Ei tilejä, analytiikkaa, mainoksia eikä kaatumisraportointia. GR Lab viestii vain
  kamerasi kanssa; katso [tietosuojakäytäntö](../../app/assets/privacy.md).

## Vaatimukset

- Ricoh GR III, GR IIIx tai GR IV, mukaan lukien HDF-rungot ja GR IV Monochrome.
- Tyylit edellyttävät GR IV ‑kameraa, jossa on laiteohjelmisto 1.04 tai uudempi, GR IV HDF ‑kameraa
  tai GR IV Monochrome ‑kameraa. GR III:n ja GR IIIx:n laiteohjelmisto ei tarjoa mitään tapaa lukea
  tai kirjoittaa Kuvansäätö-asetuksia puhelimesta.
- Android 12 tai uudempi taikka iOS 15 tai uudempi.

GR Lab on nuori. Laitteistolokiin on kirjattu ajoja GR IV HDF ‑kameralla, jossa on laiteohjelmisto
1.20: parinmuodostus, yhdistäminen, kameran herättäminen, selaus, lataus, live-kuva sekä
tarkennuksen ja valotuksen muutokset. GR III- ja GR IIIx ‑tuki perustuu protokollatutkimukseen, eikä
sitä ole vielä testattu kameralla. Tehdyt havainnot löytyvät tiedostosta
[`research/hardware-validation.md`](../../research/hardware-validation.md).

## Asennus

Valmiita julkaisupaketteja ei vielä ole, joten GR Lab asennetaan kääntämällä se lähdekoodista.
Kääntämiseen tarvitaan [Flutter](https://flutter.dev) 3.47 tai uudempi sekä käyttövalmis Android SDK
tai Xcode.

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

`flutter run` asentaa sovelluksen puhelimeen, joka on liitetty tietokoneeseesi. iOS-käännökset
vaativat oman allekirjoitustiimisi, jolla on Hotspot Configuration- ja Access Wi-Fi
Information ‑ominaisuudet.

Jos haluat kokeilla sovellusta ilman kameraa, aja se esittelytilassa, joka käyttää simuloitua
GR IV ‑kameraa esimerkkikuvineen ja toimii Android-emulaattorissa ja iOS-simulaattorissa:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Käyttö

1. **Muodosta pari kamerasi kanssa.** Napauta Lisää kamera ja seuraa ohjeita. Kamerassa
   parinmuodostus löytyy kohdasta MENU → E6 → Langaton viestintä: valitse Toimintatila-asetukseksi
   Päällä, avaa Muodostetaan laitepari ja valitse Muodosta laitepari, vahvista sitten koodi
   puhelimessa ja paina kamerassa OK. Kamera näkyy sen jälkeen Kamerat-näytöllä, ja GR Lab yhdistää
   siihen itsestään, kun sovellus avataan kameran ollessa lähellä.
2. **Avaa Kirjasto.** GR Lab käynnistää kameran, jos se on sammutettu, ja liittyy sen
   Wi-Fi-verkkoon. Android pyytää hyväksymään kameran verkon kerran. Katso otosta napauttamalla
   sitä, valitse useita painamalla pitkään ja lataa ne, jotka haluat säilyttää.
3. **Kuvaa.** Kaukolaukaisin on Bluetoothilla toimiva laukaisin. Live-kuva liittyy kameran
   Wi-Fi-verkkoon ja näyttää sen kuvan sekä tarkennuksen ja valotuksen säätimet.
4. **Tallenna tyyli.** Avaa kuva Kirjastossa ja napauta Tallenna tyyli, tai luo tyyli alusta alkaen
   Tyylit-sivun painikkeella +. Muokkaa tyyliä napauttamalla sitä ja siirrä se kameraan vetämällä se
   paikan C1, C2 tai C3 päälle.

Asetusten Automaattinen katkaisu poistuu kameran Wi-Fi-verkosta, kun GR Lab on ollut jonkin aikaa
käyttämättä (oletuksena 5 minuuttia). [Näin GR Lab toimii](../behaviour.md) kuvaa jokaisen näytön
ja jokaisen yhteystilan yksityiskohtaisesti.

## Kehitys

### Rakenne

| Polku | Sisältö |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi-HTTP-rajapinta, muutos-WebSocket sekä yhdistämisen ja palautumisen istunto puhtaalla Dartilla |
| `packages/gr_camera` | Kamerakerros, jota sovellus kutsuu kaikessa kameraan liittyvässä: Bluetooth- ja Wi-Fi-sovittimet (sekä Kotlin- ja Swift-koodi Wi-Fi-verkkoon liittymiseen), istunto, parinmuodostus, haku, Kirjasto, Kuvaus ja live-kuva sekä jokaisen viestinvaihdon jäljitys |
| `packages/gr_fake_camera` | Simuloitu GR IV (BLE, Wi-Fi-liittyminen, HTTP-palvelin loopback-osoitteessa) testejä ja esittelytilaa varten |
| `app` | Flutter-sovellus sekä Kotlin- ja Swift-koodi kuvakirjastoon tallentamista varten |
| `research` | Protokollatutkimus: miten kukin reitti ja ominaisuus (characteristic) löydettiin, laiteohjelmistosta saatu näyttö, laitteistotulokset, avoimet kysymykset |
| `tool` | `check.sh`, kaikki koodin laatutarkistukset; `testflight.sh`, iOS-lähetys |

### Ajaminen

```sh
cd app
flutter run                                  # dev-käännös, oikea kamera (vaatii puhelimen, jossa on Bluetooth)
flutter run --profile                        # sama, mutta julkaisukäännöksen nopeudella
flutter run --flavor prod --release          # käännös, jonka käyttäjät saavat
flutter run --dart-define=GR_DEMO=true       # simuloitu kamera, toimii Android-emulaattorissa ja iOS-simulaattorissa
```

Käännöksiä on kaksi. `dev` (`io.jeph.grlab.dev`, nimeltään ”GR Lab Dev”) asentuu `prod`-käännöksen
(`io.jeph.grlab`, ”GR Lab”) rinnalle. Ilman valitsinta `--flavor` komennot `flutter run` ja
`flutter build` kääntävät `dev`-käännöksen.

Pelkkä `flutter run` tekee debug-käännöksen, joka piirtää jokaisen ruudun moninkertaisesti hitaammin
kuin profile- tai release-käännös (3–4 kertaa hitaammin Kirjastossa Android-emulaattorilla,
2026-11-10). Arvioi näytön sulavuutta valitsimella `--profile` tai `--release`.

Esittelytila säilyttää tietonsa erillisessä `demo/`-kansiossa. Ensimmäisellä käynnistyskerralla
Lisää kamera löytää simuloidun kameran, ja se vahvistaa parinmuodostuksen itse; myöhemmillä
käynnistyskerroilla kamera on aluksi sammutettuna ja pysyy sammutettuna, kunnes avaat Kirjaston
(herättäminen kuuluu sen Wi-Fi-verkkoon liittymiseen) tai painat kortin virtapainiketta.
Esittelytilan RAW-tiedostot ovat JPEG-tavuja, joilla on `.DNG`-pääte.

### Tarkistukset

```sh
tool/check.sh            # muotoilija, analysoija, kamerakerroksen raja, käännökset, kaikki testisarjat
tool/check.sh --static   # ilman testejä
```

Analysoija käyttää `very_good_analysis`-sääntöjä, ja info-tason huomautukset käsitellään virheinä.
Android- ja iOS-käännökset ajavat ensin komennon `tool/check.sh --static` ja pysähtyvät, jos se
epäonnistuu. Kotlin- ja Swift-varoitukset ovat virheitä. Säännöt löytyvät tiedostosta
[`AGENTS.md`](../../AGENTS.md).

### Testit

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Integraatiotesti ajaa koko esittelytilan kulun (parinmuodostus, yhdistäminen, selaus, kahden otoksen
lataus) laitteessa, emulaattorissa tai simulaattorissa. Debug-käännös tarvitsee emulaattorissa noin
400 Mt vapaata tilaa. Androidissa `flutter test` ei ota projektista oletus-flavoria eikä sovelluksen
tunnusta, joten se tarvitsee valitsimen `--flavor dev` ja etukäteen käännetyn APK:n; ilman niitä se
pysähtyy ilmoitukseen ”No application found”.

iOS-simulaattorissa sovelluksen on oltava asennettuna, kun Kuvat-käyttöoikeus myönnetään, ja
`flutter test` poistaa sovelluksen ajon jälkeen, mikä poistaa myös käyttöoikeuden. GR Lab pyytää
täyttä käyttöoikeutta voidakseen ylläpitää albumiaan, eikä iOS 26.3 ‑simulaattorissa pelkkä
`simctl privacy grant photos` estänyt iOS:ää kysymästä: sen tallentamassa käyttöoikeudessa
`auth_version` on 1, ja iOS tulkitsee sen täydeksi käyttöoikeudeksi vasta arvolla 2. Myönnä oikeus
ja aseta arvo ennen jokaista ajoa:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Vianetsintäloki

GR Lab kirjoittaa vianetsintälokia, kun Asetukset > Ota vianetsintäloki käyttöön on päällä: kaiken,
mitä se lähettää kameralle ja vastaanottaa siltä (Bluetooth-haut, luvut, kirjoitukset ja
ilmoitukset, jokaisen HTTP-pyynnön ja ‑vastauksen, WebSocket-viestit, live-kuvan ruutujen koot ja
Wi-Fi-verkkoon liittymisen vaiheet), jokaisen sovelluksen tulostaman rivin, sieppaamattomat virheet
ja natiivin Wi-Fi-koodin rivit. Asetus on oletuksena päällä `dev`-käännöksessä ja pois päältä
`prod`-käännöksessä. Kun se on pois päältä, mitään ei kirjata, ei edes logcatiin tai konsoliin,
yhtä poikkeusta lukuun ottamatta: Flutter-moottori raportoi sieppaamattomat virheet sinne edelleen
itse, joten kaatumiset pysyvät näkyvissä. Asetukset > Vianetsintäloki vie lokin jakovalikon kautta
JSON Lines ‑tiedostoina ja tyhjentää sen. Lokia säilytetään noin 50 Mt. Se sisältää kameran
Wi-Fi-salasanan.

### TestFlight

```sh
tool/testflight.sh       # kääntää iOS-sovelluksen prod-version ja lähettää sen TestFlightiin
```

Skripti kääntää `prod`-flavorin, käyttää lähetysajankohtaa koontiversion numerona ja lähettää
käännöksen App Store Connectiin, jossa se ilmestyy käsittelyn jälkeen TestFlightin alle. Sisäiset
testaajat asentavat sen TestFlight-sovelluksesta ilman kaapelia. Xcode allekirjoittaa ja lähettää
käännöksen App Store Connectin API-avaimella, joten Macissa tarvitaan avaimen tiedosto
`AuthKey_<key id>.p8` kansiossa `~/.appstoreconnect/private_keys` sekä `ASC_KEY_ID` ja
`ASC_ISSUER_ID` tiedostossa `~/.appstoreconnect/gr-lab.env`. Avaimella on oltava Admin-rooli: Apple
ei anna App Manager ‑avaimen käyttää tiimin jakeluvarmennetta. Arkisto käännetään
allekirjoittamattomana ja allekirjoitetaan App Storea varten viennin yhteydessä
(`app/ios/ExportOptions.plist`), koska itse arkiston allekirjoittaminen vaatisi tiimiin
rekisteröidyn testilaitteen.

## Osallistuminen

Vikailmoitukset ja pull requestit ovat tervetulleita. Useimmat viat ilmenevät vain oikealla
laitteistolla, joten kun [avaat issuen](https://github.com/jeph/gr-lab/issues), kerro kamerasi malli
ja laiteohjelmistoversio, puhelimesi malli ja sen Android- tai iOS-versio sekä se, mitä teit. Viety
vianetsintäloki (Asetukset, Vianetsintäloki, Vie loki) näyttää yleensä, mitä tapahtui, mutta se
sisältää kamerasi sarjanumeron ja Wi-Fi-salasanan, joten liitä se vain, jos sinulle sopii jakaa ne.

Aja `tool/check.sh` ennen kuin lähetät muutoksen; jokaisen tarkistuksen on mentävä läpi.
[`AGENTS.md`](../../AGENTS.md) kuvaa, miten koodi on järjestetty ja mitä sääntöjä se noudattaa.

Älä ilmoita epäillyistä tietoturvahaavoittuvuuksista julkisissa issueissa. Lähetä yksityinen
haavoittuvuusilmoitus [tietoturvakäytännön](../../.github/SECURITY.md) mukaisesti.

## Kiitokset

GR Lab on tehty [Flutterilla](https://flutter.dev), ja se käyttää Bluetoothiin pakettia
[universal_ble](https://pub.dev/packages/universal_ble) sekä paketteja
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) ja
[path_provider](https://pub.dev/packages/path_provider). Sen tekstit on ladottu fonteilla
[Inter](https://rsms.me/inter/) ja [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Protokollatutkimus pohjautuu Ricohin GR WORLD- ja Image Sync ‑sovelluksiin ja GR-laiteohjelmistoon
sekä [Ricoh3x](https://github.com/Trimz/Ricoh3x)-projektin muistiinpanoihin GR IIIx:n
Kuvansäätö-asetuksista.

## Lisenssi

GR Lab julkaistaan [MIT-lisenssillä](../../LICENSE). GR Labin sisältämät kolmannen osapuolen paketit
ja fontit säilyttävät omat lisenssinsä. Sovellus luettelee ne kohdassa
**Asetukset › Tietoja › Lisenssit**, ja fonttien lisenssitekstit ovat kansiossa
[`app/assets/fonts/`](../../app/assets/fonts/).

Ricohin sovellukset ja laiteohjelmisto, joihin tutkimus viittaa, kuuluvat Ricohille eivätkä ole osa
tätä repositoriota.
