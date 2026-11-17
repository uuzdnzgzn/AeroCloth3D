# Body Lab → Aero → Godot

**Durum:** Adventure setinin altı GLB'si ve kataloğu Aero'ya alınır; iç giyside seçilen üçgenler dış giysi koşuluyla gizlenir. Kaynak Blender/GLB geometrisi silinmez. Hazırlık kaydı Aero'da, oyun kuralları Godot kataloğunda tutulur.

1. Blender'da Body Lab karakterini/giysisini hazırla ve oyuna aktar: oyun klasöründe `assets/body_lab/*.glb`, `data/wardrobe/adventure.json` bulunmalı. Parçaların kemik ağırlıkları ve morph'ları GLB'de kalır.
2. Aero projesini aç, F5 → **Body Lab · örtülen yüzleri düzenle**. Doğrudan açılış: `godot --path AeroCloth3D res://demo/AdventureAuthoring.tscn`.
3. **Klasör seç…** ile kaynak Godot proje klasörünü seç → **Adventure setini kopyala / aç**. Altı GLB `assets/adventure_work/` içine, katalog `data/wardrobe/adventure_work.json` içine kopyalanır. Godot içe aktarımı arka planda çalışır; süre ekranda görünür, pencere kullanılabilir. Tamamlanınca set açılır ve klasör seçimleri korunur.
4. Örtülecek **iç giysiyi**, mesh'ini ve malzeme yüzeyini seç. **İç giysiyi göster / tüm set** ile dış katmanları kaldır. Sağ sürükle döner; tekerlek yakınlaşır. Sol sürükle yüz seçer; Shift seçimden çıkarır. Fırça yarıçapı 0 tek üçgen seçer.
5. Gruba anlamlı bir ad ver (`bluz_korse_alti`). Gizlemeyi gerektiren dış giysiyi seç; birden fazla seçildiğinde **hepsi** giyilmiş olmalı. **Seçimi gizle / göster** sonucu geçici olarak gösterir.
6. **Yüz grubu + gizleme kuralını uygula**, sonra **Çalışma kataloğunu kaydet**. Mevcut yüz grubunu listeden seçip düzenleyebilirsin. Yeni grup adı yeni kural oluşturur; mevcut grup aynı kurala yazılır. Kaydet/Aktar yalnız uygulanmış kuralları içerir.
7. **Klasör seç…** ile hedef Godot projesini seç (başlangıçta kaynak klasör) → **Godot'a aktar**. Vücut dahil altı GLB `assets/body_lab/`, kurallar `data/wardrobe/adventure.json` içine gider. Oyunun adventure kataloğunu açıp dış giysiyi çıkar/tak: gizlenen iç yüzler geri gelmeli.

**Kayıt anlamı:** `parts.<grup>.faces` yüzey ve üçgen kimliklerini; `rules.hide-<grup>` dış giysi koşulunu ve `actions.hide_parts` eylemini taşır. Bu işlem oyunda yalnız çizilen üçgen indekslerini filtreler; ağırlıkları/morph'ları korur. Kalıcı model kesme Blender'da ayrı bir model değişikliğidir.

**Sınır:** Bu ekranda yüz seçimi giysiler içindir. Önizleme dinlenme pozundadır; koşul/morph sayısal düzenlemesi **Koşul ve morph kuralları** düğmesindedir. Animasyonlu uyum oyunda kontrol edilir. Yeniden **kopyala / aç** çalışma kopyasını kaynak oyun kataloğuyla değiştirir; kaydedilmemiş düzenleme varsa işlem durur. Kaydetme çalışma kaydını korur; kaynak oyunda da saklamak için önce oyuna aktar.

**Topoloji:** Aero gerçek Godot içe aktarılmış mesh'lerini kullanır; ham Blender poligon kimliği kullanılmaz. GLB importunda LOD üretimi kapatılır. Yüz grupları içe aktarılmış yüzey topoloji hash'i taşır; değişen mesh'te tekrar seçim gerekir. GLB dosyası hazırlıktan sonra değişirse dışa aktarım durur. Blender yeniden dışa aktarma ve değişen topoloji davranışı kaynak projenin sorumluluğundadır.

**Kontrol:** `godot --headless --path AeroCloth3D --script tests/test_adventure_authoring.gd` (seti bir kez içe aktardıktan sonra). Test beş giysi/11 mesh, gövde aktarımı, üçgen sırası, koşul ve kaynak geometrisinin korunmasını denetler. [Önceki köprü](WARDROBE_BRIDGE.md) ve [oyun tarafındaki kaynak hazırlama akışı](https://github.com/uuzdnzgzn/project-riot-of-sarrows/blob/feature/clothing-authoring-combat/docs/giysi-hazirlama-akisi.md).
