# Ürün gereksinimleri · Project Riot of Sarraw

Güncelleme: 2026-11-03. Bu belge kullanıcının oyun ve hazırlama aracı hedeflerini
toplar. Bir gereksinimin burada bulunması uygulanmış olduğu anlamına gelmez.
Mevcut 0.2 prototipi için HYBRID.md ve VERIFICATION.md geçerlidir.

## 0.3 uygulama durumu

Godot ana ekran eklentisi, kalıcı kaynaklar, bölgesel hasar aşamaları, 3D/UV
harita üretimi, aşamaya özel tarifler, animasyon/darbe zaman çizgisi ve oyun
adapteri uygulandı. R05 temel→etkin hareket, iki kısıtlayıcı ve kopmada
serbestleşme örnekle doğrulanıyor. Blender'da kopyada ağırlık, UV2 ve sınırlı
rest-pose fit yardımcıları; GLB/UUID/hash metadata aktarımı bulunuyor.
Sınırlı beden/gömlek morph örneği ve hazırlanmış fiziksel yırtık vardır.
Aşağıdaki eski durum tablosu 0.2 başlangıcını kaydeder; güncel kapsam ve
sınırlar [AUTHORING.md](AUTHORING.md), kullanım README içindedir.

## Amaç ve araç biçimi

Hazır karakter, giysi ve animasyonlardan oyun içinde giydirilebilir, hasar
alabilir ve birlikte davranabilir eşyalar hazırlamak. Aynı varlığın her kullanımını
elle yeniden ayarlamak gerekmemeli. Hazırlama verisi tekrar kullanılabilir olmalı.

Hedef, Godot projesinin içinde çalışan EditorPlugin ve kalıcı hazırlama
kaynaklarıdır. Blender modelleme, rig, ağırlık ve shape key üretiminde kullanılmalı;
tekrarlanan aktarım işleri için küçük bir Blender dışa aktarıcısı eklenebilir.
GLB + metadata aktarımı ilk aşama için yeterlidir. Bağımsız uygulama ve canlı çift
yönlü köprü zorunlu değildir. Mevcut runtime test sahnesi tam editör eklentisi değildir.

## Gereksinimler ve durum

| Kimlik | Gereksinim | Mevcut durum |
|---|---|---|
| R01 | Hazır karakter/giysi/animasyon içe alma; ortak iskelet eşleştirmesi | Sabit test GLB'si var; genel hazırlama akışı planlanıyor |
| R02 | Bedenden ağırlık aktarımı, otomatik rig/fit önerileri ve elle düzeltme | Planlanıyor; kusursuz otomatik uyum garantisi yok |
| R03 | Kumaşın çok kemiğe skin edilmesi; sert parçanın kemik/socket/bağlantıyla taşınması | Örnekte rig takibi ve sert bağlantı prototipi var |
| R04 | Birlikte giyilen parçaların bölgesel görünürlük ve hareket ilişkileri | Basit görünürlük örneği var; hareket kısıtlama ilişkileri henüz yok |
| R05 | Üst giysiyle alt kumaşın kısmen kısıtlanması; hasarla bölgesel serbestleşme | Yeni öncelikli gereksinim; uygulanmadı |
| R06 | Beden sıkıştırma morph'ları ve giysilerde karşılık gelen fit morph'ları | Planlanıyor |
| R07 | Malzemeye uygun deformasyon, yırtılma, bağlantı kopması, sarkma ve düşme | Hazırlanmış kopma ve kontrollü sarkma prototipi var |
| R08 | Çanta/aksesuarın deforme yüzeyi izlemesi, kendi hasarı ve kopma kuralı | Hazır CPU üçgen socket'i var; keyfi yüzey seçimi ve kuvvet geri beslemesi yok |
| R09 | Düşman darbesinin nokta/yön/tür/şiddetinden düzenlenebilir bölgesel tepki | Test darbesi var; oyunun savaş sistemiyle genel entegrasyon planlanıyor |
| R10 | Karakter üzerinde düzenleme, animasyon/hasar testi, Undo/Redo, kalıcı varlık ayarı | Runtime laboratuvarında kısmen var; gerçek editor kaynak akışı planlanıyor |
| R11 | İki, en fazla üç önemli karakter için ölçülen CPU/GPU paylaşımı | 0.2 hibrit prototipi ve yazılım renderer kıyası var; hedef donanım/FPS açık |

## R05: Üst katmanın alt kumaşın hareketini değiştirmesi

Örnek: uzun gömlek tek giyilince geniş bir bölgesi serbestçe hareket eder.
Üzerine kemer, dar ceket veya zırh giyildiğinde belirlenen bölgeler tutulur;
yalnız açıkta veya serbest bırakılan kısımlar simüle edilir. Üst parçanın bir
bölgesi koparsa onun tuttuğu alt bölge de kademeli olarak hareket edebilir.
Üst parçanın tamamının çıkarılması gerekli değildir.

Üstte bulunmak tek başına fiziksel sabitleme anlamına gelmez. Bol bir ceket,
altındaki kumaşı tamamen sabitlemeyebilir. Araç; örtme, temas ve hareket
kısıtlamasını ayrı ilişkiler olarak tanımlatmalı. Kullanıcı her bölge için
etkinin yok, kısmi veya güçlü olmasını ayarlayabilmeli.

