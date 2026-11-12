<p align="center">
  <img src="../icon.png" alt="GR Photoのアイコン" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="ライセンス: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="対応プラットフォーム: iOSとAndroid">
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
  <a href="README.hu.md">Magyar</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.el.md">Ελληνικά</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.th.md">ไทย</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.zh.md">中文简体</a> ·
  <a href="README.zh-Hant.md">中文繁體</a> ·
  <b>日本語</b>
</p>

**GR Photo** は、Ricoh GRカメラ（GR III、GR IIIx、GR IV）のためのiOS・Android向けコンパニオンアプリです。カメラ内の写真を閲覧してダウンロードでき、ライブビュー付きのリモートシャッターとして使え、イメージコントロールのルックをひとつの場所にまとめておけます。速く、使いやすく、そしてカメラのカラープロファイルをきちんと管理できるように作られています。写真の撮影時のルックを保存し、プレビューを見ながら編集して、カメラのカスタムスロットに登録できます。

GR Photoは独立したプロジェクトであり、Ricohとの提携関係はありません。カメラとの通信には、Ricoh純正アプリとカメラのファームウェアをリバースエンジニアリングして得たプロトコルを使っています。調査結果は[`research/`](../../research/README.md)にまとめてあります。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="ライブラリ: カメラ内の写真を日付ごとに表示し、JPEG、RAW、動画で絞り込めます" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="ルックのページ: カメラの3つのカスタムスロットが上に、スマートフォンに保存したルックがその下に並びます" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="ルックエディター: 適用前と適用後のプレビューの下に、イメージコントロールのスライダーが並びます" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="ライブビュー: カメラの映像に露出の表示とシャッターボタンが重なります" height="400">
</p>

<p align="center">
  <sub>ライブラリ、ルック、ルックエディター、ライブビュー。シミュレートしたカメラを使うデモモードでの画面です。</sub>
</p>

## 目次

