<p align="center">
  <img src="../icon.png" alt="GR Photo simgesi" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Lisans: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platformlar: iOS ve Android">
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
  <b>Türkçe</b> ·
  <a href="README.el.md">Ελληνικά</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.th.md">ไทย</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.zh.md">中文简体</a> ·
  <a href="README.zh-Hant.md">中文繁體</a> ·
  <a href="README.ja.md">日本語</a>
</p>

**GR Photo**, Ricoh GR kameralar (GR III, GR IIIx ve GR IV) için iOS ve Android’de çalışan bir
yardımcı uygulamadır. Kameranızdaki fotoğraflara göz atıp onları indirir, canlı görüntülü bir
uzaktan deklanşör olarak çalışır ve Görüntü Kontrolü stillerinizi tek bir yerde tutar. Hızlı ve
kullanımı kolay olacak, kameranın renk profillerini de hakkıyla yönetecek şekilde tasarlanmıştır:
bir fotoğrafın çekildiği stili kaydedin, bir önizleme eşliğinde düzenleyin ve kameranın Özel
yuvalarına yükleyin.

GR Photo bağımsız bir projedir ve Ricoh ile bağlantılı değildir. Kamerayla, Ricoh’un kendi
uygulamalarından ve kamera yazılımından tersine mühendislikle çıkarılmış bir protokol üzerinden
haberleşir; bulgular [`research/`](../../research/README.md) klasöründe belgelenmiştir.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/library-dark.png">
    <img src="../screenshots/library-light.png" alt="Arşiv: kameradaki fotoğraflar gün gün, JPEG, RAW ve video filtreleriyle" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/looks-dark.png">
    <img src="../screenshots/looks-light.png" alt="Stiller sayfası: telefonda kayıtlı stillerin üstünde kameranın üç Özel yuvası" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../screenshots/look-editor-dark.png">
    <img src="../screenshots/look-editor-light.png" alt="Stil düzenleyici: Görüntü Kontrolü kaydırıcılarının üstünde önce ve sonra önizlemesi" height="400">
  </picture>
  <img src="../screenshots/live-view.png" alt="Canlı görüntü: pozlama göstergeleri ve deklanşörle birlikte kameranın görüntüsü" height="400">
</p>

<p align="center">
  <sub>Arşiv, Stiller, stil düzenleyici ve canlı görüntü; simüle edilmiş kamerayla demo modunda.</sub>
</p>

## İçindekiler

