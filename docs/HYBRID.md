# CPU fizik + GPU görsel deformasyon · 0.2-hybrid

Hasar, bağlantı sahipliği, örtme kuralları ve fizik için gereken yüzey CPU'dadır.
Ayrıntılı kumaşın vertex konumlarını vertex shader üretir. GPU compute çözücüsü
eklenmedi: bu adım compute gerektirmez ve Compatibility renderer ile çalışır.

## Veri akışı

1. 9×11 = **99 CPU noktası**, beş mesafe kısıtı turuyla çözülür.
2. Noktalar yerel koordinata çevrilir. XYZ pozisyon + A boyama serbestliği,
   9×11 RGBAF texture'a yazılır: **1.584 bayt / fizik adımı / karakter** ham veri.
3. Sabit 33×41 = **1.353 vertex / 2.560 üçgen** görsel mesh, UV üzerinden
   ilgili CPU üçgenine barycentric bağlanır. Shader dört komşu texel'i okuyup
   ait olduğu üçgenin konumunu ve normalini hesaplar.
4. CPU noktalarından AABB güncellenir; shader deformasyonu kamera culling'inde
   kaybolmaz. GPU'dan geri okuma yapılmaz.

Normal GPU güncellemelerinde mesh, materyal ve texture nesneleri sabittir.
Texture içeriği güncellenir. Diagnostic CPU referans yolu aynı 1.353 vertex'i
aynı üçgen eşlemesiyle CPU'da üretip mesh'i yeniler; yalnız kıyas için tutulur.
Kenar/vertex teşhisi CPU proxy'nin o anki 99 noktasının görüntüsüdür; ayrı debug
geometrisi gerektiğinde yaratılır, normal render yolunun parçası değildir.

Daha fazla render vertex'i kendi başına yeni kırışıklık veya fizik ayrıntısı
üretmez. Bu sürüm görsel yoğunluğu fizik çözümünden ayıran altyapıyı kanıtlar.
Üretim giysisinde proxy bağlama verisi Blender hazırlığına eklenmelidir.

## Kumaşa bağlı aksesuar

Hasar panelindeki **Çanta kumaş üçgenini izlesin** seçeneği rule 2'dir. Socket,
üç CPU noktasından barycentric konum, yüzey normali ve ortonormal yön çerçevesi
üretir. Physics priority sırası cloth 0 → socket 1 → bag 2 olduğundan aynı
fizik adımındaki noktalar kullanılır. Dejenere üçgende son geçerli çerçeve korunur.

Çantanın kendi bağlantısı ve hasarı bağımsızdır; darbe ile kopup düşebilir.
Kumaş çıkarıldığında bağlı çantanın etkin görünürlüğü ve fiziği durur, hasarı
onarılmaz. Zırhı çıkarmak kumaşa bağlı çantayı kaldırmaz. Diğer iki zırh bağlantı
kuralı korunur. Profil, snapshot ve Undo/Redo rule 2'yi de taşır.

Bu takip tek yönlüdür. Çantanın kütlesi kumaşa geri kuvvet uygulamaz. Çanta
hazırlanmış bir üçgene bağlanır; editörden keyfi üçgen seçme henüz yoktur.

## Doğrulama

`scripts/validate.sh`: **275 kontrol**, 0 hata. Yeni 15 kontrol mesh/texture
kimliği, CPU referans eşlemesi, deforme AABB ve sınır örneklemesini; 53 socket
kontrolü hareket, yön, dejenere yüzey, hasar, ekipman ve üç karakteri kapsar.
İki ek profil kontrolü rule 2'nin JSON kaydı ve hasarı koruyarak yüklenmesini doğrular.

Gerçek render testi:

```bash
godot --path . --script tests/test_hybrid_render.gd
```

256×256 viewport'ta deforme yüzey CPU ve gerçek vertex shader yoluyla çizildi:
21.043 kaplanan piksel, **0 siluet farkı**. Bu, GPU vertex konumu yolunun
doğrulamasıdır; renk/aydınlatma eşitliği veya fizik doğruluğu testi değildir.
Test Compatibility / Mesa llvmpipe ile çalıştı. Donanım GPU testi yoktur.

Godot 4.6.3 ile doğrulandı. Godot 4.7.2 ve Blender 5.2.3 hâlâ test edilmedi.

## Kıyasın tekrarı

```bash
bash scripts/benchmark_hybrid.sh
```

Pencere/3D viewport, 3 karakter, görsel 1.353 vertex ve CPU 99 nokta iki yolda
aynıdır. Çantalar CPU kumaş socket'ini izler. 120 kare ısıtma + 600 ölçüm karesi;
üç tur aynı karede ilk zırh bağlantısı kopması ve ikinci bağlantıda düşme vardır.
`--fixed-fps 60` aynı simülasyon zaman çizgisi ve her karede bir fizik adımı
sağlar. Ölçülen wall-frame süreleri yine gerçek kronometredir. Bu sentetik kıyas
gerçek zamanlı oyunun yetişemediğinde yapacağı fizik catch-up davranışını ölçmez.

Ham veriler `artifacts/hybrid-{cpu,gpu}-3.json` altında ayrı tutulur.
Karşılaştırma tablosu: [hybrid-summary.md](../artifacts/hybrid-summary.md).
Son üç karakter kıyasında fizik adımı başına kumaş script ortalaması CPU referans
yolunda **12.172 ms**, GPU deformasyon yolunda **2.745 ms** idi. Wall-frame
ortalaması **111.024 / 104.746 ms**, p99 **155.755 / 134.367 ms**, hasar çevresi
tepe **132.949 / 134.367 ms** oldu. Genel kare kazancı, CPU script kazancından
küçüktür; yazılım renderer'ı yükü devam eder. Donanım GPU sonucu değildir.
Önceki 0.1 ölçümleriyle doğrudan kıyaslanamaz: geometri yoğunluğu ve zamanlama
farklıdır. llvmpipe yazılım renderer'ıdır; donanım hızlanması veya hedef FPS
garantisi vermez. Compute'a taşıma kararı hedef GPU'da CPU/GPU profili sonrası
verilmelidir. Morph ve genel giysi çarpışması bu değişiklikte uygulanmadı.
