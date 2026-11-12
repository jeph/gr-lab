<p align="center">
  <img src="../icon.png" alt="GR Lab 圖示" width="128" height="128">
</p>

<h1 align="center">GR Lab</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="授權：MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="平台：iOS 與 Android">
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
  <b>中文繁體</b> ·
  <a href="README.ja.md">日本語</a>
</p>

**GR Lab** 是 Ricoh GR 相機（GR III、GR IIIx 和 GR IV）的搭配 App，支援 iOS 與 Android。它可以瀏覽並下載相機裡的照片、當作附即時取景的遙控快門，還能把你的影像控制風格集中收在一處。它力求快速、好用，並且把相機的色彩設定檔管理好：儲存照片拍攝時所用的風格、對照預覽加以編輯，再載入相機的自定義欄位。

GR Lab 是獨立專案，與 Ricoh 沒有關聯。它與相機通訊所用的協定，是從 Ricoh 自家的 App 和相機韌體逆向工程而來；研究結果整理在 [`research/`](../../research/README.md)。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="圖庫：按日期排列的相機照片，可依 JPEG、RAW 和影片篩選" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="風格頁面：上方是相機的三個自定義欄位，下方是儲存在手機上的風格" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="風格編輯器：上方是套用前後的對照預覽，下方是影像控制的滑桿" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="即時取景：相機的畫面，附曝光數值和快門按鈕" height="400">
</p>

<p align="center">
  <sub>圖庫、風格、風格編輯器和即時取景，皆為使用模擬相機的示範模式。</sub>
</p>

## 目錄