İlişki verisi en az şunları tanımlamalı:

- Kaynak üst eşya/bölge ile hedef alt eşya/bölge veya proxy noktaları.
- Etkinleşme koşulu: giyili olma, ilgili parçanın/bağlantının sağlamlığı ve hasar durumu.
- Hareket serbestliği, kısıt sertliği ve gerekirse takip edilen hedef yüzey/kemik.
- Hasarla ne kadarının ve hangi bölgelerin serbestleşeceği.
- Etkileşim türü: yalnız örtme, hareket kısıtlama, ucuz çarpışma veya ayrıca şekil etkisi.
- Serbestleşme geçişi ve maliyet politikası; gerektiğinde komşu sınır noktalarının korunması.

Kemik ağırlıkları, kumaş serbestliği ve örtme maskeleri ayrı verilerdir. Üst
katman ilişkisi giysinin temel kemik ağırlıklarını kalıcı biçimde değiştirmemeli.
Etkin hareket, temel hazırlama verisi + o anda giyili ve sağlam etkileyicilerden
yeniden hesaplanmalı. Etkileri art arda uygulayıp çıkarırken sayısal birikim
oluşturulmamalı. Birden fazla üst parçanın etki birleştirme kuralı açık,
deterministik ve düzenleme işlem sırasından bağımsız olmalı.

Gizlenen alt yüzeyin çizimi durabilir; hareketli sınır veya çarpışma için gereken
ucuz temsil korunabilmeli. Her örtülü noktayı tamamen silmek hedef değildir.
Uyuyan simülasyon serbestleşirken güncel poz ve hızla tutarlı başlatılmalı;
eski pozdan sıçrama, patlayan hız veya uzun ilk çözüm takılması üretilmemeli.
Gerekli sıcak tutma/uyanma maliyeti ölçülmelidir.

## R05 kabul senaryoları

1. Alt giysi tek başına: kendi boyanmış temel serbestliği ve animasyon uyumu geçerli.
2. Üst parça giyili: yalnız tanımlı alt bölgeler kısıtlanır; açık kenarlar hareket eder.
3. Üst parçada yerel kopma: yalnız o etkinin tuttuğu alt bölgeler yeniden değerlendirilir.
4. İkinci üst parça aynı bölgeyi tutuyorsa birincinin kopması bölgeyi tamamen serbest bırakmaz.
5. Üst giysi çıkarılır/geri takılır: etkin hareket yeniden hesaplanır; eşya hasarı korunur.
6. Kısmi hasarda tekrar giydirme: sadece hâlâ sağlam üst bölgeler kısıtlayıcı olur.
7. Undo/Redo ve kayıt yükleme: görünürlük, ilişkiler ve etkin hareket tutarlı geri gelir.
8. Aynı etkin giyim/hasar durumuna farklı işlem sıralarıyla ulaşılınca aynı sonuç elde edilir.
9. Görünürlük ve hareket bağımsızlığı: görünen ama tutulan ve görünmeyen ama sınır için
   simüle edilen bölgeler doğru çalışır. Shader ile görünmez yapmak optimizasyon sayılmaz.
10. Üç karakterde aynı anda kopma/serbestleşme: ortalama, p99, en kötü kare ve olay
    çevresi ölçülür; CPU, render, bellek ve simülasyon uyanma maliyeti ayrılır.

## Hazırlama ve savaş sistemi akışı

Karakter/giysi seç → iskelet ve uyumu hazırla → temel ağırlık/serbestlik bölgelerini
ayarla → katmanların örtme/temas/hareket etkilerini tanımla → bağlantı ve hasar
kurallarını yerleştir → animasyon, giyim kombinasyonu ve darbeyle test et → kaydet.

Kullanıcı karakter üzerinde hangi bölgenin neden gizli veya kısıtlı olduğunu,
hangi üst eşyanın onu etkilediğini ve kopunca ne olacağını görebilmeli. Otomatik
öneri ile kullanıcının onayladığı hazırlama verisi ayırt edilebilmeli.

Oyundan gelen darbe, vuruş konumu/yönü, hasar türü ve şiddetiyle ilgili eşya ve
bölgeye eşlenmeli. Üç yönlü savaş, giysinin tümünü aynı anda azaltan tek dayanıklılık
çubuğuna indirgenmemeli. Alt katmana geçiş ve bağlantı kırılma eşikleri veriyle
ayarlanabilmeli. Oyun tasarımcısı her saldırı için mesh kodu yazmamalı.

Çanta takibi ve çantanın ağırlığının kumaşı çekmesi ayrı özelliklerdir. Birincisi
prototipte var; ikincisi ayrıca fizik tasarımı ve ölçüm gerektirir. Serbest kesme,
genel kusursuz fit ve her giysi çarpışmasını otomatik çözme vaat edilmez.

## Sonraki uygulama dilimi

Godot hazırlama kaynaklarında temel hareket verisini ve üst→alt bölge etkisini
ayır. Aynı karakterde bir alt kumaş ile iki bağımsız üst kısıtlayıcı kullanarak
R05 kabul senaryolarını kanıtla. Seçili bölgenin etkileyicilerini editörde göster;
ilişki düzenlemelerini Undo/Redo ve kalıcı kayda bağla. Bunun üzerine Blender
metadata aktarımı ve otomatik ağırlık/fit önerilerini büyüt.
