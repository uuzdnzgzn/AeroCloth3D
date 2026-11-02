# Kurtarma ve doğrulama kaydı · 2026-11-02

## Erişilebilirlik

- `/workspace/AeroCloth3D` başlangıçta yoktu. `/workspace`, yükleme klasörleri ve
  `/tmp` aramasında önceki proje, ZIP, GLTF veya paket bulunmadı.
- GitHub `uuzdnzgzn/AeroCloth3D` metadata size=0; `contents?ref=main`
  yanıtı `This repository is empty` idi. İlk uzak ref sorgusu da boştu.
- Yeni ortam bağlantısı çalışıyor; eski oturumun kimliğiyle aynı ortam değil.
  Bu kontrol eski ortamın kaydedilmemiş verilerinin silindiğini göstermez.
- Önceki iki yüklemenin dosya kimlikleri bu konuşmada yok; yeniden indirme
  aracıyla erişilebilir bir ek dosya sağlanmadı.
- Cyberstyle resmi Sketchfab `/v3/models/<id>/download` noktası 401,
  `Authentication credentials were not provided` döndürdü. Viewer verisi alınmadı.
- Mevcut dosya silme, reset veya eski proje üstüne yazma yapılmadı. Yeni proje
  boş konumda oluşturuldu. Geçersiz ilk deneme ölçümü yalnız bu oturumun ürettiği
  çıktıydı; nihai raporların arasına alınmadı.

## Geçmiş rapor ile bugünkü durum

Önceki `0.9-surface-contact`, 246 kontrol, native spring cape, surface-contact,
eski boyama/LOD/editor uygulamaları ve paketler **yalnız devir notunda** var.
Kodları burada bulunmadığından doğrulanmış veya yeniden kazanılmış sayılmıyor.

Yeni uygulamanın adı `0.1-rebuild`. Önceki özelliklerin hepsi yapılmış gibi
sürüm numarası kullanılmadı. EditorPlugin, çalışma sahnesini açan bir menü
eklentisidir; önceki ana editor ekranının kurtarılmış hali değildir.

İlk importta `.blend` import ayarı GLB importunu durdurdu. Bu tespit edilip
doğrudan Blender importu kapatıldı; karakter GLB'si yeniden import edildi.
İskelet/animasyon gerektiren bütün nihai testler import edilen gerçek GLB ile
çalıştırıldı. Karaktersiz ilk deneme sayıları nihai ölçümlerde kullanılmadı.

Referans arayüz görselleri de bu konuşmaya taşınmadı. Yeni arayüz koyu renk,
turkuaz seçim, geniş önizleme ve bağlama göre araç taleplerinden üretildi.