- [機能](#機能)
- [動作要件](#動作要件)
- [インストール](#インストール)
- [使い方](#使い方)
- [開発](#開発)
- [コントリビューション](#コントリビューション)
- [謝辞](#謝辞)
- [ライセンス](#ライセンス)

## 機能

GR Photoが何より大切にしているのは、写真にすばやくたどり着けること、操作の邪魔をしないこと、そしてイメージコントロールのルックを管理する価値のあるものとして扱うことの3つです。

- **高速**：カメラが近くにあれば、GR Photoは起動時にBluetoothでカメラとつながります。ライブラリを開くと、カメラの起動、Wi-Fiのオン、その接続までを一度に行います。Wi-Fiはページを移動しても接続されたままなので、接続し直すことはなく、ダウンロードもそのまま続きます。ファイル一覧、サムネイル、プレビューはスマートフォンにキャッシュされるため、ライブラリはすぐに開きます。GR IV HDFとAndroidスマートフォンの組み合わせでは、電源オフの状態からライブラリが表示されるまで約13秒でした。
- **使いやすい**：カメラはひとつの画面にまとまっていて、そこからライブラリ、撮影、ルックへワンタップで移れます。カメラの電源を入れ、Wi-Fiをオンにして接続するところまでGR Photoが行うので、ペアリング後にカメラ側で設定することはありません。何かが失敗したときは、その理由と確認すべき点を「再試行」とともに表示します。接続が切れても、自動で復帰します。
- **管理できるルック**：ライブラリの写真にはそれぞれ撮影時のイメージコントロールが表示され、ワンタップでルックとして保存できます。ルックは、どのカメラのものであってもスマートフォンに保存され、設定内容、元になった写真、登録先のカスタムスロットを示すタグも一緒に残ります。
- **プレビュー付きのルックエディター**：ベースとなるイメージコントロールと、そのすべてのパラメーターを変更できます。パラメーターはトーン、カラー、ディテール、効果に分けられています。結果は自分の写真かサンプル写真で確認でき、適用前と適用後の境界線をスライドさせる、並べて表示する、タップで切り替える、のいずれかで比べられます。プレビューは、ファームウェアを解析して求めた、カメラの画作りの近似です（[`research/image-control-processing.md`](../../research/image-control-processing.md)）。
- **ルックをカメラに登録**：ルックのページには、カメラのカスタムスロットC1からC3の内容が表示されます。保存したルックをスロットにドラッグするか、ルックのメニューから登録を選ぶと、カメラに書き込まれます。スロットの読み込みと登録はBluetoothだけで行え、カメラのWi-Fiに接続する必要はありません。
- **ライブラリ**：カメラ内の写真と動画を日付ごとに閲覧し、JPEG、RAW、動画、未ダウンロードで絞り込めます。どのカットも、詳細情報とともに全画面で表示できます。1枚だけでも、選択した複数枚でも、JPEG、RAW、またはその両方を、スマートフォンの写真ライブラリのGR Photoアルバムにダウンロードできます。ほかのアプリを使っている間やスマートフォンをロックしている間もダウンロードは続きます。Androidでは「一時停止」と「すべてキャンセル」の付いた通知に、iOS 26以降ではロック画面とDynamic Islandに進行状況が表示されます。動画はアプリ内で再生できます。
- **リモートシャッター**：Bluetoothだけで使える大きなシャッターボタンに、セルフタイマー、ドライブモード、モードダイヤル、残り枚数、バッテリーの表示が付きます。Androidでは音量ボタンでもシャッターを切れます。
- **ライブビュー**：カメラの映像をWi-Fi経由で表示します。タップでピントを合わせ、絞り、シャッタースピード、ISO、露出補正を、カメラが選べる値だけが並ぶダイヤルで設定できます。ドライブ、セルフタイマー、測光モード、イメージコントロールも変更できます。
- **ジオタグ**：GRにはGPSがありません。カメラの「ジオタグ」をオンにしておくと、カメラの電源が入っている間、GR Photoがスマートフォンの位置情報をBluetoothでカメラに送り、カメラがそれを写真ごとに記録します。ほかのアプリを使っている間やスマートフォンをロックしている間も続き、位置情報を「常に許可」にしておけばカメラの電源を入れたときに自動で開始します。カメラの時計もスマートフォンの時刻に合わせます。「バックグラウンドジオタグ」は、手間のかからないもうひとつの方法です。スマートフォンが移動した場所の履歴を90日間保存し、写真をダウンロードするときに、撮影時刻に最も近い時点で記録された場所をGR Photoが追加します。JPEGにもRAWにも追加されます。
- **複数のカメラ**：お持ちのカメラを何台でもペアリングして切り替えられます。カメラごとに名前の変更や登録の解除ができます。
- **テーマと言語**：テーマはライト、ダーク、暗室、印画紙、サイアノタイプの5種類。言語は、カメラ本体のメニューと同じ21言語に対応しています。
- **プライバシー**：アカウント、アクセス解析、広告、クラッシュレポートはありません。GR Photoが通信する相手はお使いのカメラだけで、位置情報の送り先もお使いのカメラとご自身の写真だけです。詳しくは[プライバシーポリシー](../../app/assets/privacy.md)をご覧ください。

## 動作要件

- Ricoh GR III、GR IIIx、GR IVのいずれか。HDFモデルとGR IV Monochromeを含みます。
- ルックを使うには、ファームウェア1.04以降のGR IV、GR IV HDF、またはGR IV Monochromeが必要です。GR IIIとGR IIIxのファームウェアには、スマートフォンからイメージコントロールの設定を読み書きする手段がありません。
- Android 12以降、またはiOS 15以降。

GR Photoはまだ新しいアプリです。実機ログに記録されているのは、ファームウェア1.20のGR IV HDFでの動作で、ペアリング、接続、カメラの起動、閲覧、ダウンロード、ライブビュー、ピントと露出の変更を確認しています。GR IIIとGR IIIxへの対応はプロトコルの調査に基づくもので、実機ではまだテストしていません。確認できている内容は[`research/hardware-validation.md`](../../research/hardware-validation.md)をご覧ください。

## インストール

Androidでは、スマートフォンで[最新のリリース](https://github.com/jeph/gr-photo/releases/latest)から`gr-photo-v<version>.apk`をダウンロードして開きます。Androidから、ブラウザーからのアプリのインストールを許可するよう一度だけ求められます。どのリリースも同じキーで署名されているため、新しいリリースはインストール済みのものに上書きでインストールされ、カメラと設定はそのまま残ります。

iOSでは、どのリリースもTestFlightに送られますが、今のところ対象はプロジェクト自身のテスターだけです。公開のTestFlightリンクはまだないため、iPhoneではGR Photoをソースからビルドしてインストールします。

ソースからのビルドには[Flutter](https://flutter.dev) 3.47以降と、セットアップ済みのAndroid SDKまたはXcodeが必要です。

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run`は、コンピューターに接続されているスマートフォンにアプリをインストールします。iOS向けのビルドには、Hotspot ConfigurationとAccess Wi-Fi Informationのケイパビリティを持つ、ご自身の署名チームが必要です。ソースからビルドしたAndroid向けのビルドは、リリース用のキーではなくお使いのコンピューターのデバッグキーで署名されるため、Androidではどちらも他方に上書きしてインストールすることはできません。先にインストール済みのものをアンインストールしてください。

カメラなしでアプリを試すには、デモモードで実行します。デモモードはサンプル写真の入ったシミュレートされたGR IVを使い、AndroidエミュレーターとiOSシミュレーターで動作します。

```sh
flutter run --dart-define=GR_DEMO=true
```

## 使い方

1. **カメラをペアリングする**：「カメラを追加」をタップし、ガイドに従います。カメラ側では、MENU → E6 → 無線通信設定で「動作モード」を「オン」にし、「ペアリング」を開いて「ペアリング実行」を選びます。続いてスマートフォンでコードを確認し、カメラのOKボタンを押します。これでカメラが「カメラ」画面に表示され、以降はカメラが近くにある状態でGR Photoを開くと自動でつながります。
2. **ライブラリを開く**：カメラの電源がオフならGR Photoが電源を入れ、カメラのWi-Fiに接続します。Androidでは、カメラのネットワークの承認を一度だけ求められます。写真をタップすると表示され、長押しすると複数選択できます。残しておきたいものをダウンロードしてください。
3. **撮影する**：「リモート」はBluetooth経由のシャッターです。「ライブビュー」はカメラのWi-Fiに接続してカメラの映像を表示し、ピントと露出を操作できます。
4. **ルックを保存する**：ライブラリで写真を開いて「ルックを保存」をタップするか、ルックのページの+で一から作成します。ルックをタップすると編集でき、C1、C2、C3のいずれかにドラッグするとカメラに登録できます。
5. **位置情報を追加する**：GR Photoは、カメラごとに一度だけ「ジオタグ」をオンにするかどうかを尋ねます。あとからカメラのカードの「⋯」からオンにすることもできます。GR Photoに位置情報の使用を許可するかどうかを、スマートフォンが確認します。それ以降は、カメラの電源が入っていて通信できる範囲にあれば、位置情報が送られます。「バックグラウンドジオタグ」は「設定」の「位置情報」にあり、位置情報を「常に許可」にする必要があります。

「設定」の「自動切断」は、GR Photoがしばらく使われないと（初期設定では5分）カメラのWi-Fiから切断します。各画面とすべての接続状態については、[GR Photoの動作](../behaviour.md)で詳しく説明しています。

## 開発

### 構成

| パス | 内容 |
|---|---|
| `packages/gr_protocol` | BLE GATT、Wi-Fi HTTP API、変更通知のWebSocket、接続と復旧を担うセッション。純粋なDartで実装 |
| `packages/gr_camera` | カメラに関するあらゆる処理でアプリが呼び出すカメラ層。BluetoothとWi-Fiのアダプター（KotlinとSwiftによるWi-Fi接続コードを含む）、セッション、ペアリング、スキャン、ライブラリ、撮影、ライブビュー、すべての通信のトレース |
| `packages/gr_fake_camera` | テストとデモモード用のシミュレートされたGR IV（BLE、Wi-Fi接続、ループバック上のHTTPサーバー） |
| `app` | Flutterアプリ。写真ライブラリに保存するためのKotlinとSwiftのコードを含む |
| `research` | プロトコルの調査。各ルートとキャラクタリスティックをどう見つけたか、ファームウェアからの根拠、実機での結果、未解決の疑問 |
| `tool` | `check.sh`: コード品質のすべてのチェック。リリースをビルドし、署名してアップロードするスクリプト。`testflight.sh`: MacからのiOSアプリのアップロード |

### 実行

```sh
cd app
flutter run                                  # devビルド、実機のカメラ（Bluetooth対応のスマートフォンが必要）
flutter run --profile                        # 同じ構成で、リリースビルド並みの速度
flutter run --flavor prod --release          # ユーザーに届くビルド
flutter run --dart-define=GR_DEMO=true       # シミュレートされたカメラ。AndroidエミュレーターとiOSシミュレーターで動作
```

ビルドは2種類あります。`dev`（`io.jeph.grphoto.dev`、名前は「GR Photo Dev」）は、`prod`（`io.jeph.grphoto`、「GR Photo」）と並べてインストールできます。`--flavor`を付けない場合、`flutter run`と`flutter build`は`dev`をビルドします。

`flutter run`だけではデバッグビルドになり、各フレームの描画がプロファイルビルドやリリースビルドより数倍遅くなります（Androidエミュレーター上のライブラリで3〜4倍、2026-11-10時点）。画面の滑らかさは`--profile`か`--release`で判断してください。

デモモードは、データを別の`demo/`フォルダに保存します。初回起動時は、「カメラを追加」でシミュレートされたカメラが見つかり、ペアリングの確認もカメラ側で自動的に行われます。2回目以降はカメラの電源がオフの状態で始まり、ライブラリを開く（カメラの起動はWi-Fi接続の一部です）か、カードの電源ボタンを押すまでオフのままです。デモのRAWファイルは、`.DNG`という名前を付けたJPEGのバイト列です。

### チェック

```sh
tool/check.sh            # フォーマッター、アナライザー、カメラ層の境界、翻訳、すべてのテストスイート
tool/check.sh --static   # テストを除く
```

アナライザーは`very_good_analysis`を使い、infoもエラーとして扱います。AndroidとiOSのビルドは最初に`tool/check.sh --static`を実行し、失敗すればそこで止まります。KotlinとSwiftの警告もエラーになります。ルールは[`AGENTS.md`](../../AGENTS.md)をご覧ください。

### テスト

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

インテグレーションテストは、デモの流れ全体（ペアリング、接続、閲覧、2枚のダウンロード）を実機、エミュレーター、またはシミュレーターで実行します。デバッグビルドには、エミュレーターに約400 MBの空き容量が必要です。Androidでは、`flutter test`がデフォルトのフレーバーもアプリのIDもプロジェクトから取得しないため、`--flavor dev`と事前にビルドしたAPKが必要です。これらがないと「No application found」で止まります。

iOSシミュレーターでは、写真へのアクセスを許可する時点でアプリがインストールされている必要がありますが、`flutter test`は終了後にアプリをアンインストールするため、許可も消えてしまいます。GR Photoはアルバムを維持するためにフルアクセスを求めますが、iOS 26.3のシミュレーターでは`simctl privacy grant photos`だけではiOSの確認ダイアログを止められませんでした。このコマンドが記録する許可は`auth_version`が1で、iOSがフルアクセスとみなすのは2の場合だけだからです。実行のたびに、事前に許可を与えてこの値を設定してください。

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### デバッグログ

GR Photoは、設定 > 「デバッグログを有効にする」がオンの間、デバッグログを記録します。記録されるのは、カメラとの間で送受信するすべての内容（Bluetoothのスキャン、読み取り、書き込み、通知、すべてのHTTPリクエストと応答、WebSocketのメッセージ、ライブビューのフレームサイズ、Wi-Fi接続の各ステップ）、アプリが出力するすべての行、捕捉されなかったエラー、ネイティブのWi-Fiコードが出力する行です。この設定は`dev`では初期状態でオン、`prod`ではオフです。オフの間は、logcatにもコンソールにも何も記録されません。ただし例外がひとつあり、捕捉されなかったエラーはFlutterエンジン自身がそこに出力するため、クラッシュは引き続き確認できます。設定 > 「デバッグログ」では、ログをJSON Lines形式のファイルとして共有シートから書き出し、消去できます。ログは約50 MBまで保持されます。ログにはカメラのWi-Fiパスワードが含まれます。

### リリース

`main`へのプッシュはすべてリリースになり、[`.github/workflows/release.yml`](../../.github/workflows/release.yml)がそれを作成します。このワークフローは、リリースに前回より1つ大きい0.0.Nという番号を付け、`tool/check.sh`を実行し、両方のアプリの`prod`フレーバーをリリースモードでビルドします。AndroidのAPKはGR Photoのリリース用キーで署名され、SHA-256チェックサム、ビルドの来歴証明（アテステーション）、Kotlinのスタックトレースを読み解くためのR8マッピングとともに[リリースページ](https://github.com/jeph/gr-photo/releases)で公開されます。iOSアプリはApp Store向けに署名され、TestFlightにアップロードされます。キーは`main`だけが使えるGitHubの環境（Environment）に保管されており、アプリをビルドするジョブはどのキーも持ちません。

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo`を実行すると、APKがこのリポジトリからそのワークフローでビルドされたものであることを確認できます。

```sh
tool/testflight.sh       # prodのiOSアプリをビルドしてTestFlightにアップロード
```

このスクリプトは、リリースではないビルドをMacからTestFlightに配信します。アップロード時刻をビルド番号として`prod`フレーバーをビルドし、App Store Connectに送信します。処理が終わると、TestFlightの下に表示されます。内部テスターは、ケーブルなしでTestFlightアプリからインストールできます。XcodeはApp Store ConnectのAPIキーでビルドに署名してアップロードするため、Macで必要な準備は、`~/.appstoreconnect/private_keys`に置くキーの`AuthKey_<key id>.p8`ファイルと、`~/.appstoreconnect/gr-photo.env`に書く`ASC_KEY_ID`と`ASC_ISSUER_ID`です。キーにはAdminロールが必要です。AppleはApp Managerのキーにチームの配布用証明書の使用を許可していないためです。アーカイブは署名なしでビルドし、書き出し時にApp Store向けに署名します（`app/ios/ExportOptions.plist`）。アーカイブ自体に署名するには、チームに登録済みのテストデバイスが必要になるからです。

## コントリビューション

バグ報告とプルリクエストを歓迎します。ほとんどのバグは実機でしか現れないため、[Issueを作成する](https://github.com/jeph/gr-photo/issues)際は、カメラの機種とファームウェアのバージョン、スマートフォンの機種とAndroidまたはiOSのバージョン、そして行った操作を記載してください。書き出したデバッグログ（設定、デバッグログ、ログを書き出す）があれば、たいていは何が起きたのかがわかります。ただし、ログにはカメラのシリアル番号とWi-Fiパスワードが含まれるため、共有しても差し支えない場合にのみ添付してください。

変更を送る前に`tool/check.sh`を実行してください。すべてのチェックに合格する必要があります。コードの構成と従うべきルールは[`AGENTS.md`](../../AGENTS.md)に書かれています。

セキュリティ上の脆弱性と思われるものは、公開のIssueで報告しないでください。[セキュリティポリシー](../../.github/SECURITY.md)に従い、非公開の脆弱性レポートとして提出してください。

## 謝辞

GR Photoは[Flutter](https://flutter.dev)で作られており、Bluetoothには[universal_ble](https://pub.dev/packages/universal_ble)を、そのほか[image](https://pub.dev/packages/image)、[video_player](https://pub.dev/packages/video_player)、[share_plus](https://pub.dev/packages/share_plus)、[path_provider](https://pub.dev/packages/path_provider)を使用しています。文字の表示には[Inter](https://rsms.me/inter/)と[JetBrains Mono](https://www.jetbrains.com/lp/mono/)を使っています。

プロトコルの調査は、RicohのGR WORLDアプリとImage Syncアプリ、GRのファームウェア、そしてGR IIIxのイメージコントロール設定に関する[Ricoh3x](https://github.com/Trimz/Ricoh3x)プロジェクトのメモに基づいています。

## ライセンス

GR Photoは[MITライセンス](../../LICENSE)のもとで公開されています。GR Photoに含まれるサードパーティのパッケージとフォントには、それぞれのライセンスが適用されます。アプリでは**設定 › このアプリについて › ライセンス**に一覧があり、フォントのライセンス文は[`app/assets/fonts/`](../../app/assets/fonts/)にあります。

デモモードのサンプル写真は[Unsplash](https://unsplash.com)のもので、MITライセンスではなく[Unsplashライセンス](https://unsplash.com/license)のもとで使用しています。写真と撮影者の一覧は[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt)にあります。

Ricohのアプリとファームウェアは、この調査で引用していますが、Ricohに帰属するものであり、このリポジトリには含まれていません。