- [Özellikler](#özellikler)
- [Gereksinimler](#gereksinimler)
- [Kurulum](#kurulum)
- [Kullanım](#kullanım)
- [Geliştirme](#geliştirme)
- [Katkıda bulunma](#katkıda-bulunma)
- [Teşekkürler](#teşekkürler)
- [Lisans](#lisans)

## Özellikler

GR Photo üç şeyi ön planda tutar: fotoğraflarınıza çabucak ulaşmak, size ayak bağı olmamak ve
Görüntü Kontrolü stillerini yönetilmeye değer bir şey olarak görmek.

- **Hızlı.** GR Photo açıldığında, kamera yakındaysa onunla Bluetooth üzerinden bağlantı kurar.
  Arşiv’i açmak kamerayı uyandırır, Wi-Fi’sini açar ve tek seferde bu ağa bağlanır; ardından siz
  sayfalar arasında gezinirken Wi-Fi açık kalır, böylece hiçbir şey iki kez bağlanmaz ve süren bir
  indirme yarıda kalmaz. Dosya listeleri, küçük resimler ve önizlemeler telefonda önbelleğe alınır;
  bu sayede Arşiv hızlı açılır. Bir Android telefonla denenen GR IV HDF’de, kapalı kameradan
  Arşiv’e ulaşmak yaklaşık 13 saniye sürdü.
- **Kullanımı kolay.** Kameralarınız tek bir ekranda durur; Arşiv, Çekim ve Stiller oradan tek
  dokunuş uzaklıktadır. GR Photo kamerayı açar, Wi-Fi’sini etkinleştirir ve ağına sizin yerinize
  bağlanır; yani eşleştirmeden sonra kamerada ayarlanacak bir şey kalmaz. Bir şey başarısız
  olduğunda nedenini ve neyi kontrol etmeniz gerektiğini söyler, yanında da Yeniden dene seçeneğini
  sunar. Kopan bağlantı kendiliğinden geri gelir.
- **Yönetebileceğiniz stiller.** Arşiv’deki her fotoğraf, hangi Görüntü Kontrolü ile çekildiğini
  gösterir; tek dokunuşla bunu bir stil olarak kaydedersiniz. Stiller, hangi kameradan gelmiş
  olurlarsa olsunlar telefonunuzda durur; ayarlarıyla, alındıkları fotoğrafla ve onları barındıran
  Özel yuvasını gösteren bir etiketle birlikte.
- **Önizlemeli stil düzenleyici.** Temel görüntüyü ve onun Ton, Renk, Ayrıntı ve Efektler olarak
  gruplanmış tüm parametrelerini değiştirin, sonucu da kendi fotoğrafınızda veya bir örnek
  fotoğrafta görün: önce ile sonra arasında bir ayırıcıyı kaydırın, ikisini yan yana koyun ya da
  aralarında geçiş yapmak için dokunun. Önizleme, kameranın yazılımından çözülen görüntü işleme
  sürecini yaklaşık olarak yansıtır
  ([`research/image-control-processing.md`](../../research/image-control-processing.md)).
- **Stilleri kameraya yükleyin.** Stiller sayfası, kameranın C1’den C3’e kadar olan Özel
  yuvalarında ne bulunduğunu gösterir. Kayıtlı bir stili bir yuvaya sürükleyin ya da menüsünden
  Yükle seçeneğini belirleyin; stil artık kameradadır. Yuvaları okumak ve yuvalara yüklemek,
  kameranın Wi-Fi ağına bağlanmadan yalnızca Bluetooth üzerinden çalışır.
- **Arşiv.** Kameradaki fotoğraf ve videolara gün gün göz atın; JPEG, RAW, video veya henüz
  indirilmemiş olanlara göre filtreleyin ve istediğiniz çekimi ayrıntılarıyla birlikte tam ekranda
  açın. Tek bir çekimi ya da bir seçimi JPEG, RAW veya her ikisi olarak telefonunuzun fotoğraf
  arşivindeki bir GR Photo albümüne indirin. İndirmeler, başka bir uygulama kullanırken veya
  telefonu kilitlediğinizde de sürer: Android bunları Duraklat ve Tümünü iptal et düğmeli bir
  bildirimde, iOS 26 ve sonrası ise ilerlemeyi kilit ekranında ve Dynamic Island'da gösterir.
  Videolar uygulamanın içinde oynatılır.
- **Uzaktan deklanşör.** Yalnızca Bluetooth üzerinden çalışan büyük bir deklanşör düğmesi; yanında
  zamanlayıcı, geçiş modu, mod kadranı, kalan çekim sayısı ve pil durumu. Android’de ses düğmeleri
  de deklanşöre basar.
- **Canlı görüntü.** Wi-Fi üzerinden kameranın görüntüsü: odaklamak için dokunun; açıklığı,
  obtüratör hızını, ISO’yu ve pozlama telafisini kameranın sunduğu değerlerden oluşan bir kadranla
  ayarlayın; geçiş modunu, zamanlayıcıyı, ölçmeyi ve Görüntü Kontrolü’nü değiştirin.
- **Konum etiketleme.** GR kameralarında GPS yoktur. Bir kamera için Canlı konum etiketleme açıkken
  GR Photo, kamera açık olduğu sürece telefonunuzun konumunu Bluetooth üzerinden ona gönderir,
  kamera da onu her fotoğrafa kaydeder. GR Photo’yu açtığınızda başlar ve siz başka bir uygulama
  kullanırken ya da telefonu kilitlediğinizde de sürer. Arka planda konum etiketleme ise sizden bir
  şey yapmanızı gerektirmeyen seçenektir: telefon bulunduğu yerlerin 90 günlük geçmişini tutar, GR
  Photo da bir fotoğrafı indirdiğinizde, çekildiği zamana en yakın anda kaydedilen yeri JPEG ve RAW
  dosyalarına aynı şekilde ekler. İkisi de siz bir kamera için açana kadar kapalıdır.
- **Birden çok kamera.** Sahip olduğunuz kadar kamerayı eşleştirin ve aralarında geçiş yapın; her
  birini yeniden adlandırın ya da unutun.
- **Temalar ve diller.** Açık, Koyu, Karanlık oda, Kâğıt ve Siyanotip temaları ile kameranın kendi
  menülerindeki 21 dil.
- **Gizliliğinize saygılı.** Hesap, analiz, reklam veya çökme raporlaması yoktur. GR Photo yalnızca
  kameranızla ve bir fotoğrafın çekildiği yerin haritası için OpenFreeMap ile haberleşir;
  [gizlilik politikasına](../../app/assets/privacy.md) bakın.

## Gereksinimler

- Bir Ricoh GR III, GR IIIx veya GR IV; HDF gövdeleri ve GR IV Monochrome dâhil.
- Stiller için yazılım sürümü 1.04 veya sonrası olan bir GR IV, bir GR IV HDF ya da bir GR IV
  Monochrome gerekir. GR III ve GR IIIx yazılımı, Görüntü Kontrolü ayarlarını telefondan okumanın
  veya yazmanın bir yolunu sunmaz.
- Android 12 veya sonrası ya da iOS 15.5 veya sonrası.

GR Photo henüz yeni bir uygulamadır. Donanım günlüğünde, yazılım sürümü 1.20 olan bir GR IV HDF ile
yapılan denemeler kayıtlıdır: eşleştirme, bağlanma, kamerayı uyandırma, göz atma, indirme, canlı
görüntü, odak ve pozlama değişiklikleri. GR III ve GR IIIx desteği protokol araştırmasına dayanır
ve henüz bir kamerada test edilmemiştir. Nelerin gözlemlendiğini görmek için
[`research/hardware-validation.md`](../../research/hardware-validation.md) dosyasına bakın.

## Kurulum

Android’de `gr-photo-v<version>.apk` dosyasını telefonunuzda
[en son sürümden](https://github.com/jeph/gr-photo/releases/latest) indirin ve açın. Android,
tarayıcınızdan uygulama kurma izni için bir kez sorar. Her sürüm aynı anahtarla imzalanır; bu
yüzden yeni sürüm elinizdekinin üzerine kurulur ve kameralarınızı ve ayarlarınızı korur.

iOS’te her sürüm TestFlight’a gider; şimdilik yalnızca projenin kendi test kullanıcılarına. Henüz
herkese açık bir TestFlight bağlantısı yoktur; bu yüzden GR Photo bir iPhone’a kaynak koddan
derlenerek kurulur.

Kaynak koddan derleme için Android SDK’sı veya Xcode kurulu olan [Flutter](https://flutter.dev)
3.47 veya sonrası gerekir.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run`, uygulamayı bilgisayarınıza bağlı olan telefona kurar. iOS derlemeleri için Hotspot
Configuration ve Access Wi-Fi Information yeteneklerine sahip kendi imzalama ekibiniz gerekir.
Kaynak koddan derlenen bir Android derlemesi yayın anahtarıyla değil, bilgisayarınızın hata
ayıklama anahtarıyla imzalanır; bu yüzden Android bunlardan birini diğerinin üzerine kurmaz: önce
elinizdekini kaldırın.

Uygulamayı kamera olmadan denemek için demo modunda çalıştırın; bu mod, örnek fotoğraflar içeren
simüle edilmiş bir GR IV kullanır ve Android emülatörü ile iOS simülatöründe çalışır:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Kullanım

1. **Kameranızı eşleştirin.** Kamera ekle’ye dokunun ve yönergeleri izleyin. Kamerada eşleştirme,
   MENU → E6 → Kablosuz İletişim Ayarı altında yer alır: İşlem Modu ayarını Açık yapın,
   Eşleştirme’yi açıp Eşleştirme Yap öğesini seçin, ardından kodu telefonda onaylayın ve kamerada
   OK düğmesine basın. Kamera artık Kameralar ekranındadır ve GR Photo, kamera yakındayken
   açıldığında ona kendiliğinden bağlanır.
2. **Arşiv’i açın.** GR Photo, kamera kapalıysa onu açar ve Wi-Fi ağına bağlanır. Android, kameranın
   ağını bir kez onaylamanızı ister. Bir çekimi görüntülemek için ona dokunun, birden çok çekim
   seçmek için basılı tutun ve saklamak istediklerinizi indirin.
3. **Çekim yapın.** Kumanda, Bluetooth üzerinden çalışan bir deklanşördür. Canlı görüntü ise
   kameranın Wi-Fi ağına bağlanır ve odak ile pozlama denetimleriyle birlikte kameranın görüntüsünü
   gösterir.
4. **Bir stil kaydedin.** Arşiv’de bir fotoğrafı açıp Stili kaydet’e dokunun ya da Stiller
   sayfasındaki + ile sıfırdan bir stil oluşturun. Düzenlemek için bir stile dokunun; kameraya
   yüklemek için de onu C1, C2 veya C3’e sürükleyin.
5. **Konum ekleyin.** Kameranın kartında, Arşiv, Çekim ve Stiller’in altındaki Canlı konum
   etiketleme’yi açın. Telefonunuz, GR Photo’nun telefonun konumunu kullanmasına izin verip
   vermediğinizi sorar. Bundan sonra konum, GR Photo çalışırken ve kamera açık ve kapsama
   alanındayken gönderilir. Arka planda konum etiketleme, kameranın kartındaki ⋯ altındadır ve
   konuma her zaman izin verilmesini gerektirir.

Ayarlar’daki Otomatik bağlantı kesme, GR Photo bir süre (varsayılan olarak 5 dakika)
kullanılmadığında kameranın Wi-Fi ağından çıkar. [GR Photo nasıl davranır](../behaviour.md) belgesi,
her ekranı ve her bağlantı durumunu ayrıntılı olarak anlatır.

## Geliştirme

### Dizin yapısı

| Yol | İçerik |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi HTTP API’si, değişiklik WebSocket’i ve bağlanma/kurtarma oturumu; saf Dart ile |
| `packages/gr_camera` | Uygulamanın kamerayla ilgili her şey için çağırdığı kamera katmanı: Bluetooth ve Wi-Fi bağdaştırıcıları (Wi-Fi’ye bağlanmayı sağlayan Kotlin ve Swift koduyla birlikte), oturum, eşleştirme, tarama, Arşiv, Çekim ve canlı görüntü ile her alışverişin izlenmesi |
| `packages/gr_fake_camera` | Testler ve demo modu için simüle edilmiş GR IV (BLE, Wi-Fi’ye bağlanma, geri döngü üzerinde HTTP sunucusu) |
| `app` | Flutter uygulaması; fotoğraf arşivine kaydetmeyi sağlayan Kotlin ve Swift koduyla birlikte |
| `research` | Protokol araştırması: her rotanın ve karakteristiğin nasıl bulunduğu, yazılımdan elde edilen kanıtlar, donanım sonuçları, açık sorular |
| `tool` | `check.sh`: tüm kod kalitesi denetimleri; bir sürümü derleyen, imzalayan ve yükleyen betikler; `testflight.sh`: Mac’ten iOS yüklemesi |

### Çalıştırma

```sh
cd app
flutter run                                  # dev derlemesi, gerçek kamera (Bluetooth’lu bir telefon gerekir)
flutter run --profile                        # aynısı, yayın derlemesinin hızında
flutter run --flavor prod --release          # kullanıcıların aldığı derleme
flutter run --dart-define=GR_DEMO=true       # simüle edilmiş kamera, Android emülatöründe ve iOS simülatöründe çalışır
```

İki derleme vardır. `dev` (`io.jeph.grphoto.dev`, adı “GR Photo Dev”), `prod` (`io.jeph.grphoto`,
“GR Photo”) ile yan yana kurulur. `--flavor` verilmezse `flutter run` ve `flutter build`, `dev`
derlemesini oluşturur.

`flutter run` tek başına bir hata ayıklama derlemesi oluşturur; bu derleme her kareyi profil veya
yayın derlemesine göre birkaç kat daha yavaş üretir (Android emülatöründe Arşiv’de 3 ila 4 kat,
2026-11-10). Bir ekranın ne kadar akıcı olduğunu `--profile` veya `--release` ile değerlendirin.

Demo modu, verilerini ayrı bir `demo/` klasöründe tutar. İlk açılışta Kamera ekle, simüle edilmiş
kamerayı bulur ve kamera eşleştirmeyi kendiliğinden onaylar; sonraki açılışlar kamera kapalı olarak
başlar ve siz Arşiv’i açana (kamerayı uyandırmak, Wi-Fi ağına bağlanmanın bir parçasıdır) ya da
karttaki güç düğmesine basana kadar kamera kapalı kalır. Demo RAW dosyaları, `.DNG` adı taşıyan
JPEG baytlarıdır.

### Denetimler

```sh
tool/check.sh            # biçimlendirici, çözümleyici, kamera katmanı sınırı, çeviriler, tüm test takımları
tool/check.sh --static   # testler olmadan
```

Çözümleyici, bilgi düzeyindeki bulguların hata sayıldığı `very_good_analysis` kurallarını kullanır.
Android ve iOS derlemeleri önce `tool/check.sh --static` komutunu çalıştırır ve bu başarısız olursa
durur. Kotlin ve Swift uyarıları hata sayılır. Kurallar için [`AGENTS.md`](../../AGENTS.md)
dosyasına bakın.

### Testler

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

Entegrasyon testi, demo akışının tamamını (eşleştirme, bağlanma, göz atma, iki çekim indirme) bir
cihazda, emülatörde veya simülatörde çalıştırır. Bir hata ayıklama derlemesi, emülatörde yaklaşık
400 MB boş alan gerektirir. Android’de `flutter test`, ne varsayılan çeşidi ne de uygulamanın
kimliğini projeden alır; bu yüzden `--flavor dev` ve önceden derlenmiş bir APK gerekir. Bunlar
olmadan “No application found” iletisiyle durur.

iOS simülatöründe, Fotoğraflar erişimi verilirken uygulamanın kurulu olması gerekir; `flutter test`
ise sonrasında uygulamayı kaldırır ve bu da verilen izni siler. GR Photo, albümünü tutabilmek için
tam erişim ister; iOS 26.3 simülatöründe ise `simctl privacy grant photos` tek başına iOS’in
sormasını engellemedi: kaydettiği iznin `auth_version` değeri 1’dir, iOS ise bunu ancak 2
olduğunda tam erişim sayar. Her çalıştırmadan önce izni verin ve bu değeri ayarlayın:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Hata ayıklama günlüğü

GR Photo, Ayarlar > Hata ayıklama günlüğünü etkinleştir açıkken hata ayıklama günlükleri tutar:
kameraya gönderdiği ve kameradan aldığı her şey (Bluetooth taramaları, okumaları, yazmaları ve
bildirimleri, her HTTP isteği ve yanıtı, WebSocket iletileri, canlı görüntü kare boyutları ve
Wi-Fi’ye bağlanma adımları), uygulamanın yazdırdığı her satır, yakalanmamış hatalar ve yerel Wi-Fi
kodunun satırları. Bu ayar `dev` derlemesinde varsayılan olarak açık, `prod` derlemesinde
kapalıdır. Kapalıyken hiçbir şey günlüğe yazılmaz, logcat’e veya konsola bile; tek bir istisna
vardır: Flutter motoru yakalanmamış hataları oraya yine de kendisi bildirir, böylece çökmeler
görünür kalır. Ayarlar > Hata ayıklama günlüğü, günlüğü paylaşma sayfası üzerinden JSON Lines
dosyaları olarak dışa aktarır ve temizler. Günlükte yaklaşık 50 MB veri tutulur. Günlük, kameranın
Wi-Fi parolasını içerir.

### Sürümler

`main`’e yapılan her push bir sürümdür ve
[`.github/workflows/release.yml`](../../.github/workflows/release.yml) tarafından oluşturulur. Bu
iş akışı sürüme, bir öncekinden bir fazla olacak şekilde 0.0.N numarasını verir, `tool/check.sh`
betiğini çalıştırır ve her iki uygulamanın `prod` çeşidini yayın modunda derler. Android APK’sı
GR Photo’nun yayın anahtarıyla imzalanır ve SHA-256 sağlama toplamı, bir derleme kaynağı doğrulaması
ve Kotlin yığın izlerini okunur kılan R8 eşlemesiyle birlikte
[sürümler sayfasında](https://github.com/jeph/gr-photo/releases) yayımlanır. iOS uygulaması App
Store için imzalanır ve TestFlight’a yüklenir. Anahtarlar yalnızca `main`’in kullanabildiği GitHub
ortamlarında tutulur ve uygulamaları derleyen işlerin hiçbirinde bu anahtarlar bulunmaz.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo`, bir APK’nın bu depodan o iş
akışı tarafından derlendiğini doğrular.

```sh
tool/testflight.sh       # prod iOS uygulamasını derler ve TestFlight’a yükler
```

Betik, sürüm olmayan bir derlemeyi bir Mac’ten TestFlight’a koyar. `prod` çeşidini derleme numarası
olarak yükleme zamanını kullanarak derler ve App Store Connect’e gönderir; derleme işlendikten
sonra orada TestFlight altında görünür. Dahili test kullanıcıları onu kablo gerekmeden TestFlight
uygulamasından kurar. Xcode, derlemeyi bir App Store
Connect API anahtarıyla imzalayıp yükler; dolayısıyla bir Mac’teki kurulum, anahtarın
`~/.appstoreconnect/private_keys` içindeki `AuthKey_<key id>.p8` dosyasından ve
`~/.appstoreconnect/gr-photo.env` içindeki `ASC_KEY_ID` ile `ASC_ISSUER_ID` değerlerinden ibarettir.
Anahtarın Admin rolüne sahip olması gerekir: Apple, bir App Manager anahtarının ekibin dağıtım
sertifikasını kullanmasına izin vermez. Derleme arşivi imzasız oluşturulur ve dışa aktarılırken
App Store için imzalanır (`app/ios/ExportOptions.plist`); çünkü arşivin kendisini imzalamak, ekipte
kayıtlı bir test cihazı gerektirirdi.

## Katkıda bulunma

Hata bildirimleri ve çekme istekleri memnuniyetle karşılanır. Hataların çoğu yalnızca gerçek
donanımda ortaya çıkar; bu yüzden [bir sorun kaydı açarken](https://github.com/jeph/gr-photo/issues)
lütfen kamera modelinizi ve yazılım sürümünü, telefon modelinizi ve Android ya da iOS sürümünü, bir
de ne yaptığınızı belirtin. Dışa aktarılmış bir hata ayıklama günlüğü (Ayarlar, Hata ayıklama
günlüğü, Günlüğü dışa aktar) genellikle ne olduğunu gösterir; ancak kameranızın seri numarasını ve
Wi-Fi parolasını içerir, bu yüzden onu yalnızca bunları paylaşmakta sakınca görmüyorsanız ekleyin.

Bir değişiklik göndermeden önce `tool/check.sh` komutunu çalıştırın; her denetimin geçmesi gerekir.
[`AGENTS.md`](../../AGENTS.md), kodun nasıl düzenlendiğini ve uyduğu kuralları açıklar.

Güvenlik açığı olduğundan şüphelendiğiniz durumları herkese açık sorun kayıtlarında bildirmeyin.
Özel bir güvenlik açığı bildirimi göndermek için [güvenlik politikasını](../../.github/SECURITY.md)
izleyin.

## Teşekkürler

GR Photo, [Flutter](https://flutter.dev) ile geliştirilmiştir; Bluetooth için
[universal_ble](https://pub.dev/packages/universal_ble), ayrıca
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) ve
[path_provider](https://pub.dev/packages/path_provider) paketlerini kullanır. Metinleri
[Inter](https://rsms.me/inter/) ve [JetBrains Mono](https://www.jetbrains.com/lp/mono/) yazı
tipleriyle dizilmiştir.

Protokol araştırması, Ricoh’un GR WORLD ve Image Sync uygulamalarına ve GR yazılımına, ayrıca
[Ricoh3x](https://github.com/Trimz/Ricoh3x) projesinin GR IIIx’in Görüntü Kontrolü ayarlarına
ilişkin notlarına dayanır.

## Lisans

GR Photo, [MIT Lisansı](../../LICENSE) ile yayımlanmıştır. GR Photo ile birlikte gelen üçüncü taraf
paketler ve yazı tipleri kendi lisanslarını korur. Uygulama bunları **Ayarlar › Hakkında ›
Lisanslar** altında listeler; yazı tiplerinin lisans metinleri ise
[`app/assets/fonts/`](../../app/assets/fonts/) klasöründedir.

Demo modunun örnek fotoğrafları [Unsplash](https://unsplash.com) kaynaklıdır ve MIT Lisansı ile
değil,
[Unsplash Lisansı](https://unsplash.com/license) ile kullanılır;
[`app/assets/photo-credits.txt`](../../app/assets/photo-credits.txt) dosyası bunları
fotoğrafçılarıyla birlikte listeler.

Araştırmanın atıfta bulunduğu Ricoh uygulamaları ve yazılımı Ricoh’a aittir ve bu deponun parçası
değildir.
