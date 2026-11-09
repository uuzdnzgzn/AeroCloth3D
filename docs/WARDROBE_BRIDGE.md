# Godot giysi köprüsü

**Durum:** Çalışan katalog düzenleme ve GLB aktarım denemesi. Aero giysi kaynağını düzenler; hedef oyunun katalog doğrulayıcısı ve resolver'ı çalışma davranışını belirler.

`demo/wardrobe_trial/catalog.json`, hedef oyunun v1 katalog biçimindedir. Control sahnesinde `scripts/wardrobe_bridge.gd` kullan: giysi ve mevcut kuralı seç; `when.all_items`, sabit morph ve `actions.hide_parts` alanlarını düzenle. Morph seçilmezse mevcut morph eylemleri korunur. Kaydet kaynak JSON'u, aktar hedef proje dosyalarını günceller. Diğer koşul ve eylemler korunur.

```sh
godot --headless --path /workspace/AeroCloth3D \
  --script scripts/export_wardrobe.gd -- \
  --target-project /workspace/prototype
```

İsteğe bağlı `--catalog res://...json` başka kaynak seçer. Aktarım, her varyantın bağımsız GLB'sini hedef `assets/aero_trial/` altına kopyalar; sahne yollarını yeniden yazar ve `data/wardrobe/aero_trial.json` üretir. Dosya adı çakışması, eksik GLB veya proje dışına çıkan yol reddedilir. Aynı hedef dosyalar sonraki aktarımda güncellenir. Yüz gruplarının üçgen kimliklerini korumak için yalnız aktarılan GLB dosyalarının `.import` ayarında `meshes/generate_lods=false` yazılır; mevcut UID ve diğer ayarlar korunur. İlk içe aktarmada da bu ayar kullanılır. Hedef oyun bu kataloğu açıkça yüklemelidir.

**Sınır:** Köprü düzenlediği alanların kimlik başvurularını denetler. Tam oyun şeması, sahne mesh/morph adları ve çözülmüş giyim sonucu hedef oyunda doğrulanır. Bu arayüz yeni mesh veya yeni kural üretmez.

Kontrol: `godot --headless --path /workspace/AeroCloth3D --script tests/test_wardrobe_bridge.gd` — düzenleme korunumu, hatalı başvurular, JSON/GLB aktarımı, yol reddi, kuralsız giysi seçimi, mevcut içe aktarma ayarlarının korunması ve yeni Godot projesinde ilk GLB içe aktarımı.

## Gerçek deneme varlıkları

`demo/wardrobe_trial/wardrobe_trial.blend` orijinal Neutral_F rig'i üzerinde ayrı kayıttır. Üç GLB, kemik ağırlıkları, `Tucked`/`NeckFit` ve gömlekte `hem` yüz grubu vardır. `blender_report.json` üretim sayımlarını içerir. Yeniden üretim:

```sh
blender --background --python scripts/create_wardrobe_trial.py -- /tam/yol/Neutral_F_sword_trial.blend
godot --headless --path . --script scripts/build_wardrobe_trial.gd
```

F5 köprü penceresini açar; hedef klasörü seçip aktar. Oyunda F12 → Aero denemesini yükle → Bel/Boyun yuvasından giy/çıkar → Kuşan. Kaynak `.blend` gövdeyi de içerir; GLB'ler yalnız seçili giysi ve armature içerir. Modeller teknik denemedir; serbest kesme veya genel otomatik fit değildir.

3B Aero çalışma alanında **Karakter GLB seç** için `demo/wardrobe_trial/character.glb`, giysi eklemek için aynı klasördeki `shirt.glb`, `corset.glb`, `collar.glb` seçilebilir. Bu köprü kuralları JSON'da tutar; 3B alanın `.tres` hasar kaynaklarıyla otomatik senkronizasyon henüz yoktur.
