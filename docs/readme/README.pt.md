<p align="center">
  <img src="../icon.png" alt="Ícone do GR Lab" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licença: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Plataformas: iOS e Android">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <b>Português</b> ·
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

O **GR Lab** é uma app complementar para as câmaras Ricoh GR (GR III, GR IIIx e GR IV), para iOS e
Android. Permite ver e transferir as fotos que estão na câmara, funciona como disparador remoto com
vista ao vivo e guarda os seus estilos de Controlo de Imagem num só lugar. Foi feito para ser rápido
e fácil de utilizar, e para gerir a sério os perfis de cor da câmara: guarde o estilo com que uma
foto foi tirada, edite-o com uma pré-visualização e carregue-o nos espaços Personalizado da câmara.

O GR Lab é um projeto independente e não está afiliado à Ricoh. Comunica com a câmara através de um
protocolo obtido por engenharia inversa das apps da própria Ricoh e do firmware da câmara; as
conclusões estão documentadas em [`research/`](../../research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="A Biblioteca: as fotos da câmara por dia, com filtros para JPEG, RAW e vídeo" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="A página Estilos: os três espaços Personalizado da câmara por cima dos estilos guardados no telemóvel" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="O editor de estilos: uma pré-visualização do antes e do depois por cima dos controlos deslizantes do Controlo de Imagem" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Vista ao vivo: a imagem da câmara com os valores de exposição e o obturador" height="400">
</p>

<p align="center">
  <sub>Biblioteca, Estilos, o editor de estilos e a vista ao vivo, em modo de demonstração com a câmara simulada.</sub>
</p>

## Índice

- [Funcionalidades](#funcionalidades)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Utilização](#utilização)
- [Desenvolvimento](#desenvolvimento)
- [Contribuir](#contribuir)
- [Agradecimentos](#agradecimentos)
- [Licença](#licença)

## Funcionalidades

O GR Lab dá prioridade a três coisas: chegar depressa às suas fotos, não atrapalhar e tratar os
estilos de Controlo de Imagem como algo que merece ser gerido.

- **Rápido.** Ao abrir, o GR Lab liga-se à câmara por Bluetooth, se ela estiver por perto. Abrir a
  Biblioteca desperta a câmara, ativa o Wi-Fi dela e liga-se a ele de uma só vez, e o Wi-Fi
  mantém-se depois ativo enquanto muda de página, pelo que nada se liga duas vezes e uma
  transferência continua. As listas de ficheiros, as miniaturas e as pré-visualizações ficam em
  cache no telemóvel, para que a Biblioteca abra depressa. Numa GR IV HDF com um telemóvel Android,
  uma câmara desligada chegou à Biblioteca em cerca de 13 segundos.
- **Fácil de utilizar.** Um único ecrã reúne as suas câmaras, e Biblioteca, Disparar e Estilos
  estão a um toque de distância. O GR Lab liga a câmara, ativa o Wi-Fi dela e liga-se a ele por si,
  pelo que não há nada a configurar na câmara depois do emparelhamento. Quando algo falha, diz
  porquê e o que verificar, com Tentar novamente. Uma ligação que cai restabelece-se sozinha.
- **Estilos que pode gerir.** Cada foto da Biblioteca mostra o Controlo de Imagem com que foi
  tirada, e um toque guarda-o como estilo. Os estilos ficam no telemóvel, seja qual for a câmara de
  onde vieram, com as suas definições, a foto de onde vieram e uma etiqueta com o espaço
  Personalizado que os contém.
- **Um editor de estilos com pré-visualização.** Altere a imagem de base e todos os parâmetros que
  ela tem, agrupados em Tom, Cor, Detalhe e Efeitos, e veja o resultado na sua própria foto ou numa
  de exemplo: deslize uma divisória entre o antes e o depois, ponha-os lado a lado ou toque para
  alternar. A pré-visualização aproxima-se do processamento da câmara, deduzido a partir do firmware
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Carregar estilos na câmara.** A página Estilos mostra o que os espaços Personalizado C1 a C3 da
  câmara contêm. Arraste um estilo guardado para um espaço, ou escolha Carregar no menu dele, e a
  câmara fica com ele. A leitura e o carregamento dos espaços funcionam só por Bluetooth, sem ligar
  ao Wi-Fi da câmara.
- **Biblioteca.** Percorra as fotos e os vídeos da câmara por dia, filtre por JPEG, RAW, vídeo ou
  por transferir e abra qualquer foto em ecrã inteiro com os respetivos detalhes. Transfira uma foto
  ou uma seleção, em JPEG, RAW ou ambos, para um álbum GR Lab na biblioteca de fotografias do
  telemóvel. As transferências continuam enquanto usa outra app ou bloqueia o telemóvel: o Android
  mostra-as numa notificação com Pausar e Cancelar tudo, e o iOS 26 ou posterior mostra o progresso
  no ecrã bloqueado e na Dynamic Island. Os vídeos são reproduzidos na app.
- **Disparador remoto.** Um botão de obturador grande, só por Bluetooth, com o temporizador
  automático, o modo de fotografar, o seletor de modo, as fotos restantes e a bateria. No Android,
  os botões de volume também disparam o obturador.
- **Vista ao vivo.** A imagem da câmara por Wi-Fi: toque para focar, defina a abertura, a
  velocidade de obturação, o ISO e a compensação da exposição num seletor com os valores que a
  câmara oferece, e altere o modo de fotografar, o temporizador automático, a medição e o Controlo
  de Imagem.
- **Várias câmaras.** Emparelhe todas as que tiver e alterne entre elas; mude o nome ou esqueça
  cada uma.
- **Temas e idiomas.** Temas Claro, Escuro, Câmara escura, Papel e Cianotipia, e os 21 idiomas dos
  menus da própria câmara.
- **Privado.** Sem contas, análise de dados, publicidade nem relatórios de falhas. O GR Lab
  comunica apenas com a sua câmara; consulte a [política de privacidade](../../app/assets/privacy.md).

## Requisitos

- Uma Ricoh GR III, GR IIIx ou GR IV, incluindo os modelos HDF e a GR IV Monochrome.
- Os Estilos precisam de uma GR IV com o firmware 1.04 ou posterior, de uma GR IV HDF ou de uma
  GR IV Monochrome. O firmware da GR III e da GR IIIx não oferece forma de ler ou gravar as
  definições de Controlo de Imagem a partir de um telemóvel.
- Android 12 ou posterior, ou iOS 15 ou posterior.

O GR Lab é recente. O registo de hardware documenta testes com uma GR IV HDF com o firmware 1.20:
emparelhar, ligar, despertar a câmara, percorrer as fotos, transferir, vista ao vivo e alterações de
foco e de exposição. O suporte para a GR III e a GR IIIx resulta da investigação do protocolo e
ainda não foi testado numa câmara. Consulte
[`research/hardware-validation.md`](../../research/hardware-validation.md) para saber o que foi
observado.

## Instalação

Ainda não há versões empacotadas, pelo que o GR Lab se instala compilando-o a partir do código-fonte.
A compilação precisa do [Flutter](https://flutter.dev) 3.47 ou posterior, com o Android SDK ou o
Xcode configurado.

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

O `flutter run` instala a app no telemóvel que estiver ligado ao computador. As compilações para iOS
precisam da sua própria equipa de assinatura, com as capacidades Hotspot Configuration e Access
Wi-Fi Information.

Para experimentar a app sem câmara, execute-a em modo de demonstração, que utiliza uma GR IV
simulada com fotos de exemplo e funciona no emulador de Android e no simulador de iOS:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Utilização

1. **Emparelhe a câmara.** Toque em Adicionar câmara e siga o guia. Na câmara, o emparelhamento
   está em MENU, E6, Comunicação sem fios: defina Modo de Ação para Ligar, abra Emparelhamento e
   escolha Executar Emparelhamento; depois confirme o código no telemóvel e prima OK na câmara. A
   câmara passa então a constar do ecrã Câmaras, e o GR Lab liga-se a ela sozinho quando é aberto
   com a câmara por perto.
2. **Abra a Biblioteca.** O GR Lab liga a câmara, se estiver desligada, e liga-se ao Wi-Fi dela. O
   Android pede-lhe que aprove uma vez a rede da câmara. Toque numa foto para a ver, mantenha
   premido para selecionar várias e transfira as que quiser guardar.
3. **Dispare.** Remoto é um obturador por Bluetooth. Vista ao vivo liga-se ao Wi-Fi da câmara e
   mostra a imagem dela, com controlos de foco e de exposição.
4. **Guarde um estilo.** Abra uma foto na Biblioteca e toque em Guardar estilo, ou crie um de raiz
   com + na página Estilos. Toque num estilo para o editar e arraste-o para C1, C2 ou C3 para o
   carregar na câmara.

Desligar automaticamente, nas Definições, sai do Wi-Fi da câmara depois de o GR Lab estar algum
tempo sem ser utilizado (5 minutos por predefinição). [Como se comporta o GR Lab](../behaviour.md)
descreve em pormenor cada ecrã e cada estado de ligação.

## Desenvolvimento

### Estrutura

| Caminho | Conteúdo |
|---|---|
| `packages/gr_protocol` | BLE GATT, API HTTP por Wi-Fi, WebSocket de alterações e a sessão de ligação/recuperação, em Dart puro |
| `packages/gr_camera` | A camada de câmara a que a app recorre para tudo o que diz respeito à câmara: adaptadores de Bluetooth e Wi-Fi (com o código Kotlin e Swift de ligação ao Wi-Fi), sessão, emparelhamento, procura, Biblioteca, Disparar e vista ao vivo, e rastreio de todas as trocas |
| `packages/gr_fake_camera` | GR IV simulada (BLE, ligação ao Wi-Fi, servidor HTTP em loopback) para os testes e o modo de demonstração |
| `app` | A app Flutter, com código Kotlin e Swift para guardar na biblioteca de fotografias |
| `research` | Investigação do protocolo: como se descobriu cada rota e cada característica, provas do firmware, resultados em hardware, questões em aberto |
| `tool` | `check.sh`, todas as verificações de qualidade do código; `testflight.sh`, o envio para iOS |

### Execução

```sh
cd app
flutter run                                  # compilação dev, câmara real (precisa de um telemóvel com Bluetooth)
flutter run --profile                        # o mesmo, à velocidade de uma compilação de release
flutter run --flavor prod --release          # a compilação que os utilizadores recebem
flutter run --dart-define=GR_DEMO=true       # câmara simulada, funciona no emulador de Android e no simulador de iOS
```

Há duas compilações. A `dev` (`io.jeph.grlab.dev`, com o nome "GR Lab Dev") instala-se ao lado da
`prod` (`io.jeph.grlab`, "GR Lab"). Sem `--flavor`, o `flutter run` e o `flutter build` compilam a
`dev`.

O `flutter run` sozinho faz uma compilação de depuração, que gera cada fotograma várias vezes mais
devagar do que uma compilação de profile ou de release (3 a 4 vezes na Biblioteca num emulador de
Android, 2026-11-10). Avalie a fluidez de um ecrã com `--profile` ou `--release`.

O modo de demonstração guarda os seus dados numa pasta `demo/` separada. No primeiro arranque,
Adicionar câmara encontra a câmara simulada e esta confirma o emparelhamento sozinha; nos arranques
seguintes a câmara começa desligada e assim fica até abrir a Biblioteca (despertá-la faz parte da
ligação ao Wi-Fi dela) ou premir o botão de alimentação do cartão. Os ficheiros RAW de demonstração
são bytes JPEG com um nome `.DNG`.

### Verificações

```sh
tool/check.sh            # formatador, analisador, limite da camada de câmara, traduções, todos os conjuntos de testes
tool/check.sh --static   # sem os testes
```

O analisador utiliza o `very_good_analysis` com as informações tratadas como erros. As compilações
para Android e iOS executam primeiro `tool/check.sh --static` e param se este falhar. Os avisos de
Kotlin e Swift são erros. Consulte as regras em [`AGENTS.md`](../../AGENTS.md).

### Testes

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

O teste de integração percorre todo o fluxo de demonstração (emparelhar, ligar, percorrer as fotos,
transferir duas fotos) num dispositivo, emulador ou simulador. Uma compilação de depuração precisa
de cerca de 400 MB livres no emulador. No Android, o `flutter test` não vai buscar ao projeto nem o
flavor predefinido nem o ID da app, pelo que precisa de `--flavor dev` e de um APK compilado
previamente; sem eles, para com "No application found".

No simulador de iOS, a app tem de estar instalada quando se concede o acesso às Fotografias, e o
`flutter test` desinstala-a no fim, o que apaga a autorização. O GR Lab pede acesso total, para
manter o seu álbum, e no simulador de iOS 26.3 o `simctl privacy grant photos` sozinho não impediu
o iOS de perguntar: a autorização que regista tem `auth_version` 1, e o iOS só a considera acesso
total com 2. Conceda-a e defina esse valor antes de cada execução:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Registo de depuração

O GR Lab guarda registos de depuração enquanto Definições > Ativar registo de depuração estiver
ativo: tudo o que envia para a câmara e dela recebe (procuras, leituras, escritas e notificações
Bluetooth, todos os pedidos e respostas HTTP, mensagens WebSocket, tamanhos dos fotogramas da vista
ao vivo e os passos da ligação ao Wi-Fi), todas as linhas que a app imprime, os erros não
capturados e as linhas do código nativo de Wi-Fi. A definição está ativa por predefinição na `dev`
e desativada na `prod`. Enquanto estiver desativada nada é registado, nem sequer no logcat ou na
consola, com uma exceção: o próprio motor do Flutter continua a comunicar aí os erros não
capturados, pelo que as falhas continuam visíveis. Definições > Registo de depuração exporta o
registo através da folha de partilha, em ficheiros JSON Lines, e limpa-o. O registo guarda cerca de
50 MB. Contém a palavra-passe do Wi-Fi da câmara.

### TestFlight

```sh
tool/testflight.sh       # compila a app iOS prod e envia-a para o TestFlight
```

O script compila o flavor `prod` com a hora do envio como número de compilação e envia-o para o App
Store Connect, onde aparece em TestFlight depois de processado. Os testadores internos instalam-no
a partir da app TestFlight, sem cabo. O Xcode assina e envia a compilação com uma chave de API do
App Store Connect, pelo que a configuração num Mac consiste no ficheiro `AuthKey_<key id>.p8` da
chave em `~/.appstoreconnect/private_keys`, e em `ASC_KEY_ID` e `ASC_ISSUER_ID` em
`~/.appstoreconnect/gr-lab.env`. A chave precisa da função Admin: a Apple não deixa uma chave de
App Manager utilizar o certificado de distribuição da equipa. O arquivo é compilado sem assinatura
e assinado para a App Store na exportação (`app/ios/ExportOptions.plist`), porque assinar o próprio
arquivo exigiria um dispositivo de teste registado na equipa.

## Contribuir

Os relatórios de erros e os pull requests são bem-vindos. A maioria dos erros só se manifesta em
hardware real, por isso, quando [abrir uma issue](https://github.com/jeph/gr-lab/issues), indique o
modelo da câmara e a versão do firmware, o modelo do telemóvel e a respetiva versão do Android ou
do iOS, e o que fez. Um registo de depuração exportado (Definições, Registo de depuração, Exportar
registo) costuma mostrar o que aconteceu, mas contém o número de série e a palavra-passe do Wi-Fi
da sua câmara, pelo que só o deve anexar se não se importar de os partilhar.

Antes de enviar uma alteração, execute `tool/check.sh`; todas as verificações têm de passar. O
[`AGENTS.md`](../../AGENTS.md) descreve como o código está organizado e as regras que segue.

Não comunique suspeitas de vulnerabilidades de segurança em issues públicas. Siga a
[política de segurança](../../.github/SECURITY.md) para enviar um relatório de vulnerabilidade
privado.

## Agradecimentos

O GR Lab é feito com [Flutter](https://flutter.dev) e utiliza o
[universal_ble](https://pub.dev/packages/universal_ble) para o Bluetooth, o
[image](https://pub.dev/packages/image), o [video_player](https://pub.dev/packages/video_player),
o [share_plus](https://pub.dev/packages/share_plus) e o
[path_provider](https://pub.dev/packages/path_provider). O texto é composto em
[Inter](https://rsms.me/inter/) e [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

A investigação do protocolo assenta nas apps GR WORLD e Image Sync da Ricoh e no firmware das GR, e
nas notas do projeto [Ricoh3x](https://github.com/Trimz/Ricoh3x) sobre as definições de Controlo de
Imagem da GR IIIx.

## Licença

O GR Lab é disponibilizado ao abrigo da [Licença MIT](../../LICENSE). Os pacotes e os tipos de
letra de terceiros que o GR Lab inclui mantêm as suas próprias licenças. A app apresenta-os em
**Definições › Acerca › Licenças**, e os textos das licenças dos tipos de letra estão em
[`app/assets/fonts/`](../../app/assets/fonts/).

As apps e o firmware da Ricoh, que a investigação cita, pertencem à Ricoh e não fazem parte deste
repositório.
