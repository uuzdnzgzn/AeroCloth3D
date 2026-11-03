# Kalan işler ve devralma notu

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
2. **Hedef cihaz:** kullanıcı hedef FPS ve en düşük CPU/GPU cihazını henüz
   belirlemedi. Bu bilgiyle gerçek GPU üzerinde üç karakter/darbe ölçümünü tekrarla.
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