- [功能](#功能)
- [系統需求](#系統需求)
- [安裝](#安裝)
- [使用方式](#使用方式)
- [開發](#開發)
- [參與貢獻](#參與貢獻)
- [致謝](#致謝)
- [授權](#授權)

## 功能

GR Lab 最看重三件事：讓你快速看到照片、不妨礙你操作，以及把影像控制風格當成值得好好管理的東西。

- **快速**：只要相機在附近，GR Lab 一打開就會透過 Bluetooth 與相機連線。打開圖庫時，它會一口氣喚醒相機、開啟相機的 Wi-Fi 並加入；之後在各頁面之間切換時 Wi-Fi 都保持連線，所以不必重複加入，下載也不會中斷。檔案列表、縮圖和預覽都會快取在手機上，圖庫因此開得很快。以 GR IV HDF 搭配 Android 手機實測，從相機關機狀態到進入圖庫約需 13 秒。
- **好用**：所有相機都在同一個畫面上，點一下就能進入圖庫、拍攝和風格。GR Lab 會替你開啟相機電源、開啟相機的 Wi-Fi 並加入，所以配對之後不必再到相機上設定任何東西。出問題時，它會說明原因和該檢查的地方，並提供「再試一次」。連線中斷後會自行恢復。
- **可以管理的風格**：圖庫中的每張照片都會顯示拍攝時所用的影像控制，點一下就能存成風格。不論來自哪一台相機，風格都存在你的手機上，並附有設定、來源照片，以及標示它位於哪個自定義欄位的標籤。
- **附預覽的風格編輯器**：你可以變更基礎影像和它的每一項參數（分為階調、色彩、細節和效果四組），並在自己的照片或範例照片上查看結果：拖動分隔線比較套用前後、將兩者並排顯示，或點一下切換。預覽是依據相機韌體推算出來的近似效果（[`research/image-control-processing.md`](../../research/image-control-processing.md)）。
- **將風格載入相機**：風格頁面會顯示相機的自定義欄位 C1 到 C3 目前的內容。把已儲存的風格拖到欄位上，或從它的選單中選擇「載入」，相機就有這個風格了。讀取和載入欄位只需要 Bluetooth，不必加入相機的 Wi-Fi。
- **圖庫**：按日期瀏覽相機裡的照片和影片，依 JPEG、RAW、影片或未下載篩選，並可全螢幕開啟任何一張，查看詳細資訊。可下載單張或選取的多張，格式可選 JPEG、RAW 或兩者，存入手機照片圖庫中的 GR Lab 相簿。使用其他 App 或鎖定手機時，下載仍會繼續：Android 會在通知中顯示下載，並附「暫停」和「全部取消」按鈕；iOS 26 或以上版本則在鎖定畫面和動態島顯示進度。影片可直接在 App 中播放。
- **遙控快門**：只靠 Bluetooth 就能使用的大型快門按鈕，並顯示自拍、驅動模式、模式轉盤、可拍張數和電池。在 Android 上，按音量鍵也能拍攝。
- **即時取景**：透過 Wi-Fi 傳來的相機畫面：點一下對焦，用列出相機可用數值的轉盤設定光圈、快門速度、ISO 和曝光補償，並可變更驅動、自拍、測光方式和影像控制。
- **多台相機**：你有幾台就能配對幾台，並在它們之間切換；每一台都可以重新命名或忘記。
- **主題與語言**：淺色、深色、暗房、相紙和藍曬主題，以及相機選單本身提供的 21 種語言。
- **重視隱私**：沒有帳號、分析、廣告或當機回報。GR Lab 只與你的相機通訊；請參閱[隱私權政策](../../app/assets/privacy.md)。

## 系統需求

- Ricoh GR III、GR IIIx 或 GR IV，包括 HDF 機型和 GR IV Monochrome。
- 風格功能需要韌體 1.04 或更新版本的 GR IV、GR IV HDF 或 GR IV Monochrome。GR III 和 GR IIIx 的韌體沒有提供從手機讀取或寫入影像控制設定的方法。
- Android 12 或更新版本，或 iOS 15 或更新版本。

GR Lab 還很年輕。硬體記錄中收錄的是以韌體 1.20 的 GR IV HDF 進行的測試：配對、連線、喚醒相機、瀏覽、下載、即時取景、對焦和變更曝光。對 GR III 和 GR IIIx 的支援來自協定研究，尚未在實機上測試。實際觀察到的結果請參閱 [`research/hardware-validation.md`](../../research/hardware-validation.md)。

## 安裝

目前還沒有打包好的發行版本，因此要安裝 GR Lab 得從原始碼建置。建置需要 [Flutter](https://flutter.dev) 3.47 或更新版本，並已設定好 Android SDK 或 Xcode。

```sh
git clone https://github.com/jeph/gr-lab.git
cd gr-lab/app
flutter run --flavor prod --release
```

`flutter run` 會將 App 安裝到與電腦連接的手機上。iOS 版本需要你自己的簽署團隊，並具備 Hotspot Configuration 和 Access Wi-Fi Information 功能。

如果想在沒有相機的情況下試用 App，可以用示範模式執行；它使用附範例照片的模擬 GR IV，可在 Android 模擬器和 iOS 模擬器上執行：

```sh
flutter run --dart-define=GR_DEMO=true
```

## 使用方式

1. **配對相機**：點一下「新增相機」，然後按照引導操作。在相機上，配對位於 MENU → E6 → 無線通訊設定：將「動作模式」設為「開啟」，開啟「配對」並選擇「執行配對」，接著在手機上確認驗證碼，再按下相機的 OK。相機隨後會出現在「相機」畫面上；之後只要相機在附近，GR Lab 一打開就會自行與它連線。
2. **打開圖庫**：如果相機已關機，GR Lab 會開啟它的電源，並加入它的 Wi-Fi。Android 會請你核准一次相機的網路。點一下照片即可檢視，按住可選取多張，然後下載想保留的照片。
3. **拍攝**：「遙控」是透過 Bluetooth 運作的快門。「即時取景」會加入相機的 Wi-Fi 並顯示相機的畫面，還有對焦和曝光控制項。
4. **儲存風格**：在圖庫中打開一張照片並點一下「儲存風格」，或在風格頁面用「+」從頭建立。點一下風格即可編輯，把它拖到 C1、C2 或 C3 上就能載入相機。

GR Lab 閒置一段時間後（預設為 5 分鐘），「設定」中的「自動中斷連線」會讓它離開相機的 Wi-Fi。[GR Lab 的運作方式](../behaviour.md)詳細說明了每個畫面和每一種連線狀態。

## 開發

### 專案結構

| 路徑 | 內容 |
|---|---|
| `packages/gr_protocol` | BLE GATT、Wi-Fi HTTP API、變更通知 WebSocket，以及連線／復原工作階段，以純 Dart 寫成 |
| `packages/gr_camera` | App 處理一切相機相關事務時所呼叫的相機層：Bluetooth 和 Wi-Fi 轉接器（含以 Kotlin 和 Swift 寫成的 Wi-Fi 加入程式碼）、工作階段、配對、掃描、圖庫、拍攝和即時取景，以及每一次資料交換的追蹤 |
| `packages/gr_fake_camera` | 模擬的 GR IV（BLE、Wi-Fi 加入、位於 loopback 的 HTTP 伺服器），供測試和示範模式使用 |
| `app` | Flutter App，含用來儲存到照片圖庫的 Kotlin 和 Swift 程式碼 |
| `research` | 協定研究：每個路由和特徵是如何找到的、韌體中的證據、硬體測試結果、尚待解答的問題 |
| `tool` | `check.sh`：所有程式碼品質檢查；`testflight.sh`：iOS 上傳 |

### 執行

```sh
cd app
flutter run                                  # dev 版本，真實相機（需要有 Bluetooth 的手機）
flutter run --profile                        # 同上，但速度與 release 版本相同
flutter run --flavor prod --release          # 使用者拿到的版本
flutter run --dart-define=GR_DEMO=true       # 模擬相機，可在 Android 模擬器和 iOS 模擬器上執行
```

共有兩種版本。`dev`（`io.jeph.grlab.dev`，名稱為「GR Lab Dev」）可與 `prod`（`io.jeph.grlab`，「GR Lab」）並存安裝。不加 `--flavor` 時，`flutter run` 和 `flutter build` 建置的是 `dev`。

單獨執行 `flutter run` 會產生除錯版本，它繪製每一個影格的速度比 profile 或 release 版本慢上數倍（2026-11-10 在 Android 模擬器的圖庫中測得為 3 到 4 倍）。請用 `--profile` 或 `--release` 來判斷畫面是否流暢。

示範模式的資料存放在獨立的 `demo/` 資料夾中。第一次啟動時，「新增相機」會找到模擬相機，而且它會自行確認配對；之後每次啟動時相機都是關機狀態，直到你打開圖庫（喚醒相機是加入其 Wi-Fi 的一部分）或按下卡片上的電源按鈕才會開機。示範用的 RAW 檔案其實是副檔名為 `.DNG` 的 JPEG 位元組。

### 檢查

```sh
tool/check.sh            # 格式化工具、分析器、相機層邊界、翻譯、所有測試套件
tool/check.sh --static   # 不含測試
```

分析器使用 `very_good_analysis`，並將 info 視為錯誤。Android 和 iOS 建置會先執行 `tool/check.sh --static`，失敗就停止。Kotlin 和 Swift 的警告一律視為錯誤。相關規則請參閱 [`AGENTS.md`](../../AGENTS.md)。

### 測試

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

整合測試會在實機或模擬器上跑完整個示範流程（配對、連線、瀏覽、下載兩張照片）。除錯版本在模擬器上需要約 400 MB 的可用空間。在 Android 上，`flutter test` 不會從專案取得預設的 flavor 和 App 的 ID，因此需要加上 `--flavor dev`，並事先建置好 APK；少了這些，它會停下來並顯示「No application found」。

在 iOS 模擬器上，授予照片取用權限時 App 必須已經安裝，而 `flutter test` 結束後會解除安裝 App，授權也隨之刪除。GR Lab 為了保有自己的相簿會要求完整取用權限，而在 iOS 26.3 模擬器上，光靠 `simctl privacy grant photos` 並不能讓 iOS 不再詢問：它記錄的授權其 `auth_version` 為 1，而 iOS 只有在該值為 2 時才視為完整取用權限。每次執行前都要授權並設定這個值：

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grlab.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grlab.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### 除錯記錄

「設定 > 啟用除錯記錄」開啟時，GR Lab 會保留除錯記錄：它傳送給相機和從相機收到的一切（Bluetooth 掃描、讀取、寫入和通知，每一個 HTTP 請求和回應，WebSocket 訊息，即時取景的影格大小，以及加入 Wi-Fi 的各個步驟）、App 印出的每一行、未攔截的錯誤，以及原生 Wi-Fi 程式碼輸出的內容。這項設定在 `dev` 中預設開啟，在 `prod` 中預設關閉。關閉時不會記錄任何內容，連 logcat 或主控台也不會有，只有一個例外：Flutter 引擎仍會自行在那裡回報未攔截的錯誤，所以當機仍然看得到。「設定 > 除錯記錄」會透過分享表單將記錄匯出為 JSON Lines 檔案，並清除記錄。記錄大約保留 50 MB。其中包含相機的 Wi-Fi 密碼。

### TestFlight

```sh
tool/testflight.sh       # 建置 prod 版 iOS App 並上傳到 TestFlight
```

這個指令碼會建置 `prod` flavor，以上傳時間作為建置版本號碼，並送到 App Store Connect；處理完成後，它就會出現在 TestFlight 底下。內部測試人員可從 TestFlight App 安裝，不需要接線。Xcode 會用 App Store Connect API 金鑰簽署並上傳這個版本，因此在 Mac 上要準備的是：放在 `~/.appstoreconnect/private_keys` 中的金鑰檔案 `AuthKey_<key id>.p8`，以及 `~/.appstoreconnect/gr-lab.env` 中的 `ASC_KEY_ID` 和 `ASC_ISSUER_ID`。金鑰需要「管理」角色：Apple 不允許「App 管理」角色的金鑰使用團隊的發佈憑證。封存檔在建置時不簽署，匯出時才針對 App Store 簽署（`app/ios/ExportOptions.plist`），因為直接簽署封存檔需要團隊中有已註冊的測試裝置。

## 參與貢獻

歡迎回報錯誤和提交拉取請求。大多數錯誤只會在實機上出現，所以[建立議題](https://github.com/jeph/gr-lab/issues)時，請附上相機型號和韌體版本、手機型號及其 Android 或 iOS 版本，以及你做了哪些操作。匯出的除錯記錄（「設定」、「除錯記錄」、「匯出記錄」）通常能看出發生了什麼事，但其中包含相機的序號和 Wi-Fi 密碼，所以只有在你願意分享這些資訊時才附上。

送出變更之前，請執行 `tool/check.sh`；每一項檢查都必須通過。[`AGENTS.md`](../../AGENTS.md) 說明了程式碼的組織方式及其遵循的規則。

請勿在公開的議題中回報疑似的安全漏洞。請依照[安全性政策](../../.github/SECURITY.md)提交私人漏洞報告。

## 致謝

GR Lab 以 [Flutter](https://flutter.dev) 建置，Bluetooth 部分使用 [universal_ble](https://pub.dev/packages/universal_ble)，另外還使用 [image](https://pub.dev/packages/image)、[video_player](https://pub.dev/packages/video_player)、[share_plus](https://pub.dev/packages/share_plus) 和 [path_provider](https://pub.dev/packages/path_provider)。文字以 [Inter](https://rsms.me/inter/) 和 [JetBrains Mono](https://www.jetbrains.com/lp/mono/) 排版。

協定研究以 Ricoh 的 GR WORLD 和 Image Sync App 以及 GR 韌體為基礎，並參考了 [Ricoh3x](https://github.com/Trimz/Ricoh3x) 專案關於 GR IIIx 影像控制設定的筆記。

## 授權

GR Lab 以 [MIT License](../../LICENSE) 釋出。GR Lab 內含的第三方套件和字型各自沿用其原有的授權。App 將它們列在**設定 › 關於 › 授權**底下，字型的授權條款全文則位於 [`app/assets/fonts/`](../../app/assets/fonts/)。

範例照片來自 [Unsplash](https://unsplash.com)，依 [Unsplash 授權](https://unsplash.com/license)使用，不適用 MIT License；[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) 列出了這些照片及其攝影者。

研究中引用的 Ricoh App 和韌體屬於 Ricoh 所有，不包含在這個儲存庫中。
