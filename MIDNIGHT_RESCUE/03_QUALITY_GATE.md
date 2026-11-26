# Ortaköy benchmark: kabul kapıları

Referans konsept görseli bir hedef; render motorunun birebir aynı çıktıyı vereceği varsayılmaz. Önce 100–250 m, tek araç, gerçek sürüş; diğer İstanbul bölgeleri duraklatılır. Teknik bütçeler başlangıç hedefidir, cihaz ölçümüyle değişebilir.

| Kapı | Kanıt | Kabul kriteri |
|---|---|---|
| G0: baseline | before.png + komut + commit | Mevcut oyun çalıştırıldı; görünen üç kusur tanımlandı |
| G1: araç | Blender gündüz/arka render + manifest | Gerçekçi oranlar, dört bağımsız tekerlek/pivot, kaporta birleşimi, cam ve stoplar; marka/lisans uygun; primitive placeholder yok |
| G2: landmark | gündüz motor ekranı | Cami kütlesi, kubbe/minareler, köprü silüeti ve cephe derinliği tanınır; aynı model tekrarları/OSM kutuları yok; özgün geometri veya lisanslı model |
| G3: gece | after_night.png | Yol üzerinde lokal yansımalar, kaporta yansıması, dengeli sıcak/soğuk ışık; aşırı bloom ile gizleme yok |
| G4: gameplay | gameplay.png + sürüş testi | Gerçek 3D, takip kamerası, hareket eden araç/tekerlekler, gerçek HUD; yarış başlat/bitir ve önceki mekanikler çalışıyor |
| G5: performans | cihaz adı, çözünürlük, preset, FPS + frame time | Aynı sahnede karşılaştırmalı ölçüm. 60 FPS hedefi 16.7ms, 30 FPS 33.3ms; iPhone testi yoksa PC ölçümünden mobil başarı çıkarma |
| G6: review | önce/sonra + SHA + test log | Kullanıcı görüntüleri inceler; ajan puanı tek başına kabul değil. Herhangi bir kritik görsel kusur varsa yeni bölge üretme. |

Teknik başlangıç bütçesi: yakın hero araba 50–100k üçgen, uzak rakipler 10–30k; 1–2K tekrar kullanılan texture setleri; landmark LOD ve instancing. Bu rakamlar doğrulanmış gereksinim değil; cihaz profiline göre ayarla. Görsel kaliteyi yalnız polygon sayısına bağlama.

Geçersiz kanıtlar: AI konsepti, Blender render'ını gameplay diye sunmak, sabit HUD, karanlıkta gizlenen model, sahte skor, varsayılan FPS, hiç çalıştırılmamış build. Scriptler teknik varlık/evidence kontrol eder; gerçek estetik kaliteyi insan veya görüntü incelemesi doğrular.
