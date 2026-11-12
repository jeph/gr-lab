<p align="center">
  <img src="../icon.png" alt="GR Photo 图标" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="许可：MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="平台：iOS 和 Android">
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
  <b>中文简体</b> ·
  <a href="README.zh-Hant.md">中文繁體</a> ·
  <a href="README.ja.md">日本語</a>
</p>

**GR Photo** 是一款面向 Ricoh GR 相机（GR III、GR IIIx 和 GR IV）的配套应用，支持 iOS 和 Android。它可以浏览并下载相机里的照片，可以当作带实时取景的遥控快门，还能把你的影像控制风格集中收在一处。它力求快速、易用，并把相机的色彩配置真正管理起来：保存拍摄某张照片时所用的风格，对照预览进行编辑，再载入相机的自定义槽位。

GR Photo 是独立项目，与 Ricoh 没有关联。它与相机通信所用的协议，是从 Ricoh 自家的应用和相机固件中逆向分析得来的；相关发现都整理在 [`research/`](../../research/README.md) 中。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="图库：按日期排列的相机照片，可按 JPEG、RAW 和影片筛选" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="“风格”页面：上方是相机的三个自定义槽位，下方是保存在手机上的风格" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="风格编辑器：上方是原图与风格效果的对比预览，下方是影像控制滑块" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="实时取景：相机的画面，以及曝光读数和快门" height="400">
</p>

<p align="center">
  <sub>图库、风格、风格编辑器和实时取景，均为使用模拟相机的演示模式。</sub>
</p>

## 目录

