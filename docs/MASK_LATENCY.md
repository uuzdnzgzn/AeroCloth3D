# Hasar maskesi ölçümü

Kesik fırçası, etkisinin sıfır olacağı piksellerde gürültü ve piksel işlemlerini atlar. Bağımsız referans testinde 48 açı, UV konumu ve seed kombinasyonu; üst üste boyama ve silgiyle RGBA ve yükseklik verisi birebir eşleşti.

Üç karakter, 600 kare ve olay başına altı darbe içeren yazılımsal llvmpipe ölçümünde bütün maskelerin yayımlandığının gözlemlenmesine kadar en uzun süre önceki koşuda 336,81 ms, yeni koşuda 196,33 ms idi. Tek koşu karşılaştırmasıdır; sistem yükü ve kare sınırında gözlem süreyi etkiler. Ortalama kare süresi sırasıyla 35,30 ve 34,27 ms; p99 68,95 ve 80,18 ms ölçüldü. Ham veri `artifacts/mask-optimization-rendered.json` içindedir.

Bu metrik ilk görünür piksel veya tek maske işleme süresi değildir. GTX 1650 üzerinde ölçüm yapılmadı. Eski nesil işlerin CPU çalışması tamamlanana kadar sürmesi, worker kuyruğu, doku yayını ve gerçek GPU görünme süresi ayrı profil gerektirir.

## Eski işlerin iptali

Yeni darbe, senkron sıfırlama/yükleme veya sahneden ayrılma eski işçiden
durmasını ister. İşçi iptali fırça işlemleri arasında Mutex ile kontrol eder;
tek bir fırça sürerken o işlemin bitmesini bekler. Nesil kontrolü eski sonuçların
yayımlanmasını engellemeyi sürdürür. Gerçek WorkerThreadPool iptali, hızlı darbe,
reset ve eşdeğer sonuç async regresyon testinde doğrulanır. Bu değişikliğin ayrı
performans kazancı ve hedef cihazdaki etkisi henüz ölçülmedi.
