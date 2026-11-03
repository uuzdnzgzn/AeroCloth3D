# Doğrulama · 2026-11-02

0.3 Authoring testleri ve güncel kapsam [AUTHORING.md](AUTHORING.md) içindedir.
Buradaki 0.2/0.1 sayıları eski sürümlerin kaydıdır; yeni sürüm sayısı olarak
sunulmamalıdır. Ham son test logları artifacts/validation-*.log olarak üretilir.

**0.2-hybrid güncellemesi:** mevcut 205 kontrol + 15 hibrit, 53 yüzey socket ve
2 ek profil kontrolü = **275 kontrol geçti**. Gerçek shader/CPU render silueti karşılaştırması
da geçti. Güncel kapsam ve sınırlar [HYBRID.md](HYBRID.md) dosyasında.

Nihai `bash scripts/validate.sh` çalışması Godot **4.6.3-stable official** üzerinde
başarılı: **205 kontrol, 0 başarısızlık**, ayrıca temiz import ve ana sahne smoke.

| Paket | Kontrol | Gerçek kapsam |
|---|---:|---|
| test_damage.gd | 58 | İki/tek bağlantı, pivot sürekliliği, açık sarkma, gerçek düşüş, kalıcı hasar, snapshot, bölge çekirdeği |
| test_scenario.gd | 52 | Import edilmiş GLB, kemik animasyonu, anchor takibi, gerçek region görünürlüğü, çanta kuralları, reset, üç karakter |
| test_workspace.gd | 83 | 30 seçim/araç bağlamı; gerçek CheckButton/SpinBox; boyama input; Undo/Redo; kenar/vertex; gizli fizik |
| test_profile.gd | 12 | JSON roundtrip, hasarı koruyan ayar yükleme, bozuk/yanlış topoloji verisinin reddi |

Bu sayılar bu yeniden kurulumun testleridir. Önceki oturumun raporladığı 246
kontrol bunlara dahil değildir. Görsel PNG'ler Godot çalışma sahnesinin gerçek
viewport ekran görüntüleridir; Blender tanıtım render'ı veya çizim değildir.

Blender 4.3.2 ile üretici çalıştırıldı; GLB'nin iskeleti, Idle/Walk animasyonları
ve hareket eden kemikleri Godot'ta ayrıca doğrulandı. 4.7.2 / 5.2.3 hedef
sürümlerine yönelik bir test çalıştırılmadı. GPU'lu oyun cihazında test yok.

Görüntülerdeki geometrinin üretim kalitesinde olduğu, her pozda temasın doğru
olduğu veya üç karakter için hedef FPS yakalandığı iddia edilmez. Ölçüm
yöntemi ve ham veriler PERFORMANCE.md ve artifacts/ altında tutulur.
