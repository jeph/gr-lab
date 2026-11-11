<p align="center">
  <img src="../icon.png" alt="Ikona GR Lab" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licence: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platformy: iOS a Android">
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
  <b>Čeština</b> ·
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

**GR Lab** je doprovodná aplikace k fotoaparátům Ricoh GR (GR III, GR IIIx a GR IV) pro iOS
a Android. Prohlíží a stahuje fotky z fotoaparátu, slouží jako dálková spoušť s živým náhledem
a uchovává vaše vzhledy Ovládání obrazu na jednom místě. Je navržena tak, aby byla rychlá, snadno se
používala a pořádně se starala o barevné profily fotoaparátu: uložte vzhled, se kterým byla fotka
pořízena, upravte ho s náhledem před očima a načtěte ho do pozic Vlastní ve fotoaparátu.

GR Lab je nezávislý projekt a není spojen se společností Ricoh. S fotoaparátem komunikuje
protokolem, který byl získán reverzním inženýrstvím z vlastních aplikací Ricoh a z firmwaru
fotoaparátu; zjištění jsou sepsána ve složce [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Knihovna: fotky z fotoaparátu po dnech, s filtry pro JPEG, RAW a video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Stránka Vzhledy: tři pozice Vlastní ve fotoaparátu nad vzhledy uloženými v telefonu" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Editor vzhledu: náhled před úpravou a po ní nad posuvníky Ovládání obrazu" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Živý náhled: obraz z fotoaparátu s údaji o expozici a spouští" height="400">
</p>

<p align="center">
  <sub>Knihovna, Vzhledy, editor vzhledu a živý náhled v ukázkovém režimu se simulovaným fotoaparátem.</sub>
</p>

## Obsah

- [Funkce](#funkce)
- [Požadavky](#požadavky)
- [Instalace](#instalace)
- [Použití](#použití)
- [Vývoj](#vývoj)
- [Jak přispět](#jak-přispět)
- [Poděkování](#poděkování)
- [Licence](#licence)

## Funkce

GR Lab klade na první místo tři věci: dostat vás rychle k fotkám, nepřekážet vám a brát vzhledy
Ovládání obrazu jako něco, o co stojí za to se starat.

- **Rychlost.** GR Lab se při otevření spojí s fotoaparátem přes Bluetooth, pokud je fotoaparát
  poblíž. Otevření Knihovny fotoaparát probudí, zapne jeho Wi-Fi a připojí se k ní v jednom kroku
  a Wi-Fi pak zůstává aktivní, i když přecházíte mezi stránkami, takže se nic nepřipojuje dvakrát
  a stahování běží dál. Seznamy souborů, miniatury a náhledy se ukládají do mezipaměti v telefonu,
  aby se Knihovna otevírala rychle. S fotoaparátem GR IV HDF a telefonem s Androidem trvala cesta od
  vypnutého fotoaparátu do jeho Knihovny asi 13 sekund.
- **Snadné používání.** Na jedné obrazovce máte své fotoaparáty a Knihovna, Snímání a Vzhledy jsou
  od ní na jedno klepnutí. GR Lab fotoaparát zapne, zapne jeho Wi-Fi a připojí se k ní za vás,
  takže po spárování není potřeba na fotoaparátu nic nastavovat. Když se něco nepovede, aplikace
  řekne proč a co zkontrolovat, a nabídne Zkusit znovu. Přerušené spojení se obnoví samo.
- **Vzhledy, které můžete spravovat.** U každé fotky v Knihovně je vidět, s jakým Ovládáním obrazu
  byla pořízena, a jedním klepnutím ho uložíte jako vzhled. Vzhledy jsou uloženy ve vašem telefonu
  bez ohledu na to, ze kterého fotoaparátu pocházejí, spolu se svým nastavením, fotkou, ze které
  vznikly, a štítkem pozice Vlastní, která je obsahuje.
- **Editor vzhledu s náhledem.** Změňte základní Ovládání obrazu a všechny jeho parametry,
  rozdělené do skupin Tóny, Barva, Detail a Efekty, a výsledek sledujte na vlastní fotce nebo na
  ukázkové: posouvejte dělicí čáru mezi stavem před a po, zobrazte si je vedle sebe nebo je
  přepínejte klepnutím. Náhled se blíží tomu, jak obraz vykreslí fotoaparát, a vychází z rozboru
  jeho firmwaru
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Načítání vzhledů do fotoaparátu.** Stránka Vzhledy ukazuje, co obsahují pozice Vlastní C1 až C3
  ve fotoaparátu. Přetáhněte uložený vzhled na pozici nebo v jeho nabídce zvolte Načíst a fotoaparát
  ho má. Čtení pozic i načítání do nich funguje jen přes Bluetooth, bez připojení k Wi-Fi
  fotoaparátu.
- **Knihovna.** Procházejte fotky a videa z fotoaparátu po dnech, filtrujte podle JPEG, RAW, videa
  nebo dosud nestažených a kterýkoli snímek si otevřete na celou obrazovku i s podrobnostmi.
  Stáhněte jeden snímek nebo výběr, jako JPEG, RAW nebo obojí, do alba GR Lab v knihovně fotek
  telefonu. Stahování pokračuje, i když používáte jinou aplikaci nebo zamknete telefon: Android ho
  ukazuje v oznámení s tlačítky Pozastavit a Zrušit vše, iOS 26 a novější ukazuje jeho průběh na
  zamčené obrazovce a v Dynamic Islandu. Videa se přehrávají přímo v aplikaci.
- **Dálková spoušť.** Velké tlačítko spouště jen přes Bluetooth, se samospouští, způsobem
  exponování, voličem režimů, počtem zbývajících snímků a stavem baterie. V Androidu spouštějí
  závěrku také tlačítka hlasitosti.
- **Živý náhled.** Obraz z fotoaparátu přes Wi-Fi: klepnutím zaostřete, na voliči s hodnotami,
  které fotoaparát nabízí, nastavte clonu, čas závěrky, ISO a korekci expozice a měňte exponování,
  samospoušť, měření a Ovládání obrazu.
- **Více fotoaparátů.** Spárujte všechny, které máte, a přepínejte mezi nimi; každý můžete
  přejmenovat nebo zapomenout.
- **Motivy a jazyky.** Motivy Světlý, Tmavý, Temná komora, Papír a Kyanotypie a 21 jazyků, které
  nabízejí nabídky samotného fotoaparátu.
- **Soukromí.** Žádné účty, analytika, reklama ani hlášení pádů. GR Lab komunikuje pouze s vaším
  fotoaparátem; viz [zásady ochrany soukromí](../../app/assets/privacy.md).

## Požadavky

- Ricoh GR III, GR IIIx nebo GR IV, včetně modelů HDF a GR IV Monochrome.
- Vzhledy vyžadují GR IV s firmwarem 1.04 nebo novějším, GR IV HDF nebo GR IV Monochrome. Firmware
  modelů GR III a GR IIIx nenabízí žádný způsob, jak nastavení Ovládání obrazu z telefonu číst nebo
  zapisovat.
- Android 12 nebo novější, případně iOS 15 nebo novější.

GR Lab je mladý projekt. Protokol testů na hardwaru zaznamenává běhy s GR IV HDF s firmwarem 1.20:
párování, připojování, probouzení fotoaparátu, procházení, stahování, živý náhled, ostření a změny
expozice. Podpora modelů GR III a GR IIIx vychází z výzkumu protokolu a na fotoaparátu zatím
testována nebyla. Co bylo pozorováno, najdete v souboru
[`research/hardware-validation.md`](../../research/hardware-validation.md).

## Instalace

Hotová vydání zatím nejsou k dispozici, takže se GR Lab instaluje sestavením ze zdrojového kódu.
K sestavení je potřeba [Flutter](https://flutter.dev) 3.47 nebo novější a nastavené Android SDK
nebo Xcode.

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

`flutter run` nainstaluje aplikaci do telefonu, který je připojen k počítači. Sestavení pro iOS
vyžadují váš vlastní podpisový tým s funkcemi Hotspot Configuration a Access Wi-Fi Information.

Chcete-li aplikaci vyzkoušet bez fotoaparátu, spusťte ji v ukázkovém režimu, který používá
simulovaný GR IV s ukázkovými fotkami a funguje v emulátoru Androidu i v simulátoru iOS:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Použití

1. **Spárujte fotoaparát.** Klepněte na Přidat fotoaparát a postupujte podle průvodce. Ve
   fotoaparátu najdete párování v MENU, E6, Bezdrátová komunikace: nastavte Režim akce na Zapnuto,
   otevřete Párování a zvolte Provést párování, potom potvrďte kód v telefonu a stiskněte na
   fotoaparátu OK. Fotoaparát se pak objeví na obrazovce Fotoaparáty a GR Lab se s ním spojí sám,
   kdykoli se otevře a fotoaparát je poblíž.
2. **Otevřete Knihovnu.** GR Lab fotoaparát zapne, pokud je vypnutý, a připojí se k jeho Wi-Fi.
   Android vás jednou požádá o schválení sítě fotoaparátu. Klepnutím snímek zobrazíte, podržením
   jich vyberete víc a stáhnete si, co si chcete ponechat.
3. **Foťte.** Ovladač je spoušť přes Bluetooth. Živý náhled se připojí k Wi-Fi fotoaparátu a ukáže
   jeho obraz s ovládáním ostření a expozice.
4. **Uložte vzhled.** Otevřete fotku v Knihovně a klepněte na Uložit vzhled, nebo vytvořte vzhled
   úplně nový tlačítkem + na stránce Vzhledy. Klepnutím vzhled upravíte a přetažením na C1, C2 nebo
   C3 ho načtete do fotoaparátu.

Automatické odpojení v Nastavení ukončí připojení k Wi-Fi fotoaparátu, když se GR Lab nějakou dobu
nepoužívá (ve výchozím nastavení 5 minut). Dokument [Jak se GR Lab chová](../behaviour.md) podrobně
popisuje každou obrazovku a každý stav připojení.

## Vývoj

### Struktura

| Cesta | Obsah |
|---|---|
| `packages/gr_protocol` | BLE GATT, HTTP API přes Wi-Fi, WebSocket se změnami a relace pro připojení a obnovu spojení, v čistém Dartu |
| `packages/gr_camera` | Vrstva fotoaparátu, kterou aplikace volá pro vše, co se fotoaparátu týká: adaptéry Bluetooth a Wi-Fi (s kódem pro připojování k Wi-Fi v Kotlinu a Swiftu), relace, párování, vyhledávání, Knihovna, Snímání a živý náhled a trasování každé výměny |
| `packages/gr_fake_camera` | Simulovaný GR IV (BLE, připojení k Wi-Fi, HTTP server na zpětné smyčce) pro testy a ukázkový režim |
| `app` | Aplikace ve Flutteru s kódem v Kotlinu a Swiftu pro ukládání do knihovny fotek |
| `research` | Výzkum protokolu: jak byla každá cesta a charakteristika nalezena, doklady z firmwaru, výsledky na hardwaru, otevřené otázky |
| `tool` | `check.sh`, všechny kontroly kvality kódu; `testflight.sh`, nahrání aplikace pro iOS |

### Spuštění

```sh
cd app
flutter run                                  # sestavení dev, skutečný fotoaparát (vyžaduje telefon s Bluetooth)
flutter run --profile                        # totéž, s rychlostí sestavení release
flutter run --flavor prod --release          # sestavení, které dostanou uživatelé
flutter run --dart-define=GR_DEMO=true       # simulovaný fotoaparát, funguje v emulátoru Androidu i v simulátoru iOS
```

Existují dvě sestavení. `dev` (`io.jeph.grlab.dev`, s názvem „GR Lab Dev“) se instaluje vedle `prod`
(`io.jeph.grlab`, „GR Lab“). Bez `--flavor` sestavují `flutter run` a `flutter build` variantu `dev`.

Samotný `flutter run` vytvoří ladicí sestavení, které každý snímek obrazovky vykresluje několikrát
pomaleji než sestavení profile nebo release (3krát až 4krát v Knihovně v emulátoru Androidu,
2026-11-10). Plynulost obrazovky posuzujte s `--profile` nebo `--release`.

Ukázkový režim ukládá svá data do samostatné složky `demo/`. Při prvním spuštění najde Přidat
fotoaparát simulovaný fotoaparát a ten párování potvrdí sám; další spuštění začínají s vypnutým
fotoaparátem, který zůstane vypnutý, dokud neotevřete Knihovnu (probuzení je součástí připojení
k jeho Wi-Fi) nebo nestisknete tlačítko napájení na kartě. Ukázkové soubory RAW jsou bajty JPEG
s příponou `.DNG`.

### Kontroly

```sh
tool/check.sh            # formátovač, analyzátor, hranice vrstvy fotoaparátu, překlady, všechny sady testů
tool/check.sh --static   # bez testů
```

Analyzátor používá `very_good_analysis` a informační hlášení bere jako chyby. Sestavení pro Android
a iOS nejprve spustí `tool/check.sh --static` a zastaví se, pokud selže. Varování Kotlinu a Swiftu
jsou chyby. Pravidla najdete v souboru [`AGENTS.md`](../../AGENTS.md).

### Testy

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Integrační test projde celý ukázkový postup (spárování, připojení, procházení, stažení dvou snímků)
na zařízení, v emulátoru nebo v simulátoru. Ladicí sestavení potřebuje v emulátoru asi 400 MB
volného místa. V Androidu si `flutter test` nepřevezme z projektu výchozí variantu ani ID aplikace,
takže potřebuje `--flavor dev` a předem sestavený soubor APK; bez nich skončí s hlášením
„No application found“.

V simulátoru iOS musí být aplikace v okamžiku udělení přístupu k Fotkám nainstalovaná a
`flutter test` ji poté odinstaluje, čímž se udělený přístup smaže. GR Lab žádá o plný přístup, aby
si mohl vést své album, a v simulátoru iOS 26.3 samotný příkaz `simctl privacy grant photos` dotazu
iOS nezabránil: oprávnění, které zapíše, má `auth_version` 1 a iOS ho jako plný přístup bere až
při hodnotě 2. Před každým spuštěním proto přístup udělte a tuto hodnotu nastavte:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Protokol ladění

GR Lab vede protokoly ladění, dokud je zapnutá volba Nastavení > Zapnout protokol ladění: vše, co
fotoaparátu posílá a co od něj přijímá (vyhledávání, čtení, zápisy a oznámení přes Bluetooth, každý
požadavek HTTP a odpověď na něj, zprávy WebSocket, velikosti snímků živého náhledu a kroky
připojování k Wi-Fi), každý řádek, který aplikace vypíše, nezachycené chyby a řádky nativního kódu
pro Wi-Fi. Volba je ve výchozím stavu zapnutá v `dev` a vypnutá v `prod`. Dokud je vypnutá,
nezaznamenává se nic, ani do logcatu nebo konzole, s jedinou výjimkou: nezachycené chyby tam engine
Flutteru hlásí sám, takže pády zůstávají viditelné. Nastavení > Protokol ladění exportuje protokol
přes list sdílení jako soubory JSON Lines a vymaže ho. Protokol uchovává asi 50 MB. Obsahuje heslo
k Wi-Fi fotoaparátu.

### TestFlight

```sh
tool/testflight.sh       # sestaví aplikaci prod pro iOS a nahraje ji do TestFlight
```

Skript sestaví variantu `prod`, jako číslo sestavení použije čas nahrání a odešle ji do App Store
Connect, kde se po zpracování objeví v části TestFlight. Interní testeři si ji nainstalují
z aplikace TestFlight, bez kabelu. Xcode sestavení podepisuje a nahrává pomocí klíče API pro App
Store Connect, takže nastavení na Macu tvoří soubor klíče `AuthKey_<key id>.p8` ve složce
`~/.appstoreconnect/private_keys` a proměnné `ASC_KEY_ID` a `ASC_ISSUER_ID` v souboru
`~/.appstoreconnect/gr-lab.env`. Klíč potřebuje roli Admin: Apple nedovolí, aby klíč s rolí App
Manager použil distribuční certifikát týmu. Archiv se sestavuje nepodepsaný a pro App Store se
podepisuje až při exportu (`app/ios/ExportOptions.plist`), protože podepsání samotného archivu by
vyžadovalo, aby měl tým zaregistrované testovací zařízení.

## Jak přispět

Hlášení chyb a pull requesty jsou vítány. Většina chyb se projeví jen na skutečném hardwaru, takže
až budete [zakládat issue](https://github.com/jeph/gr-lab/issues), uveďte prosím model fotoaparátu
a verzi firmwaru, model telefonu a jeho verzi Androidu nebo iOS a popište, co jste dělali.
Exportovaný protokol ladění (Nastavení, Protokol ladění, Exportovat protokol) obvykle ukáže, co se
stalo, obsahuje však sériové číslo vašeho fotoaparátu a heslo k jeho Wi-Fi, proto ho přikládejte
jen tehdy, pokud vám nevadí tyto údaje sdílet.

Než změnu odešlete, spusťte `tool/check.sh`; projít musí všechny kontroly. Soubor
[`AGENTS.md`](../../AGENTS.md) popisuje, jak je kód uspořádán a jakými pravidly se řídí.

Podezření na bezpečnostní zranitelnosti nehlaste ve veřejných issues. Postupujte podle
[bezpečnostních zásad](../../.github/SECURITY.md) a zranitelnost nahlaste soukromě.

## Poděkování

GR Lab je postaven na frameworku [Flutter](https://flutter.dev) a používá
[universal_ble](https://pub.dev/packages/universal_ble) pro Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) a
[path_provider](https://pub.dev/packages/path_provider). Texty jsou vysázeny písmy
[Inter](https://rsms.me/inter/) a [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Výzkum protokolu se opírá o aplikace GR WORLD a Image Sync společnosti Ricoh a o firmware
fotoaparátů GR a také o poznámky projektu [Ricoh3x](https://github.com/Trimz/Ricoh3x) k nastavení
Ovládání obrazu u modelu GR IIIx.

## Licence

GR Lab je vydán pod [licencí MIT](../../LICENSE). Balíčky a písma třetích stran, které GR Lab
obsahuje, si ponechávají své vlastní licence. Aplikace je uvádí v části **Nastavení › O aplikaci ›
Licence** a texty licencí písem jsou ve složce [`app/assets/fonts/`](../../app/assets/fonts/).

Aplikace a firmware společnosti Ricoh, které výzkum cituje, patří společnosti Ricoh a nejsou
součástí tohoto repozitáře.
