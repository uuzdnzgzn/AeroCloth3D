# Kalan işler ve devralma notu

## 0.3 sonrası

Godot authoring/main-screen, harita/aşama/timeline, runtime hit adapteri ve
R05 örneği uygulandı. Önce [AUTHORING.md](AUTHORING.md) ve güncel test/ölçümleri
oku; aşağıdaki 2026-11-03 başlangıç öncelikleri tarihsel kayıttır.

Üretim öncelikleri: hedef CPU/GPU'da 60 FPS profili ve maske yayın gecikmesi;
4 bölgelik önbellek sınırının büyük varlıklarda ölçülü genişletilmesi; daha
iyi temas/bükülme, karmaşık iskelet/fit kombinasyonları; gölge/uzak mesafe
görsel kabul matrisi. Serbest kesme, tam kendisiyle çarpışma, canlı Blender
köprüsü ve aksesuar kütlesi geri beslemesi hâlâ yoktur. GPU compute'a geçiş
yalnız gerçek profiler gerekçesiyle yapılmalıdır.

## Güncel ürün hedefi ve öncelik · 2026-11-03

Kullanıcının birleşik iş akışı [REQUIREMENTS.md](REQUIREMENTS.md) içindedir.
Bu hedefler uygulanmış özellik olarak sunulmamalı. İlk öncelik **R04/R05**:
üst giysinin alt kumaşın hareketini bölgesel olarak kısıtlaması ve yerel kopmada
bu etkinin kaldırılması. Görünürlük, temas ve hareket kısıtları ayrı ayarlanmalı.
Temel serbestlikten etkin giyim/hasar durumuna göre yeniden hesaplama, birden çok
üst etki, tutarlı uyanma ve Undo/Redo kabul senaryoları belgede tanımlıdır.

Araç hedefi Godot editörü içinde kalıcı hazırlama kaynakları ve Blender aktarımıdır;
mevcut runtime demo bu tam hazırlama uygulaması değildir. R01–R11 kapsamı ağırlık
aktarımı/fit önerilerini, morph uyumunu, düşman darbesine göre veriyle ayarlanabilir
tepkiyi ve üç karakter ölçümünü de içerir.

## Diğer kalan işler

İlk hazırlanmış hasar senaryosu karakter üzerinde çalışır. Bütün eski sürümü
yeniden kurmak bu aşamanın sonucu değildir; yeni kod ve kanıtlar bu depodadır.

1. **Üretim karakteri:** özgün Cyberstyle arşivi geldiğinde lisans/atıfla ekle;
   mevcut yeni test karakteriyle karıştırma. Yeni iskeletin rest uzayını ve gerçek
   giysi yüzeylerini ölç, anchor'ları yeniden hazırla. Genel otomatik fit vaat etme.
2. **Hedef cihaz:** Ryzen 5 1600 + GTX 1650 4 GB + 16 GB RAM + SATA SSD
   kullanıcı tarafından bildirildi. Bu cihazda üç karakter/darbe ölçümünü tekrarla;
   çözünürlük ve grafik profili belirlenmeli. 60 FPS çalışma hedefi henüz
   doğrulanmadı; referans cihazı ölçmeden minimum gereksinim ilan etme.
3. **Temas:** askıda zırhın bedene girişini sınırlayan basit temas; kumaşın gerçek
   bacak/kalça hareketiyle güncellenen proxy'si. Genel kendisiyle çarpışma yok.
4. **Kumaşa aksesuar:** CPU üçgen/barycentric socket 0.2'de uygulandı. Keyfi
   üçgeni editörden seçme ve çift yönlü kütle/kuvvet aktarımı henüz yok.
5. **Katman karşılaştırması:** aynı giyside region-mesh, önbellekli indeks ve
   compact vertex varyantlarını draw/skin/physics/memory olarak ayrı ölç.
6. **Morph zinciri:** beden temelinden yeniden hesaplama, fit sürücüleri ve
   çıkarıp takma testleri. Birikimli deformasyondan kaçın.
7. **Varlık iş akışı:** bu çalışan örneğin metadata ihtiyacına göre küçük Blender
   GLB + JSON dışa aktarıcı; canlı çift yönlü köprü henüz gerekçelendirilmedi.
8. **Editör:** runtime laboratuvarı şu an Tools menüsünden açılır. Keyfi GLB içe
   aktarma, gerçek project resource authoring, editor içi ana ekran ve kalıcı
   gameplay save/load ayrı geliştirmelerdir.

Araştırmayı tekrar etmeden önce RECOVERY.md, ARCHITECTURE.md ve PERFORMANCE.md
dosyalarını oku. Doğrulama komutu scripts/validate.sh; ham ölçümler artifacts/
altında. Devir notundaki 246 eski kontrolü bu uygulamanın test sayısına ekleme.
