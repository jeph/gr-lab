<p align="center">
  <img src="../icon.png" alt="Icona di GR Lab" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licenza: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Piattaforme: iOS e Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt.md">Português</a> ·
  <b>Italiano</b> ·
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

**GR Lab** è un'app complementare per le fotocamere Ricoh GR (GR III, GR IIIx e GR IV) su iOS e
Android. Sfoglia e scarica le foto presenti sulla fotocamera, funziona da scatto remoto con live
view e tiene i tuoi stili di Controllo immagine in un unico posto. È pensata per essere veloce e
facile da usare, e per gestire come si deve i profili colore della fotocamera: salvi lo stile con
cui è stata scattata una foto, lo modifichi con l'aiuto di un'anteprima e lo carichi negli slot
Personalizzata della fotocamera.

GR Lab è un progetto indipendente e non è affiliato a Ricoh. Comunica con la fotocamera tramite un
protocollo ricavato con il reverse engineering delle app di Ricoh e del firmware della fotocamera;
i risultati sono documentati in [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="La Libreria: le foto della fotocamera divise per giorno, con i filtri per JPEG, RAW e video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="La pagina Stili: i tre slot Personalizzata della fotocamera sopra gli stili salvati sul telefono" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="L'editor degli stili: un'anteprima prima e dopo sopra i cursori di Controllo immagine" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Live view: l'immagine della fotocamera con i valori di esposizione e il pulsante di scatto" height="400">
</p>

<p align="center">
  <sub>Libreria, Stili, l'editor degli stili e il live view, in modalità demo con la fotocamera simulata.</sub>
</p>

## Indice

- [Funzionalità](#funzionalità)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Utilizzo](#utilizzo)
- [Sviluppo](#sviluppo)
- [Contribuire](#contribuire)
- [Ringraziamenti](#ringraziamenti)
- [Licenza](#licenza)

## Funzionalità

GR Lab mette tre cose al primo posto: arrivare in fretta alle tue foto, non starti tra i piedi e
trattare gli stili di Controllo immagine come qualcosa che vale la pena gestire.

- **Veloce.** All'apertura GR Lab si collega alla fotocamera tramite Bluetooth, se è nelle
  vicinanze. Aprendo la Libreria la fotocamera viene riattivata, il suo Wi-Fi acceso e il telefono
  connesso in un solo passaggio; il Wi-Fi resta poi attivo mentre passi da una pagina all'altra,
  così nulla si connette due volte e un download prosegue. Elenchi dei file, miniature e anteprime
  vengono conservati nella cache del telefono, così la Libreria si apre in fretta. Con una GR IV HDF
  e un telefono Android, da fotocamera spenta alla Libreria sono bastati circa 13 secondi.
- **Facile da usare.** Un'unica schermata raccoglie le tue fotocamere, e da lì Libreria, Scatta e
  Stili sono a un tocco. GR Lab accende la fotocamera, ne attiva il Wi-Fi e vi si connette al posto
  tuo, quindi dopo l'accoppiamento non c'è nulla da impostare sulla fotocamera. Quando qualcosa non
  va, l'app dice perché e che cosa controllare, con Riprova. Una connessione che cade si
  ristabilisce da sola.
- **Stili che puoi gestire.** Ogni foto della Libreria mostra il Controllo immagine con cui è stata
  scattata, e basta un tocco per salvarlo come stile. Gli stili vivono sul telefono, da qualunque
  fotocamera provengano, con le loro impostazioni, la foto da cui derivano e un'etichetta per lo
  slot Personalizzata che li contiene.
- **Un editor degli stili con anteprima.** Cambia l'immagine di base e tutti i suoi parametri,
  raggruppati in Tono, Colore, Dettaglio ed Effetti, e guarda il risultato su una tua foto o su una
  di esempio: fai scorrere un divisore tra il prima e il dopo, affiancali oppure tocca per
  alternarli. L'anteprima approssima la resa della fotocamera, ricostruita a partire dal suo
  firmware ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Carica gli stili nella fotocamera.** La pagina Stili mostra che cosa contengono gli slot
  Personalizzata da C1 a C3 della fotocamera. Trascina uno stile salvato su uno slot, oppure scegli
  Carica dal suo menu, e la fotocamera lo riceve. La lettura e il caricamento degli slot funzionano
  con il solo Bluetooth, senza connettersi al Wi-Fi della fotocamera.
- **Libreria.** Sfoglia le foto e i video della fotocamera divisi per giorno, filtra per JPEG, RAW,
  video o Non scaricati e apri qualsiasi scatto a schermo intero con i suoi dettagli. Scarica uno
  scatto o una selezione, in JPEG, in RAW o in entrambi i formati, in un album GR Lab nella
  libreria foto del telefono. I download continuano mentre usi un'altra app o blocchi il telefono:
  Android li mostra in una notifica con Pausa e Annulla tutti, e iOS 26 o versioni successive ne
  mostra l'avanzamento nella schermata di blocco e nella Dynamic Island. I video si riproducono
  nell'app.
- **Scatto remoto.** Un grande pulsante di scatto con il solo Bluetooth, con l'autoscatto, la
  modalità di scatto, la ghiera dei modi, gli scatti rimasti e la batteria. Su Android si scatta
  anche con i tasti del volume.
- **Live view.** L'immagine della fotocamera tramite Wi-Fi: tocca per mettere a fuoco, imposta
  diaframma, tempo di posa, ISO e compensazione dell'esposizione su una ghiera con i valori che la
  fotocamera offre, e cambia Scatto, Autoscatto, Misurazione e Controllo immagine.
- **Più fotocamere.** Accoppia tutte quelle che possiedi e passa dall'una all'altra; puoi
  rinominarle o dimenticarle una per una.
- **Temi e lingue.** I temi Chiaro, Scuro, Camera oscura, Carta e Cianotipia, e le 21 lingue dei
  menu della fotocamera.
- **Riservata.** Niente account, analisi dei dati, pubblicità o segnalazione degli arresti anomali.
  GR Lab comunica soltanto con la tua fotocamera; consulta
  l'[informativa sulla privacy](../../app/assets/privacy.md).

## Requisiti

- Una Ricoh GR III, GR IIIx o GR IV, comprese le versioni HDF e la GR IV Monochrome.
- Gli Stili richiedono una GR IV con firmware 1.04 o successivo, una GR IV HDF o una GR IV
  Monochrome. Il firmware di GR III e GR IIIx non offre alcun modo per leggere o scrivere le
  impostazioni di Controllo immagine da un telefono.
- Android 12 o versioni successive, oppure iOS 15 o versioni successive.

GR Lab è un progetto giovane. Il registro delle prove hardware documenta sessioni con una GR IV HDF
con firmware 1.20: accoppiamento, connessione, riattivazione della fotocamera, navigazione,
download, live view, modifiche di messa a fuoco ed esposizione. Il supporto per GR III e GR IIIx
deriva dalla ricerca sul protocollo e non è ancora stato provato su una fotocamera. Per ciò che è
stato osservato, consulta [`research/hardware-validation.md`](../../research/hardware-validation.md).

## Installazione

Non esistono ancora versioni pacchettizzate, quindi GR Lab si installa compilandola dal codice
sorgente. La compilazione richiede [Flutter](https://flutter.dev) 3.47 o successivo, con Android SDK
o Xcode configurati.

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

`flutter run` installa l'app sul telefono collegato al computer. Le build per iOS richiedono un
proprio team di firma con le capability Hotspot Configuration e Access Wi-Fi Information.

Per provare l'app senza una fotocamera, avviala in modalità demo, che usa una GR IV simulata con
foto di esempio e funziona sull'emulatore Android e sul simulatore iOS:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Utilizzo

1. **Accoppia la fotocamera.** Tocca Aggiungi fotocamera e segui la guida. Sulla fotocamera
   l'accoppiamento si trova in MENU, E6, Comunicazione wireless: imposta Modalità operativa su On,
   apri Accoppiamento e scegli Esegui accoppiamento, poi conferma il codice sul telefono e premi OK
   sulla fotocamera. La fotocamera compare quindi nella schermata Fotocamere, e GR Lab vi si
   collega da sola quando viene aperta con la fotocamera nelle vicinanze.
2. **Apri la Libreria.** GR Lab accende la fotocamera se è spenta e si connette al suo Wi-Fi.
   Android chiede di approvare la rete della fotocamera una sola volta. Tocca uno scatto per
   vederlo, tieni premuto per selezionarne più di uno e scarica quelli che vuoi conservare.
3. **Scatta.** Telecomando è un pulsante di scatto tramite Bluetooth. Live view si connette al
   Wi-Fi della fotocamera e ne mostra l'immagine, con i controlli di messa a fuoco ed esposizione.
4. **Salva uno stile.** Apri una foto nella Libreria e tocca Salva stile, oppure creane uno da zero
   con + nella pagina Stili. Tocca uno stile per modificarlo e trascinalo su C1, C2 o C3 per
   caricarlo nella fotocamera.

Disconnessione automatica, in Impostazioni, esce dal Wi-Fi della fotocamera dopo che GR Lab è
rimasta inutilizzata per un po' (5 minuti per impostazione predefinita).
[Come si comporta GR Lab](../behaviour.md) descrive in dettaglio ogni schermata e ogni stato della
connessione.

## Sviluppo

### Struttura

| Percorso | Contenuto |
|---|---|
| `packages/gr_protocol` | BLE GATT, API HTTP via Wi-Fi, WebSocket delle modifiche e la sessione di connessione e ripristino, in puro Dart |
| `packages/gr_camera` | Il livello fotocamera che l'app chiama per tutto ciò che riguarda la fotocamera: adattatori Bluetooth e Wi-Fi (con il codice Kotlin e Swift per la connessione al Wi-Fi), sessione, accoppiamento, ricerca, Libreria, Scatta e live view, e tracciamento di ogni scambio |
| `packages/gr_fake_camera` | GR IV simulata (BLE, connessione Wi-Fi, server HTTP su loopback) per i test e la modalità demo |
| `app` | L'app Flutter, con il codice Kotlin e Swift per il salvataggio nella libreria foto |
| `research` | Ricerca sul protocollo: come sono state individuate ogni route e ogni caratteristica, riscontri nel firmware, risultati sull'hardware, questioni aperte |
| `tool` | `check.sh`, tutti i controlli di qualità del codice; `testflight.sh`, il caricamento per iOS |

### Esecuzione

```sh
cd app
flutter run                                  # build dev, fotocamera reale (serve un telefono con Bluetooth)
flutter run --profile                        # la stessa, alla velocità di una build release
flutter run --flavor prod --release          # la build che ricevono gli utenti
flutter run --dart-define=GR_DEMO=true       # fotocamera simulata, funziona sull'emulatore Android e sul simulatore iOS
```

Le build sono due. `dev` (`io.jeph.grlab.dev`, chiamata "GR Lab Dev") si installa accanto a `prod`
(`io.jeph.grlab`, "GR Lab"). Senza `--flavor`, `flutter run` e `flutter build` compilano `dev`.

`flutter run` da solo produce una build di debug, che genera ogni fotogramma con una lentezza di
diverse volte superiore rispetto a una build profile o release (da 3 a 4 volte nella Libreria su un
emulatore Android, 2026-11-10). Valuta la fluidità di una schermata con `--profile` o `--release`.

La modalità demo conserva i propri dati in una cartella `demo/` separata. Al primo avvio, Aggiungi
fotocamera trova la fotocamera simulata, che conferma l'accoppiamento da sola; agli avvii successivi
la fotocamera parte spenta e resta tale finché non apri la Libreria (riattivarla fa parte della
connessione al suo Wi-Fi) o non premi il pulsante di accensione della scheda. I file RAW della demo
sono byte JPEG con un nome `.DNG`.

### Controlli

```sh
tool/check.sh            # formattatore, analizzatore, confine del livello fotocamera, traduzioni, tutte le suite di test
tool/check.sh --static   # senza i test
```

L'analizzatore usa `very_good_analysis` con gli avvisi di tipo info trattati come errori. Le build
per Android e iOS eseguono prima `tool/check.sh --static` e si fermano se fallisce. Gli avvisi di
Kotlin e Swift sono errori. Per le regole, consulta [`AGENTS.md`](../../AGENTS.md).

### Test

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Il test di integrazione esegue l'intero flusso demo (accoppiamento, connessione, navigazione,
download di due scatti) su un dispositivo, un emulatore o un simulatore. Una build di debug richiede
circa 400 MB liberi sull'emulatore. Su Android, `flutter test` non ricava dal progetto né il flavor
predefinito né l'ID dell'app, quindi servono `--flavor dev` e un APK compilato in precedenza; senza
di essi si ferma con "No application found".

Sul simulatore iOS l'app deve essere installata nel momento in cui viene concesso l'accesso a Foto,
e `flutter test` la disinstalla al termine, cancellando così l'autorizzazione. GR Lab chiede
l'accesso completo, per mantenere il proprio album, e sul simulatore di iOS 26.3 il solo
`simctl privacy grant photos` non è bastato a impedire a iOS di chiederlo: l'autorizzazione che
registra ha `auth_version` 1, e iOS la considera accesso completo solo a 2. Concedila e imposta
quel valore prima di ogni esecuzione:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Log di debug

GR Lab conserva i log di debug finché Impostazioni > Attiva log di debug è attivo: tutto ciò che
invia alla fotocamera e riceve da essa (scansioni, letture, scritture e notifiche Bluetooth, ogni
richiesta e risposta HTTP, i messaggi WebSocket, le dimensioni dei fotogrammi del live view e i
passaggi della connessione al Wi-Fi), ogni riga stampata dall'app, gli errori non gestiti e le righe
del codice Wi-Fi nativo. L'impostazione è attiva per impostazione predefinita in `dev` e disattivata
in `prod`. Finché è disattivata non viene registrato nulla, nemmeno su logcat o sulla console, con
una sola eccezione: il motore di Flutter continua a segnalarvi da sé gli errori non gestiti, così
gli arresti anomali restano visibili. Impostazioni > Log di debug esporta il log tramite il foglio
di condivisione sotto forma di file JSON Lines e lo cancella. Il log conserva circa 50 MB. Contiene
la password del Wi-Fi della fotocamera.

### TestFlight

```sh
tool/testflight.sh       # compila l'app iOS prod e la carica su TestFlight
```

Lo script compila il flavor `prod` usando l'ora del caricamento come numero di build e lo invia ad
App Store Connect, dove compare in TestFlight una volta elaborato. I tester interni lo installano
dall'app TestFlight, senza cavo. Xcode firma e carica la build con una chiave API di App Store
Connect, quindi la configurazione su un Mac consiste nel file `AuthKey_<key id>.p8` della chiave in
`~/.appstoreconnect/private_keys`, e in `ASC_KEY_ID` e `ASC_ISSUER_ID` in
`~/.appstoreconnect/gr-lab.env`. La chiave deve avere il ruolo Admin: Apple non permette a una
chiave App Manager di usare il certificato di distribuzione del team. L'archivio viene compilato
senza firma e firmato per l'App Store al momento dell'esportazione
(`app/ios/ExportOptions.plist`), perché firmare l'archivio stesso richiederebbe un dispositivo di
test registrato nel team.

## Contribuire

Segnalazioni di bug e pull request sono benvenute. La maggior parte dei bug si manifesta solo
sull'hardware reale, quindi quando
[apri una issue](https://github.com/jeph/gr-lab/issues) indica il modello della fotocamera e la
versione del firmware, il modello del telefono e la sua versione di Android o iOS, e che cosa hai
fatto. Un log di debug esportato (Impostazioni, Log di debug, Esporta log) di solito mostra che cosa
è successo, ma contiene il numero di serie e la password del Wi-Fi della fotocamera, quindi allegalo
solo se non hai problemi a condividerli.

Prima di inviare una modifica, esegui `tool/check.sh`; tutti i controlli devono essere superati.
[`AGENTS.md`](../../AGENTS.md) descrive com'è organizzato il codice e le regole che segue.

Non segnalare sospette vulnerabilità di sicurezza nelle issue pubbliche. Segui la
[politica di sicurezza](../../.github/SECURITY.md) per inviare una segnalazione privata.

## Ringraziamenti

GR Lab è realizzata con [Flutter](https://flutter.dev) e usa
[universal_ble](https://pub.dev/packages/universal_ble) per il Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) e
[path_provider](https://pub.dev/packages/path_provider). I testi sono composti in
[Inter](https://rsms.me/inter/) e [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

La ricerca sul protocollo si basa sulle app GR WORLD e Image Sync di Ricoh e sul firmware delle GR,
oltre che sugli appunti del progetto [Ricoh3x](https://github.com/Trimz/Ricoh3x) sulle impostazioni
di Controllo immagine della GR IIIx.

## Licenza

GR Lab è distribuita con [licenza MIT](../../LICENSE). I pacchetti e i font di terze parti inclusi
in GR Lab mantengono le rispettive licenze. L'app li elenca in **Impostazioni › Informazioni ›
Licenze**, e i testi delle licenze dei font si trovano in
[`app/assets/fonts/`](../../app/assets/fonts/).

Le app e il firmware di Ricoh, citati dalla ricerca, appartengono a Ricoh e non fanno parte di
questo repository.
