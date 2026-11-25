# Body Lab → Aero → Godot

**Durum:** Body Lab kataloğu ve ona bağlı GLB'ler Aero'ya alınır. Beden veya iç giyside seçilen üçgenler, ilgili giysi kuşanıldığında gizlenir. Hazırlık kaydı Aero'da, oyun kuralları Godot kataloğunda tutulur.

1. Blender'da giysiyi hazırla ve oyuna aktar. Aero, `data/wardrobe/adventure.json` kaydındaki GLB yollarını kullanır. Giysi Stüdyosu'nun canlı beden GLB'siyle eşleşen mevcut yüz grupları açılışta korunur.
2. Aero projesini aç, F5 → **Body Lab · örtülen yüzleri düzenle**. Doğrudan açılış: `godot --path AeroCloth3D res://demo/AdventureAuthoring.tscn`.
3. **Klasör seç…** ile kaynak Godot proje klasörünü seç → **Adventure setini kopyala / aç**. Katalog ve bağlı GLB'ler Aero çalışma kopyasına alınır. Godot içe aktarımı arka planda tamamlanınca set açılır.
4. Örtülecek **iç giysiyi**, mesh'ini ve malzeme yüzeyini seç. **İç giysiyi göster / tüm set** ile dış katmanları kaldır. Sağ sürükle döner; tekerlek yakınlaşır. Sol sürükle yüz seçer; Shift seçimden çıkarır. Fırça yarıçapı 0 tek üçgen seçer.
5. Gruba anlamlı bir ad ver (`bluz_korse_alti`). Gizlemeyi gerektiren dış giysiyi seç; birden fazla seçildiğinde **hepsi** giyilmiş olmalı. **Seçimi gizle / göster** sonucu geçici olarak gösterir.
6. **Yüz grubu + gizleme kuralını uygula**, sonra **Çalışma kataloğunu kaydet**. Mevcut yüz grubunu listeden seçip düzenleyebilirsin. Yeni grup adı yeni kural oluşturur; mevcut grup aynı kurala yazılır. Kaydet/Aktar yalnız uygulanmış kuralları içerir.
7. **Klasör seç…** ile hedef Godot projesini seç (başlangıçta kaynak klasör) → **Godot'a aktar**. Vücut dahil altı GLB `assets/body_lab/`, kurallar `data/wardrobe/adventure.json` içine gider. Oyunun adventure kataloğunu açıp dış giysiyi çıkar/tak: gizlenen iç yüzler geri gelmeli.

**Kayıt anlamı:** `parts.<grup>.faces` yüzey ve üçgen kimliklerini; `rules.hide-<grup>` dış giysi koşulunu ve `actions.hide_parts` eylemini taşır. Bu işlem oyunda yalnız çizilen üçgen indekslerini filtreler; ağırlıkları/morph'ları korur. Kalıcı model kesme Blender'da ayrı bir model değişikliğidir.

**Sınır:** Beden için listeden **BEDEN · giysi altında kalan yüzler → CC_Base_Body** seç. Tam örtülen yüzleri seçip koşula ilgili giysiyi ekle; açıklık kenarlarında pay bırak. Beden grupları `body.masking.parts/rules` içinde saklanır; giysi çıkınca beden geri gelir. Önizleme dinlenme pozundadır; koşul/morph sayısal düzenlemesi **Koşul ve morph kuralları** düğmesindedir. Animasyonlu uyum oyunda kontrol edilir. Yeniden **kopyala / aç** çalışma kopyasını kaynak oyun kataloğuyla değiştirir; kaydedilmemiş düzenleme varsa işlem durur. Kaydetme çalışma kaydını korur; kaynak oyunda da saklamak için önce oyuna aktar.

**Topoloji:** Aero gerçek Godot içe aktarılmış mesh'lerini kullanır; ham Blender poligon kimliği kullanılmaz. GLB importunda LOD üretimi kapatılır. Yüz grupları içe aktarılmış yüzey topoloji hash'i taşır; değişen mesh'te tekrar seçim gerekir. GLB dosyası hazırlıktan sonra değişirse dışa aktarım durur. Blender yeniden dışa aktarma ve değişen topoloji davranışı kaynak projenin sorumluluğundadır.

**Kontrol:** `godot --headless --path AeroCloth3D --script tests/test_adventure_authoring.gd` (seti bir kez içe aktardıktan sonra). Test beden ve beş giysi/15 mesh, gövde aktarımı, üçgen sırası, koşul ve kaynak geometrisinin korunmasını denetler. [Önceki köprü](WARDROBE_BRIDGE.md) ve [oyun tarafındaki kaynak hazırlama akışı](https://github.com/uuzdnzgzn/project-riot-of-sarrows/blob/feature/clothing-authoring-combat/docs/giysi-hazirlama-akisi.md).
