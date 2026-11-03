# 0.3 Authoring · uygulama kaydı

## Kaynak ve çalışma zamanı

`AeroOutfit` karakter, giysi kaynakları ve test zaman çizgisini tutar.
`AeroWearableDefinition`, `AeroWearableRegion`, `AeroDamageStage` ve
`AeroLayerEffect` kaynakları temel hareket, hasar aşaması, harita tarifi ve
üst→alt ilişkileri taşır. Bunlar oyun hasarıyla değiştirilmez.

`AeroWearableController` bölgesel hasarı, eşikleri, yinelenen hit kimliklerini,
ekipman sahipliğini ve sinyalleri yönetir. Reentrant darbeler sıraya alınır;
geçişler bir kez bildirilir. `AeroWearableRig` kaynakları sahne, materyal, morph,
CPU proxy ve hazırlanmış rigid parçalara uygular. Oyun sahnesi EditorPlugin veya
EditorInterface'e bağlı değildir; temiz projede ayrıca denenir.

## Harita ve model aşamaları

Maskenin RGBA kanalları cut/wear/burn/blood'dur. Dent ayrı yükseklik görüntüsünde
tutulur. Fırça işlemleri ve tohumlar tarif olarak saklanır. Haritalar hem giysi
temelinde hem aşama bazında düzenlenir; etkin aşamaya kadar olan tarifler birleşir.
Undo/Redo tek fırça hareketini tek işlem sayar. UV görünümünde alpha, normal,
roughness, nötr albedo ve yükseklik incelenebilir; PNG ve tarif dışa aktarılabilir.
Albedo önizlemesi kaynak dokunun tam bake'i değildir.

PBR shader UV0 kaynak dokularını ve varsa UV2 hasar alanını ayrı kullanır.
RNM normal karışımı, alpha scissor ve çift yüz aydınlatması vardır. Bölgesel
çarpanlar bir bölgenin hasarının diğerinin delik kuvvetini değiştirmesini önler.
Ortak UV sınırlarında controller ve shader aynı kimlik sırasını kullanır.

Oyun kipinde normal detayı yükseklik texture'ından shader'da üretilir. Kozmetik
maske raster işlemleri WorkerThreadPool'da CPU-only Image'lar üzerinde çalışır;
Node, hazırlama kaynağı veya GPU nesnesi işçi thread'inde değiştirilmez. Ana
iş parçacığı yalnız tamamlanan sonucu mevcut texture kimliklerine yayınlar.
Her eşyada tek iş yürür; yeni darbeler en son nesilde birleştirilir, eski sonuçlar
atılır. Mantık/fizik hemen değişir; kozmetik iz kısa süre gecikebilir. Delik
sorgusu son yayımlanmış maskeyi kullanır. Çok hızlı darbelerde harita yayın
gecikmesi hedef donanımda ayrıca ölçülmelidir.

Editör, başlangıç hazırlığı, sıfırlama ve kayıt yükleme eşzamanlıdır. Normal PNG
dışa aktarımı CPU'da yapılmaya devam eder. `async_runtime_masks=false` ile
eşzamanlı teşhis yolu seçilebilir; yoğun harita üretiminde bu yol takılabilir.

Model varyantları ve fizik gövdeleri oyun başlamadan hazırlanır. Varyant değişimi
mevcut proxy noktalarını/hızlarını taşır; bağlama darbe anında tekrarlanmaz.
Tam mesh varyantları birden çok bölgeden seçiliyorsa en yüksek aşama kazanır;
eşitlikte bölge kimliği belirleyicidir. Bağımsız bölgesel model kırılmaları için
ayrı parçalar kullanılmalıdır; rastgele varyantlar birleştirilmez.

Örnekte yatay yırtık hazırlanmıştır: aşama 3'te tek köprü kalır, aşama 4'te
son köprü açılır. Görsel varyant ile proxy kenarları birlikte değişir. İkinci
kısıtlayıcının 0.2 hareket sınırı etkinse alt kumaş tamamen serbestleşmez.

## Önizleme ve oyun

