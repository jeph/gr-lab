<p align="center">
  <img src="../icon.png" alt="Ikona GR Photo" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licencja: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platformy: iOS i Android">
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
  <b>Polski</b> ·
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

**GR Photo** to aplikacja towarzysząca aparatom Ricoh GR (GR III, GR IIIx i GR IV) na iOS i
Androida. Pozwala przeglądać i pobierać zdjęcia z aparatu, działa jako zdalna migawka z podglądem na
żywo i trzyma Twoje style Sterowania obrazem w jednym miejscu. Powstała po to, by była szybka i
łatwa w obsłudze oraz by porządnie zarządzała profilami kolorów aparatu: zapisz styl, w którym
zrobiono zdjęcie, edytuj go, patrząc na podgląd, i wczytaj do slotów Niestand. aparatu.

GR Photo to niezależny projekt, niepowiązany z firmą Ricoh. Z aparatem komunikuje się za pomocą
protokołu odtworzonego metodą inżynierii wstecznej z aplikacji firmy Ricoh i z oprogramowania
sprzętowego aparatu; ustalenia są opisane w [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Biblioteka: zdjęcia z aparatu pogrupowane według dni, z filtrami JPEG, RAW i Film" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Strona Style: trzy sloty Niestand. aparatu nad stylami zapisanymi w telefonie" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Edytor stylu: podgląd przed i po nad suwakami Sterowania obrazem" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Podgląd na żywo: obraz z aparatu z parametrami ekspozycji i przyciskiem migawki" height="400">
</p>

<p align="center">
  <sub>Biblioteka, Style, edytor stylu i podgląd na żywo w trybie demonstracyjnym z symulowanym aparatem.</sub>
</p>

## Spis treści

- [Funkcje](#funkcje)
- [Wymagania](#wymagania)
- [Instalacja](#instalacja)
- [Korzystanie z aplikacji](#korzystanie-z-aplikacji)
- [Rozwój aplikacji](#rozwój-aplikacji)
- [Współtworzenie](#współtworzenie)
- [Podziękowania](#podziękowania)
- [Licencja](#licencja)

## Funkcje

GR Photo stawia na pierwszym miejscu trzy rzeczy: szybki dostęp do zdjęć, nieprzeszkadzanie
użytkownikowi i traktowanie stylów Sterowania obrazem jako czegoś, czym warto zarządzać.

- **Szybka.** GR Photo łączy się z aparatem przez Bluetooth zaraz po otwarciu, jeśli aparat jest
  w pobliżu. Otwarcie Biblioteki za jednym razem wybudza aparat, włącza jego Wi-Fi i łączy się
  z nim, a Wi-Fi pozostaje potem aktywne, gdy przechodzisz między stronami, więc nic nie łączy się
  dwa razy, a pobieranie trwa dalej. Listy plików, miniatury i podglądy są przechowywane w pamięci
  podręcznej telefonu, dzięki czemu Biblioteka otwiera się szybko. W przypadku GR IV HDF i telefonu
  z Androidem przejście od wyłączonego aparatu do jego Biblioteki zajęło około 13 sekund.
- **Łatwa w obsłudze.** Wszystkie aparaty są na jednym ekranie, a Biblioteka, Fotografuj i Style są
  od niego o jedno dotknięcie. GR Photo samo włącza aparat, uruchamia jego Wi-Fi i łączy się z nim,
  więc po sparowaniu niczego nie trzeba ustawiać w aparacie. Gdy coś się nie uda, aplikacja mówi
  dlaczego i co sprawdzić, i proponuje Spróbuj ponownie. Zerwane połączenie wraca samo.
- **Style, którymi da się zarządzać.** Każde zdjęcie w Bibliotece pokazuje Sterowanie obrazem,
  z którym je zrobiono, a jedno dotknięcie zapisuje je jako styl. Style są przechowywane
  w telefonie, niezależnie od tego, z którego aparatu pochodzą, razem z ustawieniami, zdjęciem,
  z którego powstały, i etykietą slotu Niestand., w którym się znajdują.
- **Edytor stylu z podglądem.** Zmień obraz bazowy i każdy jego parametr, pogrupowane jako Ton,
  Kolor, Szczegóły i Efekty, i zobacz wynik na własnym zdjęciu albo na przykładowym: przesuwaj
  linię podziału między wersją przed i po, ustaw je obok siebie albo dotknij, aby je przełączyć.
  Podgląd w przybliżeniu oddaje sposób, w jaki aparat przetwarza obraz, ustalony na podstawie jego
  oprogramowania sprzętowego
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Wczytywanie stylów do aparatu.** Strona Style pokazuje, co znajduje się w slotach Niestand.
  aparatu, od C1 do C3. Przeciągnij zapisany styl na slot albo wybierz Wczytaj w jego menu,
  a aparat już go ma. Odczytywanie i wczytywanie slotów działa przez sam Bluetooth, bez łączenia
  się z Wi-Fi aparatu.
- **Biblioteka.** Przeglądaj zdjęcia i filmy z aparatu według dni, filtruj według JPEG, RAW, Film
  albo Niepobrane i otwieraj dowolne ujęcie na pełnym ekranie razem ze szczegółami. Pobierz jedno
  ujęcie albo kilka zaznaczonych, jako JPEG, RAW albo oba, do albumu GR Photo w bibliotece zdjęć
  telefonu. Pobieranie trwa, gdy używasz innej aplikacji albo zablokujesz telefon: Android pokazuje
  je w powiadomieniu z przyciskami Wstrzymaj i Anuluj wszystkie, a iOS 26 lub nowszy pokazuje postęp
  na ekranie blokady i w Dynamic Island. Filmy odtwarzają się w aplikacji.
- **Zdalna migawka.** Duży przycisk migawki działający przez sam Bluetooth, a do tego
  samowyzwalacz, tryb rejestracji, pokrętło trybów, liczba pozostałych zdjęć i stan baterii.
  W Androidzie migawkę wyzwalają też przyciski głośności.
- **Podgląd na żywo.** Obraz z aparatu przez Wi-Fi: dotknij, aby ustawić ostrość, ustaw przysłonę,
  czas otwarcia migawki, ISO i kompensację ekspozycji na tarczy z wartościami, które oferuje
  aparat, oraz zmieniaj ustawienia Rejestracja, Samowyzwalacz, Pomiar i Sterowanie obrazem.
- **Geotagowanie.** Aparaty GR nie mają GPS. Gdy Geotagowanie jest włączone dla aparatu, GR Photo
  wysyła do niego lokalizację Twojego telefonu przez Bluetooth, dopóki aparat jest włączony, a
  aparat zapisuje ją w każdym zdjęciu. Działa dalej, gdy używasz innej aplikacji albo blokujesz
  telefon, uruchamia się samo po włączeniu aparatu, jeśli zezwolisz na dostęp do lokalizacji zawsze,
  i ustawia zegar aparatu według czasu Twojego telefonu. Geotagowanie w tle to bezobsługowa
  alternatywa: telefon przechowuje 90-dniową historię miejsc, w których był, a GR Photo przy
  pobieraniu zdjęcia dodaje miejsce zapisane najbliżej czasu jego zrobienia, zarówno do plików JPEG,
  jak i RAW.
- **Kilka aparatów.** Sparuj wszystkie, które masz, i przełączaj się między nimi; każdemu możesz
  zmienić nazwę albo go zapomnieć.
- **Motywy i języki.** Motywy Jasny, Ciemny, Ciemnia, Papier i Cyjanotypia oraz 21 języków,
  w których dostępne jest menu samego aparatu.
- **Prywatna.** Żadnych kont, analityki, reklam ani raportowania awarii. GR Photo komunikuje się
  wyłącznie z Twoim aparatem, a Twoja lokalizacja trafia tylko do Twojego aparatu i do Twoich
  własnych zdjęć; zobacz [politykę prywatności](../../app/assets/privacy.md).

## Wymagania

- Ricoh GR III, GR IIIx albo GR IV, w tym wersje HDF oraz GR IV Monochrome.
- Style wymagają GR IV z oprogramowaniem sprzętowym w wersji 1.04 lub nowszej, GR IV HDF albo
  GR IV Monochrome. Oprogramowanie sprzętowe GR III i GR IIIx nie daje żadnej możliwości odczytu
  ani zapisu ustawień Sterowania obrazem z telefonu.
- Android 12 lub nowszy albo iOS 15 lub nowszy.

GR Photo to młody projekt. Dziennik testów sprzętowych zawiera przebiegi z GR IV HDF
z oprogramowaniem sprzętowym 1.20: parowanie, łączenie, wybudzanie aparatu, przeglądanie,
pobieranie, podgląd na żywo, zmiany ostrości i ekspozycji. Obsługa GR III i GR IIIx wynika z badań
nad protokołem i nie została jeszcze sprawdzona na aparacie. To, co zaobserwowano, opisuje
[`research/hardware-validation.md`](../../research/hardware-validation.md).

## Instalacja

Na Androidzie pobierz na telefonie `gr-photo-v<version>.apk` z
[najnowszego wydania](https://github.com/jeph/gr-photo/releases/latest) i otwórz go. Android jeden
raz poprosi o zgodę na instalowanie aplikacji z przeglądarki. Każde wydanie jest podpisane tym
samym kluczem, więc nowsze instaluje się na tym, które już masz, i zachowuje twoje aparaty oraz
ustawienia.

Na iOS każde wydanie trafia do TestFlight, na razie tylko do testerów samego projektu. Publicznego
linku do TestFlight jeszcze nie ma, więc na iPhonie GR Photo instaluje się, budując je ze źródeł.

Do zbudowania ze źródeł potrzebny jest [Flutter](https://flutter.dev) 3.47 lub nowszy ze
skonfigurowanym Android SDK albo Xcode.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` instaluje aplikację na telefonie podłączonym do komputera. Kompilacje na iOS wymagają
własnego zespołu do podpisywania z uprawnieniami (capabilities) Hotspot Configuration i Access
Wi-Fi Information. Kompilacja na Androida zbudowana ze źródeł jest podpisana kluczem debugowania
twojego komputera, a nie kluczem wydań, więc Android nie zainstaluje jednej na drugiej: najpierw
odinstaluj tę, którą masz.

Aby wypróbować aplikację bez aparatu, uruchom ją w trybie demonstracyjnym, który korzysta
z symulowanego GR IV z przykładowymi zdjęciami i działa w emulatorze Androida oraz symulatorze iOS:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Korzystanie z aplikacji

1. **Sparuj aparat.** Dotknij Dodaj aparat i postępuj zgodnie ze wskazówkami. W aparacie parowanie
   znajduje się w MENU → E6 → Komunikacja bezprz.: ustaw Tryb działania na Wł., otwórz Parowanie
   i wybierz Wykonaj parowanie, a następnie potwierdź kod w telefonie i naciśnij OK w aparacie.
   Aparat pojawi się wtedy na ekranie Aparaty, a GR Photo będzie się z nim łączyć samodzielnie, gdy
   zostanie otwarte w pobliżu aparatu.
2. **Otwórz Bibliotekę.** GR Photo włącza aparat, jeśli jest wyłączony, i łączy się z jego Wi-Fi.
   Android jednorazowo prosi o zatwierdzenie sieci aparatu. Dotknij ujęcia, aby je wyświetlić,
   naciśnij i przytrzymaj, aby zaznaczyć kilka, i pobierz to, co chcesz zachować.
3. **Fotografuj.** Pilot to migawka działająca przez Bluetooth. Podgląd na żywo łączy się z Wi-Fi
   aparatu i pokazuje jego obraz razem z elementami sterowania ostrością i ekspozycją.
4. **Zapisz styl.** Otwórz zdjęcie w Bibliotece i dotknij Zapisz styl albo utwórz styl od zera
   przyciskiem + na stronie Style. Dotknij stylu, aby go edytować, i przeciągnij go na C1, C2 albo
   C3, aby wczytać go do aparatu.
5. **Dodaj lokalizację.** GR Photo proponuje Geotagowanie raz dla każdego aparatu; możesz je też
   włączyć później, dotykając etykiety na karcie aparatu. Telefon pyta, czy GR Photo może używać
   jego lokalizacji. Od tej chwili lokalizacja jest wysyłana zawsze, gdy aparat jest włączony i w
   zasięgu. Geotagowanie w tle znajduje się w Ustawieniach, w sekcji Lokalizacja, i wymaga
   zezwolenia na dostęp do lokalizacji zawsze.

Automatyczne rozłączanie w Ustawieniach rozłącza Wi-Fi aparatu, gdy GR Photo nie jest używane przez
pewien czas (domyślnie 5 minut). Dokument [Jak zachowuje się GR Photo](../behaviour.md) szczegółowo
opisuje każdy ekran i każdy stan połączenia.

## Rozwój aplikacji

### Struktura repozytorium

| Ścieżka | Zawartość |
|---|---|
| `packages/gr_protocol` | BLE GATT, interfejs HTTP API przez Wi-Fi, WebSocket ze zmianami oraz sesja łączenia i przywracania połączenia, w czystym Darcie |
| `packages/gr_camera` | Warstwa aparatu, którą aplikacja wywołuje we wszystkim, co dotyczy aparatu: adaptery Bluetooth i Wi-Fi (z kodem łączenia z Wi-Fi w Kotlinie i Swifcie), sesja, parowanie, skanowanie, Biblioteka, Fotografuj i podgląd na żywo oraz śledzenie każdej wymiany danych |
| `packages/gr_fake_camera` | Symulowany GR IV (BLE, łączenie z Wi-Fi, serwer HTTP na interfejsie pętli zwrotnej) na potrzeby testów i trybu demonstracyjnego |
| `app` | Aplikacja Flutter z kodem w Kotlinie i Swifcie do zapisywania w bibliotece zdjęć |
| `research` | Badania nad protokołem: jak znaleziono każdą trasę i charakterystykę, dowody z oprogramowania sprzętowego, wyniki testów sprzętowych, otwarte pytania |
| `tool` | `check.sh`, wszystkie kontrole jakości kodu; skrypty, które budują, podpisują i wysyłają wydanie; `testflight.sh`, wysyłanie kompilacji iOS z Maca |

### Uruchamianie

```sh
cd app
flutter run                                  # kompilacja dev, prawdziwy aparat (wymaga telefonu z Bluetooth)
flutter run --profile                        # to samo, z szybkością kompilacji release
flutter run --flavor prod --release          # kompilacja, którą dostają użytkownicy
flutter run --dart-define=GR_DEMO=true       # symulowany aparat, działa w emulatorze Androida i symulatorze iOS
```

Są dwie kompilacje. `dev` (`io.jeph.grphoto.dev`, o nazwie „GR Photo Dev”) instaluje się obok `prod`
(`io.jeph.grphoto`, „GR Photo”). Bez `--flavor` polecenia `flutter run` i `flutter build` budują
`dev`.

Samo `flutter run` tworzy kompilację debug, która buduje każdą klatkę kilka razy wolniej niż
kompilacja profile albo release (3 do 4 razy w Bibliotece w emulatorze Androida, 2026-11-10).
Płynność ekranu oceniaj z `--profile` albo `--release`.

Tryb demonstracyjny przechowuje swoje dane w osobnym folderze `demo/`. Przy pierwszym uruchomieniu
Dodaj aparat znajduje symulowany aparat, a ten sam potwierdza parowanie; kolejne uruchomienia
zaczynają się z wyłączonym aparatem, który pozostaje wyłączony, dopóki nie otworzysz Biblioteki
(wybudzenie go jest częścią łączenia z jego Wi-Fi) albo nie naciśniesz przycisku zasilania na
karcie. Pliki RAW w trybie demonstracyjnym to bajty JPEG z nazwą `.DNG`.

### Kontrole

```sh
tool/check.sh            # formater, analizator, granica warstwy aparatu, tłumaczenia, wszystkie zestawy testów
tool/check.sh --static   # bez testów
```

Analizator używa `very_good_analysis`, a informacje (infos) są traktowane jak błędy. Kompilacje na
Androida i iOS uruchamiają najpierw `tool/check.sh --static` i zatrzymują się, jeśli zakończy się
ono niepowodzeniem. Ostrzeżenia Kotlina i Swifta są błędami. Zasady opisuje
[`AGENTS.md`](../../AGENTS.md).

### Testy

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Test integracyjny przechodzi cały scenariusz demonstracyjny (parowanie, łączenie, przeglądanie,
pobranie dwóch ujęć) na urządzeniu, w emulatorze albo w symulatorze. Kompilacja debug wymaga około
400 MB wolnego miejsca w emulatorze. W Androidzie `flutter test` nie bierze z projektu ani
domyślnego wariantu (flavor), ani identyfikatora aplikacji, więc potrzebuje `--flavor dev`
i zbudowanego wcześniej pliku APK; bez nich zatrzymuje się z komunikatem „No application found”.

W symulatorze iOS aplikacja musi być zainstalowana w chwili przyznawania dostępu do Zdjęć,
a `flutter test` odinstalowuje ją po zakończeniu, co usuwa to uprawnienie. GR Photo prosi o pełny
dostęp, aby móc prowadzić swój album, a w symulatorze iOS 26.3 samo `simctl privacy grant photos`
nie powstrzymało iOS przed pytaniem: zapisane w ten sposób uprawnienie ma `auth_version` 1, a iOS
uznaje je za pełny dostęp dopiero przy wartości 2. Przyznaj uprawnienie i ustaw tę wartość przed
każdym uruchomieniem:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Dziennik debugowania

GR Photo prowadzi dzienniki debugowania, gdy włączona jest opcja Ustawienia > Włącz dziennik
debugowania: wszystko, co wysyła do aparatu i od niego odbiera (skanowania, odczyty, zapisy
i powiadomienia Bluetooth, każde żądanie HTTP i każda odpowiedź, wiadomości WebSocket, rozmiary
klatek podglądu na żywo oraz kroki łączenia z Wi-Fi), każdy wiersz wypisywany przez aplikację,
nieprzechwycone błędy oraz wiersze natywnego kodu Wi-Fi. Ustawienie jest domyślnie włączone
w `dev` i wyłączone w `prod`. Gdy jest wyłączone, nic nie jest zapisywane, nawet w logcat ani
w konsoli, z jednym wyjątkiem: silnik Fluttera nadal sam zgłasza tam nieprzechwycone błędy, więc
awarie pozostają widoczne. Ustawienia > Dziennik debugowania eksportuje dziennik przez arkusz
udostępniania jako pliki JSON Lines i go czyści. Dziennik przechowuje około 50 MB. Zawiera hasło
Wi-Fi aparatu.

### Wydania

Każdy push do `main` jest wydaniem, które tworzy
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Workflow nadaje wydaniu
numer 0.0.N, o jeden większy od poprzedniego, uruchamia `tool/check.sh` i buduje wariant `prod` obu
aplikacji w trybie release. APK na Androida jest podpisywany kluczem wydań GR Photo i publikowany na
[stronie wydań](https://github.com/jeph/gr-photo/releases) wraz z sumą kontrolną SHA-256, atestacją
pochodzenia kompilacji oraz mapowaniem R8, które pozwala odczytać jego ślady stosu Kotlina.
Aplikacja na iOS jest podpisywana dla App Store i wysyłana do TestFlight. Klucze są przechowywane
w środowiskach GitHub, z których może korzystać tylko `main`, a zadania budujące aplikacje nie mają
żadnego z nich.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` sprawdza, czy APK został
zbudowany przez ten workflow z tego repozytorium.

```sh
tool/testflight.sh       # buduje aplikację iOS w wariancie prod i wysyła ją do TestFlight
```

Skrypt umieszcza w TestFlight z Maca kompilację, która nie jest wydaniem. Buduje wariant `prod`,
używając czasu wysyłki jako numeru kompilacji, i przesyła go do App Store Connect, gdzie po
przetworzeniu pojawia się w sekcji TestFlight. Testerzy wewnętrzni instalują go z aplikacji
TestFlight, bez kabla. Xcode podpisuje i wysyła kompilację za pomocą
klucza API App Store Connect, więc konfiguracja na Macu sprowadza się do pliku klucza
`AuthKey_<key id>.p8` w `~/.appstoreconnect/private_keys` oraz zmiennych `ASC_KEY_ID`
i `ASC_ISSUER_ID` w `~/.appstoreconnect/gr-photo.env`. Klucz musi mieć rolę Admin: Apple nie
pozwala, by klucz z rolą App Manager używał certyfikatu dystrybucyjnego zespołu. Archiwum jest
budowane bez podpisu i podpisywane dla App Store podczas eksportu (`app/ios/ExportOptions.plist`),
ponieważ podpisanie samego archiwum wymagałoby zarejestrowanego w zespole urządzenia testowego.

## Współtworzenie

Zgłoszenia błędów i pull requesty są mile widziane. Większość błędów ujawnia się dopiero na
prawdziwym sprzęcie, dlatego [otwierając zgłoszenie](https://github.com/jeph/gr-photo/issues), podaj
model aparatu i wersję jego oprogramowania sprzętowego, model telefonu i wersję Androida albo iOS
oraz opisz, co zostało zrobione. Wyeksportowany dziennik debugowania (Ustawienia, Dziennik
debugowania, Eksportuj dziennik) zwykle pokazuje, co się stało, ale zawiera numer seryjny aparatu
i hasło jego Wi-Fi, więc dołącz go tylko wtedy, gdy nie masz nic przeciwko ich udostępnieniu.

Przed wysłaniem zmiany uruchom `tool/check.sh`; wszystkie kontrole muszą przejść.
[`AGENTS.md`](../../AGENTS.md) opisuje, jak zorganizowany jest kod i jakich zasad przestrzega.

Nie zgłaszaj podejrzewanych luk w zabezpieczeniach w publicznych zgłoszeniach. Postępuj zgodnie
z [polityką bezpieczeństwa](../../.github/SECURITY.md), aby przesłać prywatne zgłoszenie luki.

## Podziękowania

GR Photo jest zbudowane we [Flutterze](https://flutter.dev) i korzysta
z [universal_ble](https://pub.dev/packages/universal_ble) do obsługi Bluetooth, a także
z [image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus)
i [path_provider](https://pub.dev/packages/path_provider). Teksty są złożone krojami
[Inter](https://rsms.me/inter/) i [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

Badania nad protokołem opierają się na aplikacjach GR WORLD i Image Sync firmy Ricoh oraz na
oprogramowaniu sprzętowym GR, a także na notatkach projektu
[Ricoh3x](https://github.com/Trimz/Ricoh3x) o ustawieniach Sterowania obrazem w GR IIIx.

## Licencja

GR Photo jest udostępniane na [licencji MIT](../../LICENSE). Zewnętrzne pakiety i czcionki zawarte
w GR Photo zachowują własne licencje. Aplikacja wymienia je w sekcji
**Ustawienia › Informacje › Licencje**, a teksty licencji czcionek znajdują się
w [`app/assets/fonts/`](../../app/assets/fonts/).

Przykładowe zdjęcia trybu demonstracyjnego pochodzą z serwisu [Unsplash](https://unsplash.com)
i są używane na
[licencji Unsplash](https://unsplash.com/license), a nie na licencji MIT; plik
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) wymienia je wraz z autorami.

Aplikacje i oprogramowanie sprzętowe firmy Ricoh, na które powołują się badania, należą do firmy
Ricoh i nie są częścią tego repozytorium.
