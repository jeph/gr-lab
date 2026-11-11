<p align="center">
  <img src="../icon.png" alt="Symbol von GR Lab" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Lizenz: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Plattformen: iOS und Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <b>Deutsch</b> ·
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

**GR Lab** ist eine Begleit-App für Ricoh-GR-Kameras (GR III, GR IIIx und GR IV) unter iOS und
Android. Sie zeigt die Fotos auf deiner Kamera an und lädt sie herunter, dient als Fernauslöser mit
Live-View und sammelt deine Looks für die Bildsteuerung an einem Ort. Sie soll schnell und einfach
zu bedienen sein und die Farbprofile der Kamera ordentlich verwalten: Speichere den Look, mit dem
ein Foto aufgenommen wurde, bearbeite ihn mit einer Vorschau und lade ihn in die Individuell-Slots
der Kamera.

GR Lab ist ein unabhängiges Projekt und steht in keiner Verbindung zu Ricoh. Die App spricht mit der
Kamera über ein Protokoll, das per Reverse Engineering aus Ricohs eigenen Apps und der
Kamera-Firmware ermittelt wurde; die Ergebnisse sind in [`research/`](../../research/README.md)
dokumentiert.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Die Mediathek: die Fotos der Kamera nach Tagen, mit Filtern für JPEG, RAW und Video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Die Seite „Looks“: die drei Individuell-Slots der Kamera über den auf dem Smartphone gespeicherten Looks" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Der Look-Editor: eine Vorher-Nachher-Vorschau über den Reglern der Bildsteuerung" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Live-View: das Bild der Kamera mit Belichtungsanzeigen und dem Auslöser" height="400">
</p>

<p align="center">
  <sub>Mediathek, Looks, der Look-Editor und Live-View, im Demomodus mit der simulierten Kamera.</sub>
</p>

## Inhalt