Editör AnimationPlayer klibi ve darbe olaylarını birlikte sürer. Seek, hasarı
sıfırlayıp 60 Hz adımlarla tekrar oynatır; olay tohumları saklıdır. Oyunun
AnimationTree'si yeniden kurulmaz. Hızlı seek'te kopan sert parça kontrollü
yerçekimi/zemin önizlemesiyle ilerler; oyun kipinde RigidBody3D fizik dünyasını
kullanır. Keyfi oyun çarpışmasının birebir seek replay'i vaat edilmez.

Oyundan `rig.apply_hit({hit_id,position,direction,type,amount,impulse})` çağrılır.
`resolve_hit` CPU proxy veya o andaki skin/morph yüzeyinden UV2/UV0 eşlemesi yapar.
Mevcut delik ve gizli üçgenler dikkate alınır; GPU readback yoktur. Eşleme biliniyorsa
item/region/uv doğrudan verilebilir. Sistem saldırı engelleme veya karakter HP'sine
karar vermez. Darbe yönü UV kesik açısına, impulse yeni kopan parçaya aktarılır.

Hazırlama kaydı ve runtime kayıt ayrıdır. Runtime JSON; maskeleri yeniden üretmek
için gereken darbeleri, bölge aşamalarını, kopma/ekipman durumunu, nokta hızlarını
ve animasyon durumunu taşır. Bozuk kayıtlar atomik reddedilir; yükleme hasar/kopma
bildirimlerini tekrar oynatmaz.

## Blender ve yeniden import

Blender eklentisi UUID, rig, ağırlık, bölge, proxy, bağlantı ve morph metadata'sı
üretir. UV2 pozitif alan örtüşmesi test edilir. GLB SHA-256 hash'i yanlış eşlikçi
metadata kullanımını engeller. Kaynak topolojisi ve Godot vertex düzeni ayrı izlenir;
Blender indeksleri doğrudan Godot'a kopyalanmaz. Değişen topoloji/rig yeniden
hazırlama gerektirir. UV2 ve sınırlı fit yardımcıları kopyalarda çalışır; orijinal
mesh, ağırlıklar ve morph farkları korunur.

## Doğrulama ve performans

`scripts/validate.sh` eski prototip regresyonlarını ve yeni canvas/controller/
proxy/importer/rig/game adapter testlerini çalıştırır. Ayrıca eklenti yalnız
başına temiz projeye kopyalanır; editörde import edilir, sahne üretilir ve ayrı
oyun prosesinde darbe uygulanır. `scripts/validate_render.sh` gerçek sürücüde
shader delikleri, UV2, RNM, proxy hareketi, varyant ve arayüzü doğrular.
Blender testi kopyada ağırlık, UV2, fit sınırı ve gerçek dışa aktarımı kapsar.

`scripts/benchmark_authoring.gd` üç karakterde aynı runtime adapterini kullanır:
120 kare ısıtma, 600 örnek, 12 olayda eşzamanlı altı eşya darbesi. Ceket ve
alt kumaşın maskeleri, model varyantı, kopma ve katman serbestleşmesi birlikte
değişir. Ham sonuçlar `artifacts/authoring-benchmark-*.json` altındadır.

İlk ölçüm ciddi CPU maske/normal yeniden üretim takılması gösterdi. Önceki sonuçlar
`authoring-baseline-*.json` olarak korunur. Güncel ölçüm ve sınırlar bunlarla
birlikte yayımlanır; yazılım renderer'ında 60 FPS onayı verilmez.

Son doğrulama: 626 başsız kontrol, 146 görüntü oluşturma kontrolü ve 40 Blender
kontrolü geçti. Ölçüm tablosu ve kozmetik maske gecikmeleri
[`artifacts/authoring-summary.md`](../artifacts/authoring-summary.md) içinde.
Benchmark darbeleri bilinen UV koordinatlarını kullanır; dünya uzayındaki temasın
UV'ye çözülme maliyeti bu darbe sürelerine dahil değildir. Dünya uzayı eşlemesi
ayrı işlevsel testlerde doğrulanır.
