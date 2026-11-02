# Uygulama kararları

0.2 güncellemesi: [HYBRID.md](HYBRID.md) geçerli kumaş render ve aksesuar yolunu
tanımlar. CPU proxy + GPU vertex deformasyonu ve CPU üçgen socket'i uygulanmıştır.

## Parçaya göre hareket

Temel beden ve sabit giysi Blender'da riglenir; GLB animasyonu Godot'ta oynar.
Göğüslük Chest kemiğini izler. Omuz zırhı UpperArm_R kemiğinin animasyon uzayına
bir BoneAttachment3D ve rest dönüşüm düzeltmesiyle bağlanır.

`AeroClothPiece3D`, sağlam bağlantı dizisini, equipped durumunu, salınımı ve
kopan gövdeyi sahiplenir. İki bağlantı sağlamken animasyonu izler. İlk kopmada
kalan bağlantının dünya noktası korunarak sönümlü, sınırlı bir açıya sarkar.
Bu kontrollü bir hareket modelidir; bedene karşı rigid-body mafsalı değildir.
İkinci kopmada aynı görsel kökü önceden hazırlanmış RigidBody3D'ye aktarır.
Mesh/şekil üretimi hasar anında yapılmaz. Başlangıç hızı animasyon anchor'ından
örneklenir; test darbesi ek impulse verir.

Çanta zırh üzerindeki kararlı bir socket çerçevesini izler ve tek bağlantıya
sahiptir. Varsayılan kural zırhla birlikte gitmesidir; alternatifte zırh düşünce
ayrı gövde olur. Çantaya ayrı darbe de uygulanabilir. Bu takip tek yönlüdür:
çantanın kütlesi zırhın salınımını, kumaşı veya karakter animasyonunu etkilemez.
Rule 2'de çanta CPU kumaşındaki üç köşeli/barycentric socket'i takip eder.

Kumaş, yalnız kalça çevresindeki 9×11 düşük çözünürlüklü test parçasıdır.
Verlet entegrasyonu, beş mesafe düzeltme turu, boyanmış serbestlik, kalça
elipsoidi ve zemin kullanır. İki hazırlanmış üst pin grubu kopabilir. Her fizik adımında
99 nokta texture'a aktarılır; sabit ayrıntılı mesh GPU'da deforme olur.

## Durum ve geri alma

Giysi çıkarılması equipped bayrağını değiştirir; broken_connections onarılmaz.
Tekrar takma aynı hasar durumunu kullanır. Snapshot'lar dizi kopyalarını,
bağlantı konumlarını, fizik dönüşüm/hızlarını, kumaş noktalarını ve boyamayı
taşır. UndoRedo bu snapshot'ları geri kurar. Sadece açık Sıfırla onarır.

Bağlı çantanın kendi ekipman/hasar durumu korunur. Ana zırh çıkarılırsa etkin
görünürlüğü ve fiziği durur. Üç karakterden gizlenenler process ve kopmuş gövde
fiziği açısından durdurulur. Animasyon duraklatma ise yalnız animasyonu durdurur.

JSON hazırlama profili yalnız bağlantıları, alt bölge kuralını, çanta davranışını
ve boyamayı taşır. Runtime hasarı ayrı sahipliktedir; profil yükleme onu sıfırlamaz.
Bu sürümde oyun save/load envanter sistemi yoktur.

## Katmanlar ve maliyet sınırları

İç katmanın ön, arka ve omuz bölgeleri ayrı hazırlanmış yüzeylerdir. Göğüslük
çıkarılırsa ön bölge, ilk omuz bağlantısı koparsa omuz bölgesi hemen geri açılır.
Hareketle açılabilecek omuz, tek bağlantıda artık güvenli örtücü sayılmaz.
`AeroClothLayerState`, başka varlıklara uygulanabilecek örtme/region çekirdeğidir;
bu küçük örnek actor kendi açık bölge kurallarını yeniden hesaplar.

| Maliyet | Bu sürümün yaptığı |
|---|---|
| Çizim | Kesin örtülen bağımsız bölgenin visible bayrağını kapatır; şeffaflık kullanmaz. |
| Skinning/morph | Temel GLB'nin skinning'i devam eder; morph yok. Region gizlemek tüm beden skinning'ini kaldırmaz. |
| Fizik | Çıkarılan kumaş ve gizli karakterler durur; ucuz proxy saklanır. |
| Bellek | Kaynak mesh, pinler, gövdeler ve snapshot'lar bellekte kalır. |

Her darbede mesh kesme yapılmaz. Yüzlerce alt mesh, indeks filtreleme veya vertex
compact etme alternatifleri bu sürümde karşılaştırılmadı; üstünlük iddiası yok.
Gerekli sonraki kıyas, gerçek üretim giysisinin aynı bölgelerini bu yöntemlerle
hazırlayıp aynı görünürlük/hasar zaman çizgisinde ölçmektir.

Beden şekli, temel durum + mevcut giyilenlerden hesaplanan morph sürücüleriyle
tasarlanmalı. Giysiye karşılık gelen fit morph'ları gerekecek; farklı topoloji
için alternatif modeller kullanılacak. Bu zincir şu an uygulanmış değildir.