- [功能](#功能)
- [使用要求](#使用要求)
- [安装](#安装)
- [使用方法](#使用方法)
- [开发](#开发)
- [参与贡献](#参与贡献)
- [致谢](#致谢)
- [许可](#许可)

## 功能

GR Photo 最看重三件事：让你尽快看到照片，不给你添麻烦，以及把影像控制风格当作值得用心管理的东西。

- **快速**：只要相机在附近，GR Photo 一打开就会通过蓝牙与它建立连接。打开“图库”时，唤醒相机、开启相机的 Wi-Fi 并加入其中一气呵成；此后在各页面之间切换时 Wi-Fi 一直保持连接，因此无需重复加入，下载也不会中断。文件列表、缩略图和预览都缓存在手机上，所以“图库”打开得很快。用 Android 手机搭配 GR IV HDF 时，从相机关机状态到进入它的“图库”约需 13 秒。
- **易用**：所有相机都在同一个画面上，从那里点按一下即可进入“图库”“拍摄”和“风格”。GR Photo 会替你开启相机、打开它的 Wi-Fi 并加入其中，因此配对之后无需再在相机上做任何设置。出问题时，它会说明原因和需要检查的事项，并提供“重试”。连接断开后会自动恢复。
- **可以管理的风格**：“图库”中的每张照片都会显示拍摄时所用的影像控制，点按一下即可将其保存为风格。无论来自哪台相机，风格都保存在你的手机上，并附带其设置、来源照片，以及标明它在哪个自定义槽位中的标签。
- **带预览的风格编辑器**：可以更改基础影像及其全部参数（按“影调”“色彩”“细节”和“效果”分组），并在自己的照片或示例照片上查看效果：拖动分隔线对比原图与风格效果，将两者并排显示，或点按切换。预览是对相机成像效果的近似，依据其固件推算得出（[`research/image-control-processing.md`](../../research/image-control-processing.md)）。
- **把风格载入相机**：“风格”页面会显示相机的自定义槽位 C1 至 C3 中各有什么。把已保存的风格拖到某个槽位上，或在它的菜单中选择“载入”，相机就有了这个风格。读取和载入槽位仅靠蓝牙即可完成，无需加入相机的 Wi-Fi。
- **图库**：按日期浏览相机里的照片和影片，按 JPEG、RAW、影片或“未下载”筛选，并可全屏打开任意一张，查看其详细信息。可以下载单张或选中的多张，格式可选 JPEG、RAW 或两者，存入手机相册中的 GR Photo 相簿。使用其他应用或锁定手机时，下载仍会继续：Android 会在通知中显示下载，并附“暂停”和“全部取消”按钮；iOS 26 或更高版本则在锁定屏幕和灵动岛显示进度。影片可在应用内播放。
- **遥控快门**：一个大大的快门按钮，仅靠蓝牙即可工作，并提供自拍、驱动模式、模式转盘、剩余张数和电池电量。在 Android 上，音量键也可以释放快门。
- **实时取景**：通过 Wi-Fi 显示相机的画面：点按对焦，在列有相机可选数值的转盘上设置光圈、快门速度、ISO 和曝光补偿，还可更改驱动、自拍、测光和影像控制。
- **地理标记**：GR 相机没有 GPS。为某台相机开启“实时地理标记”后，只要相机处于开机状态，GR Photo 就会通过蓝牙把手机的位置发送给它，相机再把位置保存到每张照片中。它会在你打开过 GR Photo 之后开始，使用其他应用或锁定手机时仍会继续。“后台地理标记”是另一种省事的方式：手机会保存 90 天内到过的地点记录，下载照片时，GR Photo 会添加记录时间与拍摄时间最接近的地点，JPEG 和 RAW 文件都一样。两者默认都是关闭的，需要你为相机逐一开启。
- **多台相机**：有多少台就可以配对多少台，并在它们之间切换；每台都可以重命名或移除。
- **主题和语言**：浅色、深色、暗房、相纸和蓝晒主题，以及相机自身菜单所提供的 21 种语言。
- **注重隐私**：没有账户、数据分析、广告或崩溃报告。GR Photo 只与你的相机通信，你的位置只会发送给你的相机并写入你自己的照片；参见[隐私政策](../../app/assets/privacy.md)。

## 使用要求

- 一台 Ricoh GR III、GR IIIx 或 GR IV，包括 HDF 机型和 GR IV Monochrome。
- 风格功能需要 GR IV（固件 1.04 或更高版本）、GR IV HDF 或 GR IV Monochrome。GR III 和 GR IIIx 的固件没有提供从手机读取或写入影像控制设置的途径。
- Android 12 或更高版本，或者 iOS 15 或更高版本。

GR Photo 还很年轻。硬件日志记录了在固件为 1.20 的 GR IV HDF 上进行的测试：配对、连接、唤醒相机、浏览、下载、实时取景、对焦以及更改曝光。对 GR III 和 GR IIIx 的支持来自协议研究，尚未在真机上测试。已观察到的情况参见 [`research/hardware-validation.md`](../../research/hardware-validation.md)。

## 安装

在 Android 上，用手机从[最新发行版](https://github.com/jeph/gr-photo/releases/latest)下载 `gr-photo-v<version>.apk` 并打开它。Android 会请你授予一次从浏览器安装应用的权限。每个发行版都使用同一个密钥签名，因此新版本会直接覆盖安装在你现有的版本之上，并保留你的相机和设置。

在 iOS 上，每个发行版都会发送到 TestFlight，目前只面向本项目自己的测试员。现在还没有公开的 TestFlight 链接，因此在 iPhone 上需要从源代码构建来安装 GR Photo。

从源代码构建需要 [Flutter](https://flutter.dev) 3.47 或更高版本，并配置好 Android SDK 或 Xcode。

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` 会把应用安装到与电脑连接的手机上。iOS 构建需要你自己的签名团队，并具备 Hotspot Configuration 和 Access Wi-Fi Information 两项功能。从源代码得到的 Android 构建使用你电脑上的调试密钥签名，而不是发行密钥，因此 Android 不允许两者中的任何一个覆盖安装另一个：请先卸载你现有的那一个。

如果想在没有相机的情况下试用应用，可以用演示模式运行。演示模式使用一台带有示例照片的模拟 GR IV，可在 Android 模拟器和 iOS 模拟器上运行：

```sh
flutter run --dart-define=GR_DEMO=true
```

## 使用方法

1. **配对相机**：点按“添加相机”，然后按照引导操作。在相机上，配对位于 MENU → E6 → 无线通信设定：将“动作模式”设为“开启”，打开“配对”并选择“执行配对”，然后在手机上确认验证码，再按相机上的 OK。此后相机就会出现在“相机”画面上；只要相机在附近，GR Photo 一打开就会自动与它建立连接。
2. **打开“图库”**：如果相机处于关机状态，GR Photo 会将它开启，并加入它的 Wi-Fi。Android 会请你批准一次相机的网络。点按一张照片即可查看，按住可选择多张，然后下载想要保留的照片。
3. **拍摄**：“遥控”是通过蓝牙工作的快门。“实时取景”会加入相机的 Wi-Fi 并显示其画面，同时提供对焦和曝光控制。
4. **保存风格**：在“图库”中打开一张照片并点按“保存风格”，或在“风格”页面上点按 + 从头新建一个。点按某个风格即可编辑，把它拖到 C1、C2 或 C3 上即可载入相机。
5. **添加位置**：在相机卡片上“图库”“拍摄”“风格”的下方开启“实时地理标记”。手机会询问是否允许 GR Photo 使用位置信息。此后，只要 GR Photo 正在运行，且相机处于开机状态并在连接范围内，就会发送位置。“后台地理标记”位于相机卡片上的 ⋯ 中，需要将位置信息权限设为“始终允许”。

“设置”中的“自动断开”会在 GR Photo 闲置一段时间后（默认为 5 分钟）断开相机的 Wi-Fi。[GR Photo 的行为说明](../behaviour.md)详细介绍了每个画面和每种连接状态。

## 开发

### 目录结构

| 路径 | 内容 |
|---|---|
| `packages/gr_protocol` | BLE GATT、Wi-Fi HTTP API、变更通知 WebSocket 以及连接/恢复会话，纯 Dart 实现 |
| `packages/gr_camera` | 相机层，应用中一切与相机有关的操作都通过它调用：蓝牙和 Wi-Fi 适配器（含用 Kotlin 和 Swift 编写的 Wi-Fi 加入代码）、会话、配对、扫描、图库、拍摄和实时取景，以及对每次数据交换的跟踪记录 |
| `packages/gr_fake_camera` | 模拟的 GR IV（BLE、Wi-Fi 加入、回环地址上的 HTTP 服务器），用于测试和演示模式 |
| `app` | Flutter 应用，以及用于存入手机相册的 Kotlin 和 Swift 代码 |
| `research` | 协议研究：每个路由和特征是如何发现的、固件证据、硬件测试结果、尚未解决的问题 |
| `tool` | `check.sh`，执行全部代码质量检查；构建、签名并上传发行版的各个脚本；`testflight.sh`，从 Mac 执行 iOS 上传 |

### 运行

```sh
cd app
flutter run                                  # dev 构建，真实相机（需要带蓝牙的手机）
flutter run --profile                        # 同上，但速度与 release 构建相同
flutter run --flavor prod --release          # 用户拿到的构建
flutter run --dart-define=GR_DEMO=true       # 模拟相机，可在 Android 模拟器和 iOS 模拟器上运行
```

构建分为两种。`dev`（`io.jeph.grphoto.dev`，名为“GR Photo Dev”）可与 `prod`（`io.jeph.grphoto`，名为“GR Photo”）并存安装。不带 `--flavor` 时，`flutter run` 和 `flutter build` 构建的是 `dev`。

单独运行 `flutter run` 得到的是 debug 构建，它生成每一帧的耗时是 profile 或 release 构建的数倍（2026-11-10 在 Android 模拟器上的“图库”中为 3 到 4 倍）。评判某个画面是否流畅时，请使用 `--profile` 或 `--release`。

演示模式的数据保存在单独的 `demo/` 文件夹中。首次启动时，“添加相机”会找到模拟相机，并且它会自行确认配对；此后每次启动时相机都处于关机状态，直到你打开“图库”（唤醒相机是加入其 Wi-Fi 的一个环节）或按下卡片上的电源按钮才会开机。演示用的 RAW 文件实际是 JPEG 数据，只是文件名以 `.DNG` 结尾。

### 检查

```sh
tool/check.sh            # 格式化工具、分析器、相机层边界、翻译、全部测试套件
tool/check.sh --static   # 不运行测试
```

分析器使用 `very_good_analysis`，并把 info 级别的提示视为错误。Android 和 iOS 构建会先运行 `tool/check.sh --static`，失败则停止。Kotlin 和 Swift 的警告均视为错误。具体规则参见 [`AGENTS.md`](../../AGENTS.md)。

### 测试

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

集成测试会在真机、Android 模拟器或 iOS 模拟器上跑完整个演示流程（配对、连接、浏览、下载两张照片）。debug 构建需要模拟器上有约 400 MB 的可用空间。在 Android 上，`flutter test` 既不会从项目中读取默认 flavor，也不会读取应用的 ID，因此需要加上 `--flavor dev` 并事先构建好 APK；否则它会报“No application found”并停止。

在 iOS 模拟器上，授予“照片”访问权限时应用必须已经安装，而 `flutter test` 结束后会卸载应用，授权也随之被删除。为了维护自己的相簿，GR Photo 会请求完全访问权限；而在 iOS 26.3 模拟器上，仅靠 `simctl privacy grant photos` 并不能阻止 iOS 弹出询问：它记录的授权中 `auth_version` 为 1，而 iOS 只有在该值为 2 时才将其视为完全访问权限。每次运行前都要授予权限并设置该值：

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### 调试日志

只要“设置 > 启用调试日志”处于开启状态，GR Photo 就会保留调试日志：它与相机之间收发的一切（蓝牙扫描、读取、写入和通知，每一个 HTTP 请求和响应，WebSocket 消息，实时取景的帧大小，以及加入 Wi-Fi 的各个步骤）、应用输出的每一行、未捕获的错误，以及原生 Wi-Fi 代码输出的内容。该设置在 `dev` 中默认开启，在 `prod` 中默认关闭。关闭时不会记录任何内容，连 logcat 或控制台也不会写入，只有一个例外：Flutter 引擎自身仍会在那里报告未捕获的错误，因此崩溃依然看得到。“设置 > 调试日志”会通过共享表单把日志导出为 JSON Lines 文件，然后将其清除。日志大约保留 50 MB。其中包含相机的 Wi-Fi 密码。

### 发行版

每次推送到 `main` 都会产生一个发行版，由 [`.github/workflows/release.yml`](../../.github/workflows/release.yml) 完成。它把发行版编号为 0.0.N，比上一个大一，运行 `tool/check.sh`，并以 release 模式构建两个应用的 `prod` flavor。Android APK 使用 GR Photo 的发行密钥签名，连同它的 SHA-256 校验和、构建来源证明以及用于解读其 Kotlin 堆栈跟踪的 R8 映射文件一起发布在[发行版页面](https://github.com/jeph/gr-photo/releases)上。iOS 应用针对 App Store 签名并上传到 TestFlight。密钥保存在只有 `main` 才能使用的 GitHub 环境中，而构建应用的作业不持有其中任何一个。

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` 用于检查某个 APK 是否由该工作流从本仓库构建而成。

```sh
tool/testflight.sh       # 构建 prod 版 iOS 应用并上传到 TestFlight
```

该脚本从 Mac 把一个不属于发行版的构建放到 TestFlight 上。它以上传时间作为构建号来构建 `prod` flavor，并把它发送到 App Store Connect；处理完成后，它会出现在 TestFlight 下。内部测试员通过 TestFlight 应用安装，无需连接数据线。Xcode 使用 App Store Connect API 密钥对构建进行签名并上传，因此在 Mac 上需要准备的是：放在 `~/.appstoreconnect/private_keys` 中的密钥文件 `AuthKey_<key id>.p8`，以及 `~/.appstoreconnect/gr-photo.env` 中的 `ASC_KEY_ID` 和 `ASC_ISSUER_ID`。密钥需要“管理”角色：Apple 不允许“App 管理”角色的密钥使用团队的分发证书。归档在构建时不签名，导出时才为 App Store 签名（`app/ios/ExportOptions.plist`），因为直接对归档签名需要团队中有一台已注册的测试设备。

## 参与贡献

欢迎提交错误报告和拉取请求。大多数错误只会在真实硬件上出现，因此[提交 issue](https://github.com/jeph/gr-photo/issues) 时，请写明相机型号和固件版本、手机型号及其 Android 或 iOS 版本，以及你做了哪些操作。导出的调试日志（设置、调试日志、导出日志）通常能说明发生了什么，但其中包含相机的序列号和 Wi-Fi 密码，因此只有在你不介意分享这些信息时才附上。

提交更改之前，请运行 `tool/check.sh`；每一项检查都必须通过。[`AGENTS.md`](../../AGENTS.md) 介绍了代码的组织方式及其遵循的规则。

请勿在公开的 issue 中报告疑似安全漏洞。请按照[安全政策](../../.github/SECURITY.md)提交私密漏洞报告。

## 致谢

GR Photo 使用 [Flutter](https://flutter.dev) 构建，蓝牙部分使用 [universal_ble](https://pub.dev/packages/universal_ble)，此外还用到 [image](https://pub.dev/packages/image)、[video_player](https://pub.dev/packages/video_player)、[share_plus](https://pub.dev/packages/share_plus) 和 [path_provider](https://pub.dev/packages/path_provider)。界面文字使用 [Inter](https://rsms.me/inter/) 和 [JetBrains Mono](https://www.jetbrains.com/lp/mono/) 字体。

协议研究以 Ricoh 的 GR WORLD 和 Image Sync 应用以及 GR 固件为基础，并参考了 [Ricoh3x](https://github.com/Trimz/Ricoh3x) 项目关于 GR IIIx 影像控制设置的笔记。

## 许可

GR Photo 依据 [MIT 许可证](../../LICENSE)发布。GR Photo 所包含的第三方软件包和字体各自沿用其原有许可。应用在**设置 › 关于 › 许可**下列出了这些许可，字体的许可文本位于 [`app/assets/fonts/`](../../app/assets/fonts/)。

演示模式的示例照片来自 [Unsplash](https://unsplash.com)，依据 [Unsplash 许可](https://unsplash.com/license)使用，不适用 MIT 许可证；[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) 列出了这些照片及其拍摄者。

研究中引用的 Ricoh 应用和固件归 Ricoh 所有，不属于本仓库的内容。
