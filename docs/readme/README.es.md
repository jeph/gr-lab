<p align="center">
  <img src="../icon.png" alt="Icono de GR Photo" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licencia: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Plataformas: iOS y Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <b>Español</b> ·
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

**GR Photo** es una app complementaria para las cámaras Ricoh GR (GR III, GR IIIx y GR IV) en iOS y
Android. Explora y descarga las fotos de tu cámara, sirve de disparador remoto con vista en directo
y reúne tus estilos de Control de imagen en un solo lugar. Está pensada para ser rápida y fácil de
usar, y para gestionar como es debido los perfiles de color de la cámara: guarda el estilo con el
que se tomó una foto, edítalo con una vista previa y cárgalo en las ranuras Personalizado de la
cámara.

GR Photo es un proyecto independiente y no está afiliado a Ricoh. Se comunica con la cámara mediante
un protocolo obtenido por ingeniería inversa de las apps de Ricoh y del firmware de la cámara; los
hallazgos están documentados en [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="La Biblioteca: las fotos de la cámara por días, con filtros para JPEG, RAW y vídeo" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="La página Estilos: las tres ranuras Personalizado de la cámara sobre los estilos guardados en el teléfono" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="El editor de estilos: una vista previa del antes y el después sobre los controles deslizantes de Control de imagen" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Vista en directo: la imagen de la cámara con los datos de exposición y el disparador" height="400">
</p>

<p align="center">
  <sub>Biblioteca, Estilos, el editor de estilos y la vista en directo, en modo demo con la cámara simulada.</sub>
</p>

## Contenido

- [Funciones](#funciones)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Desarrollo](#desarrollo)
- [Contribuir](#contribuir)
- [Agradecimientos](#agradecimientos)
- [Licencia](#licencia)

## Funciones

GR Photo da prioridad a tres cosas: llegar rápido a tus fotos, no estorbar y tratar los estilos de
Control de imagen como algo que merece la pena gestionar.

- **Rápida.** GR Photo se enlaza con tu cámara por Bluetooth al abrirse, si la cámara está cerca. Al
  abrir la Biblioteca, despierta la cámara, activa su Wi-Fi y se conecta a ella de una sola vez, y
  el Wi-Fi sigue activo mientras pasas de una página a otra, así que nada se conecta dos veces y
  las descargas continúan. Las listas de archivos, las miniaturas y las vistas previas se guardan
  en caché en el teléfono para que la Biblioteca se abra enseguida. Con una GR IV HDF y un teléfono
  Android, una cámara apagada llegó a su Biblioteca en unos 13 segundos.
- **Fácil de usar.** Una sola pantalla reúne tus cámaras, y Biblioteca, Disparo y Estilos están a
  un toque de ella. GR Photo enciende la cámara, activa su Wi-Fi y se conecta a ella por ti, así que
  no hay nada que ajustar en la cámara después del emparejamiento. Cuando algo falla, explica por
  qué y qué comprobar, con la opción Reintentar. Una conexión que se corta vuelve por sí sola.
- **Estilos que puedes gestionar.** Cada foto de la Biblioteca muestra el Control de imagen con el
  que se tomó, y con un toque se guarda como estilo. Los estilos viven en tu teléfono, vengan de la
  cámara que vengan, con sus ajustes, la foto de la que proceden y una etiqueta de la ranura
  Personalizado que los contiene.
- **Un editor de estilos con vista previa.** Cambia la imagen base y todos sus parámetros,
  agrupados en Tono, Color, Detalle y Efectos, y comprueba el resultado en tu propia foto o en una
  de muestra: desliza un divisor entre el antes y el después, ponlos lado a lado o toca para
  alternar. La vista previa se aproxima al procesado de la cámara, deducido de su firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Carga estilos en la cámara.** La página Estilos muestra lo que contienen las ranuras
  Personalizado C1 a C3 de la cámara. Arrastra un estilo guardado a una ranura, o elige Cargar en
  su menú, y la cámara ya lo tiene. Leer y cargar las ranuras funciona solo con Bluetooth, sin
  conectarse al Wi-Fi de la cámara.
- **Biblioteca.** Explora las fotos y los vídeos de la cámara por días, filtra por JPEG, RAW, vídeo
  o sin descargar, y abre cualquier toma a pantalla completa con sus detalles. Descarga una toma o
  una selección, como JPEG, RAW o ambos, en un álbum GR Photo de la fototeca de tu teléfono. Las
  descargas siguen mientras usas otra app o bloqueas el teléfono: Android las muestra en una
  notificación con Pausar y Cancelar todo, e iOS 26 o posterior muestra su progreso en la pantalla
  de bloqueo y en la Dynamic Island. Los vídeos se reproducen en la app.
- **Disparador remoto.** Un botón de disparo grande que funciona solo con Bluetooth, con el
  autodisparador, el modo Fotografiar, el dial de modos, las fotos restantes y la batería. En
  Android, los botones de volumen también disparan.
- **Vista en directo.** La imagen de la cámara por Wi-Fi: toca para enfocar, ajusta la apertura, la
  velocidad de obturación, el ISO y la compensación de exposición en un dial con los valores que
  ofrece la cámara, y cambia el modo Fotografiar, el autodisparador, la medición y el Control de
  imagen.
- **Geoetiquetado.** Las cámaras GR no tienen GPS. Con Geoetiquetado en directo activado para una
  cámara, GR Photo le envía la ubicación de tu teléfono por Bluetooth mientras la cámara está
  encendida, y la cámara la guarda en cada foto. Se inicia una vez que has abierto GR Photo y sigue
  funcionando mientras usas otra app o bloqueas el teléfono. Geoetiquetado en segundo plano es la
  alternativa que no requiere atención: el teléfono guarda un historial de 90 días de los lugares
  donde ha estado, y GR Photo añade a cada foto, cuando la descargas, el lugar registrado más cerca
  de la hora en que se tomó, tanto en archivos JPEG como RAW. Los dos están desactivados hasta que
  los activas para una cámara.
- **Varias cámaras.** Empareja todas las que tengas y cambia de una a otra; renombra u olvida cada
  una.
- **Temas e idiomas.** Temas Claro, Oscuro, Cuarto oscuro, Papel y Cianotipia, y los 21 idiomas de
  los menús de la propia cámara.
- **Privada.** Sin cuentas, analíticas, publicidad ni informes de fallos. GR Photo solo se comunica
  con tu cámara y, para el mapa del lugar donde se tomó una foto, con OpenFreeMap; consulta la
  [política de privacidad](../../app/assets/privacy.md).

## Requisitos

- Una Ricoh GR III, GR IIIx o GR IV, incluidos los modelos HDF y la GR IV Monochrome.
- Los estilos requieren una GR IV con firmware 1.04 o posterior, una GR IV HDF o una GR IV
  Monochrome. El firmware de la GR III y la GR IIIx no ofrece ninguna forma de leer o escribir los
  ajustes de Control de imagen desde un teléfono.
- Android 12 o posterior, o iOS 15.5 o posterior.

GR Photo es un proyecto joven. El registro de pruebas con hardware recoge sesiones con una GR IV HDF
con firmware 1.20: emparejamiento, conexión, despertar la cámara, exploración, descarga, vista en
directo y cambios de enfoque y exposición. La compatibilidad con la GR III y la GR IIIx procede de
la investigación del protocolo y aún no se ha probado en una cámara. Consulta
[`research/hardware-validation.md`](../../research/hardware-validation.md) para ver lo que se ha
observado.

## Instalación

En Android, descarga `gr-photo-v<version>.apk` de la
[última versión](https://github.com/jeph/gr-photo/releases/latest) en tu teléfono y ábrelo. Android
pide una vez permiso para instalar apps desde tu navegador. Todas las versiones se firman con la
misma clave, así que una más reciente se instala sobre la que tienes y conserva tus cámaras y
ajustes.

En iOS, cada versión va a TestFlight, por ahora solo para los testers del propio proyecto. Todavía
no hay un enlace público de TestFlight, así que en un iPhone GR Photo se instala compilándola desde
el código fuente.

Compilar desde el código fuente necesita [Flutter](https://flutter.dev) 3.47 o posterior con el SDK
de Android o Xcode configurados.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` instala la app en el teléfono que esté conectado a tu ordenador. Las compilaciones
para iOS necesitan tu propio equipo de firma con las capacidades Hotspot Configuration y Access
Wi-Fi Information. Una compilación para Android hecha desde el código fuente se firma con la clave
de depuración de tu ordenador, no con la clave de publicación, así que Android no instala ninguna
de las dos sobre la otra: desinstala primero la que tienes.

Para probar la app sin una cámara, ejecútala en modo demo, que usa una GR IV simulada con fotos de
muestra y funciona en el emulador de Android y en el simulador de iOS:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Uso

1. **Empareja tu cámara.** Toca Añadir una cámara y sigue la guía. En la cámara, el emparejamiento
   está en MENU → E6 → Comunicación inalámbrica: pon Modo de acción en On, abre Emparejamiento y
   elige Ejecutar emparejamiento; después confirma el código en el teléfono y pulsa OK en la
   cámara. La cámara aparece entonces en la pantalla Cámaras, y GR Photo se enlaza con ella por sí
   solo cuando se abre con la cámara cerca.
2. **Abre la Biblioteca.** GR Photo enciende la cámara si está apagada y se conecta a su Wi-Fi.
   Android te pide aprobar la red de la cámara una vez. Toca una toma para verla, mantén pulsado
   para seleccionar varias y descarga lo que quieras conservar.
3. **Dispara.** Remoto es un disparador por Bluetooth. Vista en directo se conecta al Wi-Fi de la
   cámara y muestra su imagen, con controles de enfoque y exposición.
4. **Guarda un estilo.** Abre una foto en la Biblioteca y toca Guardar estilo, o crea uno desde
   cero con + en la página Estilos. Toca un estilo para editarlo y arrástralo a C1, C2 o C3 para
   cargarlo en la cámara.
5. **Añade la ubicación.** Activa Geoetiquetado en directo en la tarjeta de la cámara, debajo de
   Biblioteca, Disparo y Estilos. Tu teléfono pregunta si GR Photo puede usar su ubicación. A partir
   de entonces, la ubicación se envía mientras GR Photo esté en ejecución y la cámara esté encendida
   y al alcance. Geoetiquetado en segundo plano está en ⋯ en la tarjeta de la cámara, y necesita que
   la ubicación esté permitida siempre.

Desconexión automática, en Ajustes, sale del Wi-Fi de la cámara cuando GR Photo lleva un rato sin
usarse (5 minutos de forma predeterminada). [Cómo se comporta GR Photo](../behaviour.md) describe en
detalle cada pantalla y cada estado de conexión.

## Desarrollo

### Estructura

| Ruta | Contenido |
|---|---|
| `packages/gr_protocol` | BLE GATT, la API HTTP por Wi-Fi, el WebSocket de cambios y la sesión de conexión y recuperación, en Dart puro |
| `packages/gr_camera` | La capa de cámara a la que la app llama para todo lo relacionado con la cámara: adaptadores de Bluetooth y Wi-Fi (con el código en Kotlin y Swift para conectarse al Wi-Fi), sesión, emparejamiento, búsqueda, Biblioteca, Disparo y vista en directo, y la traza de cada intercambio |
| `packages/gr_fake_camera` | GR IV simulada (BLE, conexión Wi-Fi, servidor HTTP en loopback) para las pruebas y el modo demo |
| `app` | La app de Flutter, con código en Kotlin y Swift para guardar en la fototeca |
| `research` | Investigación del protocolo: cómo se encontró cada ruta y cada característica, evidencias del firmware, resultados con hardware, preguntas abiertas |
| `tool` | `check.sh`, todas las comprobaciones de calidad del código; los scripts que compilan, firman y suben una versión; `testflight.sh`, una subida para iOS desde un Mac |

### Ejecución

```sh
cd app
flutter run                                  # compilación dev, cámara real (necesita un teléfono con Bluetooth)
flutter run --profile                        # lo mismo, a la velocidad de una compilación release
flutter run --flavor prod --release          # la compilación que reciben los usuarios
flutter run --dart-define=GR_DEMO=true       # cámara simulada, funciona en el emulador de Android y el simulador de iOS
```

Hay dos compilaciones. `dev` (`io.jeph.grphoto.dev`, llamada "GR Photo Dev") se instala junto a
`prod` (`io.jeph.grphoto`, "GR Photo"). Sin `--flavor`, `flutter run` y `flutter build` compilan
`dev`.

`flutter run` a secas genera una compilación de depuración, que tarda varias veces más en generar
cada fotograma que una compilación profile o release (de 3 a 4 veces en la Biblioteca en un
emulador de Android, 2026-11-10). Valora la fluidez de una pantalla con `--profile` o `--release`.

El modo demo guarda sus datos en una carpeta `demo/` aparte. En el primer arranque, Añadir una
cámara encuentra la cámara simulada y esta confirma el emparejamiento por sí sola; los arranques
posteriores empiezan con la cámara apagada, y sigue apagada hasta que abres la Biblioteca
(despertarla forma parte de conectarse a su Wi-Fi) o pulsas el botón de encendido de la tarjeta.
Los archivos RAW de la demo son bytes JPEG con un nombre `.DNG`.

### Comprobaciones

```sh
tool/check.sh            # formateador, analizador, límite de la capa de cámara, traducciones, todas las suites de pruebas
tool/check.sh --static   # sin las pruebas
```

El analizador usa `very_good_analysis` con los avisos de tipo info tratados como errores. Las
compilaciones de Android e iOS ejecutan primero `tool/check.sh --static` y se detienen si falla.
Las advertencias de Kotlin y Swift son errores. Consulta [`AGENTS.md`](../../AGENTS.md) para ver
las reglas.

### Pruebas

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

La prueba de integración ejecuta todo el flujo de la demo (emparejar, conectar, explorar, descargar
dos tomas) en un dispositivo, emulador o simulador. Una compilación de depuración necesita unos
400 MB libres en el emulador. En Android, `flutter test` no toma del proyecto ni el flavor
predeterminado ni el ID de la app, así que necesita `--flavor dev` y un APK compilado de antemano;
sin ellos se detiene con "No application found".

En el simulador de iOS, la app debe estar instalada cuando se concede el acceso a Fotos, y
`flutter test` la desinstala después, lo que borra el permiso. GR Photo pide acceso completo, para
mantener su álbum, y en el simulador de iOS 26.3 `simctl privacy grant photos` por sí solo no
impidió que iOS preguntara: el permiso que registra tiene `auth_version` 1, e iOS solo lo toma como
acceso completo con 2. Concédelo y fija ese valor antes de cada ejecución:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Registro de depuración

GR Photo guarda registros de depuración mientras Ajustes > Activar registro de depuración está
activado: todo lo que envía a la cámara y recibe de ella (búsquedas, lecturas, escrituras y
notificaciones de Bluetooth, cada petición y respuesta HTTP, los mensajes de WebSocket, los tamaños
de los fotogramas de la vista en directo y los pasos de la conexión al Wi-Fi), cada línea que
imprime la app, los errores no capturados y las líneas del código nativo de Wi-Fi. El ajuste está
activado de forma predeterminada en `dev` y desactivado en `prod`. Mientras está desactivado no se
registra nada, ni siquiera en logcat o en la consola, con una excepción: el motor de Flutter sigue
informando ahí por su cuenta de los errores no capturados, así que los fallos siguen siendo
visibles. Ajustes > Registro de depuración exporta el registro mediante la hoja para compartir
como archivos JSON Lines y lo borra. El registro conserva unos 50 MB. Contiene la contraseña del
Wi-Fi de la cámara.

### Versiones

Cada push a `main` es una versión, creada por
[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Numera la versión 0.0.N,
una más que la anterior, ejecuta `tool/check.sh` y compila el flavor `prod` de ambas apps en modo
release. El APK de Android se firma con la clave de publicación de GR Photo y se publica en la
[página de versiones](https://github.com/jeph/gr-photo/releases) con su suma de comprobación
SHA-256, una atestación de procedencia de la compilación y el mapeo de R8 que permite leer sus
trazas de pila de Kotlin. La app para iOS se firma para el App Store y se sube a TestFlight. Las
claves se guardan en entornos de GitHub que solo `main` puede usar, y los jobs que compilan las apps
no tienen ninguna.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` comprueba que un APK fue
compilado por ese workflow a partir de este repositorio.

```sh
tool/testflight.sh       # compila la app prod para iOS y la sube a TestFlight
```

El script pone en TestFlight, desde un Mac, una compilación que no es una versión. Compila el
flavor `prod` con la hora de la subida como número de compilación y lo envía a
App Store Connect, donde aparece en TestFlight una vez procesado. Los testers internos lo instalan
desde la app TestFlight, sin cable. Xcode firma y sube la compilación con una clave de API de App
Store Connect, así que la configuración en un Mac consiste en el archivo `AuthKey_<key id>.p8` de
la clave en `~/.appstoreconnect/private_keys`, y `ASC_KEY_ID` y `ASC_ISSUER_ID` en
`~/.appstoreconnect/gr-photo.env`. La clave necesita el rol Administrador: Apple no permite que una
clave de Gestor de apps use el certificado de distribución del equipo. El archivo se compila sin
firmar y se firma para el App Store al exportarlo (`app/ios/ExportOptions.plist`), porque firmar el
propio archivo requeriría un dispositivo de prueba registrado en el equipo.

## Contribuir

Los informes de errores y las pull requests son bienvenidos. La mayoría de los errores solo
aparecen con hardware real, así que cuando
[abras una incidencia](https://github.com/jeph/gr-photo/issues), incluye el modelo de tu cámara y la
versión de su firmware, el modelo de tu teléfono y su versión de Android o iOS, y lo que hiciste.
Un registro de depuración exportado (Ajustes, Registro de depuración, Exportar registro) suele
mostrar lo que ocurrió, pero contiene el número de serie y la contraseña del Wi-Fi de tu cámara,
así que adjúntalo solo si no te importa compartirlos.

Antes de enviar un cambio, ejecuta `tool/check.sh`; todas las comprobaciones deben pasar.
[`AGENTS.md`](../../AGENTS.md) describe cómo está organizado el código y las reglas que sigue.

No informes de posibles vulnerabilidades de seguridad en incidencias públicas. Sigue la
[política de seguridad](../../.github/SECURITY.md) para enviar un informe de vulnerabilidad privado.

## Agradecimientos

GR Photo está creada con [Flutter](https://flutter.dev) y usa
[universal_ble](https://pub.dev/packages/universal_ble) para Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) y
[path_provider](https://pub.dev/packages/path_provider). Su texto está compuesto en
[Inter](https://rsms.me/inter/) y [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

La investigación del protocolo se apoya en las apps GR WORLD e Image Sync de Ricoh y en el firmware
de las GR, y en las notas del proyecto [Ricoh3x](https://github.com/Trimz/Ricoh3x) sobre los
ajustes de Control de imagen de la GR IIIx.

## Licencia

GR Photo se publica bajo la [licencia MIT](../../LICENSE). Los paquetes y las fuentes de terceros
que incluye GR Photo conservan sus propias licencias. La app los enumera en **Ajustes › Acerca de ›
Licencias**, y los textos de las licencias de las fuentes están en
[`app/assets/fonts/`](../../app/assets/fonts/).

Las fotos de muestra del modo demo proceden de [Unsplash](https://unsplash.com) y se usan bajo la
[licencia de Unsplash](https://unsplash.com/license), no bajo la licencia MIT;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) las enumera junto con sus
fotógrafos.

Las apps y el firmware de Ricoh, que la investigación cita, pertenecen a Ricoh y no forman parte de
este repositorio.