- [Funktionen](#funktionen)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Verwendung](#verwendung)
- [Entwicklung](#entwicklung)
- [Mitwirken](#mitwirken)
- [Danksagungen](#danksagungen)
- [Lizenz](#lizenz)

## Funktionen

Drei Dinge stehen bei GR Lab an erster Stelle: schnell an deine Fotos zu kommen, dir nicht im Weg zu
stehen und Looks für die Bildsteuerung als etwas zu behandeln, das Verwaltung verdient.

- **Schnell.** GR Lab verbindet sich beim Öffnen über Bluetooth mit deiner Kamera, wenn sie in der
  Nähe ist. Das Öffnen der Mediathek weckt die Kamera, schaltet ihr WLAN ein und verbindet sich
  damit in einem Zug. Das WLAN bleibt danach bestehen, während du zwischen den Seiten wechselst, es
  wird also nichts zweimal verbunden und ein Download läuft weiter. Dateilisten, Miniaturen und
  Vorschauen werden auf dem Smartphone zwischengespeichert, damit die Mediathek schnell öffnet. Mit
  einer GR IV HDF und einem Android-Smartphone war eine ausgeschaltete Kamera nach etwa 13 Sekunden
  in ihrer Mediathek.
- **Einfach zu bedienen.** Ein Bildschirm zeigt deine Kameras, und Mediathek, Aufnehmen und Looks
  sind von dort nur einmal Tippen entfernt. GR Lab schaltet die Kamera ein, aktiviert ihr WLAN und
  verbindet sich für dich damit, nach dem Koppeln ist an der Kamera also nichts mehr einzustellen.
  Wenn etwas fehlschlägt, sagt die App, warum und was zu prüfen ist, und bietet „Erneut versuchen“
  an. Eine abgebrochene Verbindung kommt von selbst zurück.
- **Looks, die sich verwalten lassen.** Jedes Foto in der Mediathek zeigt die Bildsteuerung, mit
  der es aufgenommen wurde, und einmal Tippen speichert sie als Look. Looks liegen auf deinem
  Smartphone, egal von welcher Kamera sie stammen, mit ihren Einstellungen, dem Foto, aus dem sie
  entstanden sind, und einer Markierung für den Individuell-Slot, der sie enthält.
- **Ein Look-Editor mit Vorschau.** Ändere das Basisbild und jeden seiner Parameter, gruppiert in
  Tonwerte, Farbe, Details und Effekte, und sieh dir das Ergebnis an deinem eigenen Foto oder einem
  Beispielfoto an: Schiebe eine Trennlinie zwischen Vorher und Nachher, stelle beide nebeneinander
  oder tippe, um zu wechseln. Die Vorschau ist eine Annäherung an die Bildverarbeitung der Kamera,
  hergeleitet aus ihrer Firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Looks in die Kamera laden.** Die Seite „Looks“ zeigt, was die Individuell-Slots C1 bis C3 der
  Kamera enthalten. Ziehe einen gespeicherten Look auf einen Slot oder wähle in seinem Menü das
  Laden in einen Slot, und die Kamera hat ihn. Das Lesen und Laden der Slots funktioniert allein
  über Bluetooth, ohne Verbindung zum WLAN der Kamera.
- **Mediathek.** Sieh dir die Fotos und Videos der Kamera nach Tagen an, filtere nach JPEG, RAW,
  Video oder „Nicht geladen“ und öffne jede Aufnahme im Vollbild mit ihren Details. Lade eine
  einzelne Aufnahme oder eine Auswahl als JPEG, RAW oder beides in ein Album „GR Lab“ in der
  Fotomediathek deines Smartphones. Downloads laufen weiter, während du eine andere App benutzt oder
  das Smartphone sperrst: Android zeigt sie in einer Benachrichtigung mit „Pausieren“ und „Alle
  abbrechen“, iOS 26 oder neuer zeigt den Fortschritt auf dem Sperrbildschirm und in der Dynamic
  Island. Videos werden in der App abgespielt.
- **Fernauslöser.** Ein großer Auslöser allein über Bluetooth, mit Selbstauslöser, Aufnahmemodus,
  Moduswahlrad, verbleibenden Aufnahmen und Akkustand. Unter Android lösen auch die Lautstärketasten
  aus.
- **Live-View.** Das Bild der Kamera über WLAN: Tippe zum Fokussieren, stelle Blende,
  Verschlusszeit, ISO und Belichtungskorrektur auf einem Wählrad mit den Werten ein, die die Kamera
  anbietet, und ändere Aufnahmemodus, Selbstauslöser, Belichtungsmessung und Bildsteuerung.
- **Mehrere Kameras.** Kopple so viele, wie du besitzt, und wechsle zwischen ihnen; jede lässt sich
  umbenennen oder entfernen.
- **Designs und Sprachen.** Die Designs Hell, Dunkel, Dunkelkammer, Papier und Cyanotypie sowie die
  21 Sprachen der Kameramenüs.
- **Privat.** Keine Konten, keine Analyse, keine Werbung, keine Absturzberichte. GR Lab spricht nur
  mit deiner Kamera; siehe die [Datenschutzerklärung](../../app/assets/privacy.md).

## Voraussetzungen

- Eine Ricoh GR III, GR IIIx oder GR IV, einschließlich der HDF-Modelle und der GR IV Monochrome.
- Looks setzen eine GR IV mit Firmware 1.04 oder neuer, eine GR IV HDF oder eine GR IV Monochrome
  voraus. Die Firmware der GR III und GR IIIx bietet keine Möglichkeit, Einstellungen der
  Bildsteuerung von einem Smartphone aus zu lesen oder zu schreiben.
- Android 12 oder neuer bzw. iOS 15 oder neuer.

GR Lab ist jung. Das Hardware-Protokoll verzeichnet Durchläufe mit einer GR IV HDF mit Firmware
1.20: Koppeln, Verbinden, Wecken der Kamera, Durchsehen, Herunterladen, Live-View, Fokus- und
Belichtungsänderungen. Die Unterstützung für GR III und GR IIIx beruht auf der Protokollforschung
und wurde noch nicht an einer Kamera getestet. Was bisher beobachtet wurde, steht in
[`research/hardware-validation.md`](../../research/hardware-validation.md).

## Installation

Es gibt noch keine fertigen Releases, GR Lab wird also installiert, indem man es aus dem Quellcode
baut. Für den Build wird [Flutter](https://flutter.dev) 3.47 oder neuer mit eingerichtetem Android
SDK oder Xcode benötigt.

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

`flutter run` installiert die App auf dem Smartphone, das an deinen Computer angeschlossen ist.
iOS-Builds brauchen dein eigenes Signing-Team mit den Capabilities Hotspot Configuration und Access
Wi-Fi Information.

Um die App ohne Kamera auszuprobieren, starte sie im Demomodus. Er verwendet eine simulierte GR IV
mit Beispielfotos und funktioniert im Android-Emulator und im iOS-Simulator:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Verwendung

1. **Kopple deine Kamera.** Tippe auf „Kamera hinzufügen“ und folge der Anleitung. Auf der Kamera
   findest du die Kopplung unter MENU → E6 → Drahtlose Kommunikation: Stelle „Aktionsmodus“ auf
   „An“, öffne „Kopplung“ und wähle „Kopplung ausführen“, bestätige dann den Code auf dem Smartphone
   und drücke an der Kamera OK. Die Kamera steht danach auf dem Bildschirm „Kameras“, und GR Lab
   verbindet sich von selbst mit ihr, wenn es geöffnet wird und die Kamera in der Nähe ist.
2. **Öffne die Mediathek.** GR Lab schaltet die Kamera ein, falls sie aus ist, und verbindet sich
   mit ihrem WLAN. Android bittet dich einmalig, dem Netzwerk der Kamera zuzustimmen. Tippe auf eine
   Aufnahme, um sie anzusehen, halte gedrückt, um mehrere auszuwählen, und lade herunter, was du
   behalten möchtest.
3. **Nimm auf.** „Fernauslöser“ ist ein Auslöser über Bluetooth. „Live-View“ verbindet sich mit dem
   WLAN der Kamera und zeigt ihr Bild, mit Bedienelementen für Fokus und Belichtung.
4. **Speichere einen Look.** Öffne ein Foto in der Mediathek und tippe auf „Look speichern“, oder
   erstelle mit + auf der Seite „Looks“ einen ganz neuen. Tippe auf einen Look, um ihn zu
   bearbeiten, und ziehe ihn auf C1, C2 oder C3, um ihn in die Kamera zu laden.

„Automatisch trennen“ in den Einstellungen verlässt das WLAN der Kamera, nachdem GR Lab eine Weile
nicht verwendet wurde (standardmäßig 5 Minuten). [So verhält sich GR Lab](../behaviour.md)
beschreibt jeden Bildschirm und jeden Verbindungszustand im Detail.

## Entwicklung

### Aufbau

| Pfad | Inhalt |
|---|---|
| `packages/gr_protocol` | BLE GATT, die HTTP-API über WLAN, der WebSocket für Änderungen und die Sitzung für Verbindungsaufbau und Wiederherstellung, in reinem Dart |
| `packages/gr_camera` | Die Kameraschicht, die die App für alles aufruft, was mit der Kamera zu tun hat: Bluetooth- und WLAN-Adapter (mit dem Kotlin- und Swift-Code für die WLAN-Verbindung), Sitzung, Kopplung, Suche, Mediathek, Aufnehmen und Live-View sowie die Aufzeichnung jedes Austauschs |
| `packages/gr_fake_camera` | Simulierte GR IV (BLE, WLAN-Verbindung, HTTP-Server auf Loopback) für Tests und den Demomodus |
| `app` | Die Flutter-App, mit Kotlin- und Swift-Code für das Speichern in der Fotomediathek |
| `research` | Protokollforschung: wie jede Route und jede Characteristic gefunden wurde, Belege aus der Firmware, Hardware-Ergebnisse, offene Fragen |
| `tool` | `check.sh`, alle Prüfungen der Codequalität; `testflight.sh`, der iOS-Upload |

### Ausführen

```sh
cd app
flutter run                                  # dev-Build, echte Kamera (benötigt ein Smartphone mit Bluetooth)
flutter run --profile                        # dasselbe, mit der Geschwindigkeit eines Release-Builds
flutter run --flavor prod --release          # der Build, den Nutzer erhalten
flutter run --dart-define=GR_DEMO=true       # simulierte Kamera, funktioniert im Android-Emulator und im iOS-Simulator
```

Es gibt zwei Builds. `dev` (`io.jeph.grlab.dev`, mit dem Namen „GR Lab Dev“) wird neben `prod`
(`io.jeph.grlab`, „GR Lab“) installiert. Ohne `--flavor` bauen `flutter run` und `flutter build`
`dev`.

`flutter run` allein erzeugt einen Debug-Build, der jedes Frame um ein Mehrfaches langsamer aufbaut
als ein Profile- oder Release-Build (3- bis 4-mal langsamer in der Mediathek auf einem
Android-Emulator, 2026-11-10). Beurteile mit `--profile` oder `--release`, wie flüssig ein
Bildschirm läuft.

Der Demomodus legt seine Daten in einem eigenen Ordner `demo/` ab. Beim ersten Start findet „Kamera
hinzufügen“ die simulierte Kamera, und sie bestätigt die Kopplung von selbst; spätere Starts
beginnen mit ausgeschalteter Kamera, die aus bleibt, bis du die Mediathek öffnest (das Wecken gehört
zum Verbinden mit ihrem WLAN) oder die Ein/Aus-Taste der Karte drückst. Die RAW-Dateien des
Demomodus sind JPEG-Bytes mit einem `.DNG`-Namen.

### Prüfungen

```sh
tool/check.sh            # Formatter, Analyzer, Grenze der Kameraschicht, Übersetzungen, alle Testsuiten
tool/check.sh --static   # ohne die Tests
```

Der Analyzer verwendet `very_good_analysis`, wobei Infos als Fehler behandelt werden. Android- und
iOS-Builds führen zuerst `tool/check.sh --static` aus und brechen ab, wenn es fehlschlägt.
Warnungen in Kotlin und Swift sind Fehler. Die Regeln stehen in [`AGENTS.md`](../../AGENTS.md).

### Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Der Integrationstest durchläuft den gesamten Demo-Ablauf (koppeln, verbinden, durchsehen, zwei
Aufnahmen herunterladen) auf einem Gerät, Emulator oder Simulator. Ein Debug-Build braucht etwa
400 MB freien Speicher auf dem Emulator. Unter Android übernimmt `flutter test` weder den
Standard-Flavor noch die ID der App aus dem Projekt und braucht deshalb `--flavor dev` und eine
vorab gebaute APK; ohne sie bricht es mit „No application found“ ab.

Im iOS-Simulator muss die App installiert sein, wenn der Zugriff auf Fotos gewährt wird, und
`flutter test` deinstalliert sie anschließend, wodurch die Freigabe gelöscht wird. GR Lab fragt nach
vollem Zugriff, um sein Album zu führen, und im Simulator mit iOS 26.3 hielt
`simctl privacy grant photos` allein iOS nicht vom Nachfragen ab: Die Freigabe, die es einträgt, hat
`auth_version` 1, und iOS wertet sie erst bei 2 als vollen Zugriff. Gewähre den Zugriff und setze
diesen Wert vor jedem Durchlauf:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Debug-Protokoll

GR Lab führt Debug-Protokolle, solange Einstellungen > Debug-Protokoll aktivieren eingeschaltet
ist: alles, was die App an die Kamera sendet und von ihr empfängt (Bluetooth-Scans, Lese- und
Schreibvorgänge und Benachrichtigungen, jede HTTP-Anfrage und -Antwort, WebSocket-Nachrichten, die
Frame-Größen des Live-View und die Schritte der WLAN-Verbindung), jede Zeile, die die App ausgibt,
nicht abgefangene Fehler und die Zeilen des nativen WLAN-Codes. Die Einstellung ist in `dev`
standardmäßig ein- und in `prod` ausgeschaltet. Solange sie aus ist, wird nichts protokolliert,
auch nicht in logcat oder auf der Konsole, mit einer Ausnahme: Die Flutter-Engine meldet nicht
abgefangene Fehler dort weiterhin selbst, Abstürze bleiben also sichtbar. Einstellungen >
Debug-Protokoll exportiert das Protokoll über das Teilen-Menü als JSON-Lines-Dateien und löscht es.
Das Protokoll behält etwa 50 MB. Es enthält das WLAN-Passwort der Kamera.

### TestFlight

```sh
tool/testflight.sh       # baut die prod-iOS-App und lädt sie zu TestFlight hoch
```

Das Skript baut den Flavor `prod` mit dem Zeitpunkt des Uploads als Build-Nummer und sendet ihn an
App Store Connect, wo er nach der Verarbeitung unter TestFlight erscheint. Interne Tester
installieren ihn aus der TestFlight-App, ohne Kabel. Xcode signiert den Build und lädt ihn mit einem
API-Schlüssel für App Store Connect hoch; die Einrichtung auf einem Mac besteht daher aus der Datei
`AuthKey_<key id>.p8` des Schlüssels in `~/.appstoreconnect/private_keys` sowie `ASC_KEY_ID` und
`ASC_ISSUER_ID` in `~/.appstoreconnect/gr-lab.env`. Der Schlüssel braucht die Rolle „Admin“: Apple
lässt einen Schlüssel mit der Rolle „App-Manager“ das Distributionszertifikat des Teams nicht
verwenden. Das Archiv wird unsigniert gebaut und beim Export für den App Store signiert
(`app/ios/ExportOptions.plist`), weil das Signieren des Archivs selbst ein registriertes Testgerät
im Team erfordern würde.

## Mitwirken

Fehlerberichte und Pull Requests sind willkommen. Die meisten Fehler zeigen sich nur an echter
Hardware. Wenn du [ein Issue eröffnest](https://github.com/jeph/gr-lab/issues), gib deshalb bitte
dein Kameramodell und die Firmware-Version, dein Smartphone-Modell und dessen Android- oder
iOS-Version an und beschreibe, was du getan hast. Ein exportiertes Debug-Protokoll (Einstellungen,
Debug-Protokoll, Protokoll exportieren) zeigt meist, was passiert ist, enthält aber die Seriennummer
und das WLAN-Passwort deiner Kamera; hänge es also nur an, wenn du damit einverstanden bist, diese
weiterzugeben.

Führe `tool/check.sh` aus, bevor du eine Änderung einreichst; jede Prüfung muss bestanden werden.
[`AGENTS.md`](../../AGENTS.md) beschreibt, wie der Code aufgebaut ist und welchen Regeln er folgt.

Melde vermutete Sicherheitslücken nicht in öffentlichen Issues. Folge der
[Sicherheitsrichtlinie](../../.github/SECURITY.md), um eine Sicherheitslücke vertraulich zu melden.

## Danksagungen

GR Lab ist mit [Flutter](https://flutter.dev) gebaut und verwendet
[universal_ble](https://pub.dev/packages/universal_ble) für Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) und
[path_provider](https://pub.dev/packages/path_provider). Der Text ist in
[Inter](https://rsms.me/inter/) und [JetBrains Mono](https://www.jetbrains.com/lp/mono/) gesetzt.

Die Protokollforschung stützt sich auf Ricohs Apps GR WORLD und Image Sync und die GR-Firmware sowie
auf die Notizen des Projekts [Ricoh3x](https://github.com/Trimz/Ricoh3x) zu den Einstellungen der
Bildsteuerung der GR IIIx.

## Lizenz

GR Lab wird unter der [MIT-Lizenz](../../LICENSE) veröffentlicht. Pakete und Schriften von
Drittanbietern, die GR Lab enthält, behalten ihre eigenen Lizenzen. Die App führt sie unter
**Einstellungen › Info › Lizenzen** auf, und die Lizenztexte der Schriften liegen in
[`app/assets/fonts/`](../../app/assets/fonts/).

Ricohs Apps und Firmware, die in der Forschung zitiert werden, gehören Ricoh und sind nicht Teil
dieses Repositorys.
