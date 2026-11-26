# MIDNIGHT SYNDICATE — GRAPHICS RESCUE / EXECUTE, DO NOT PRETEND

Mevcut yarış oyununu kurtar. Bu dosya önceki grafik görevlerine göre önceliklidir. Kullanıcı düşük kaliteli şehir ve araçlardan memnun değil. Oyun motorunu değiştirmek veya sıfırdan oyun yapmak varsayılan çözüm değildir. Mevcut proje kaynaklarını koru. `MIDNIGHT_RESCUE/reference/ORTAKOY_CONCEPT.png` AI konseptidir; gerçek render değildir ve arka plan olarak kullanılamaz.

## 0 — Çalışma sınırları
- Önce `git status --short`, `git branch --show-current`, `git rev-parse HEAD`; kirli çalışma ağacını silme, stash/reset/checkout ile kullanıcı işini kaybetme. Temizse ayrı `fix/istanbul-graphics-rescue` dalı kullan. Kirliyse değişiklikleri koruyarak güvenli izole çalışma alanı kur veya engeli kaydet. Main'e yazma, merge/push/yayınlama yapma.
- Windows + RTX 5060 Ti 8 GB hedef donanımını gerçek komutla doğrula. 0 TL ek harcama; ücretli hizmet, otomatik ödeme, hesap oluşturma yok.
- Fable 5.2 yönetici / Haiku 5.5 işçi tercihidir, gerçek model adlarını ve erişimi doğrula. Erişilemezse mevcut modelle devam et. En fazla bir eşzamanlı alt ajan (yalnız bağımsız bir iş faydalıysa); uzun ajan zincirleri kurma. R.E.A./Replica kuruluysa yalnız kamuya açık davranış/teknik referans analizi için kullan. Kurulu olmayan skill çalışmış gibi yazma. Kurulum gereksizse atla. İzinleri aşma.
- Önce `skill/SKILL.md`, `02_ASSET_SOURCES.md`, `03_QUALITY_GATE.md` oku. Kullanılabilir Python varsa araçları çalıştır. Scriptler motor bağımsızdır; Blender scripti mevcut Blender sürümünde denenmeli.

## 1 — Baseline (önce kanıt)
- Motoru, çalıştırma komutunu, renderer'ı, kullanılan modelleri ve shader'ları belirle. `python MIDNIGHT_RESCUE/tools/project_scan.py .` çalıştır; bunu elle doğrula.
- Mevcut oyunu aç, gerçek yarıştan `evidence/before.png` al. Ekran yakalama yoksa blocker olarak yaz; başka resim üretme.
- Üç en kötü görsel kusurun nedenini belirle: model geometrisi, UV/materyal, çevre detayları, aydınlatma veya kamera. Yeni oyun mekanikleri geliştirme. Çalışan sürüş, fizik, yarış ve save sistemlerine dokunma.

## 2 — Önce varlık bul, sonra kodla
- Önce tek otomobil: `02_ASSET_SOURCES.md` içindeki gerçekçi GLB adaylarının önizlemesini incele, açık ticari dağıtım hakkını kontrol et. Uygun bir modeli yerelde indir. Araba geometrisini kendi primitive scriptinle üretme. Önce arka üç çeyrek ve gündüz görünümü kabul edilmeli; aksi halde başka aday seç.
- `tools/fetch_polyhaven.py asphalt_01` ile gerçek PBR dokuları edin; API başarısızsa resmi sayfadan elle indir. Prosedürel gürültü ile fotoğraf tabanlı materyal taklidi yapma.
- Ortaköy için sadece 100–250 metre kurgusal, kapalı yarış bölümü. Gerçek coğrafya değil görsel tanınabilirlik öncelikli. Yol genişliği oyuna uyarlanabilir. Ana landmark: Ortaköy Camii ve köprü silüeti. Lisanslı yüksek detaylı model yoksa mimari referanslardan özgün modelleme yap; düşük kaliteli modelle başka ilçelere geçme. OSM sadece konum/plan için, OSM2World final mesh yasak. Google Maps/Earth/Street View veya rakip oyundan mesh/doku çıkarma yok.
- Fotoğraflar yalnız hakları uygun olduğunda texture/scan için kullanılır. Fotogrametri için örtüşen, aynı yapıya ait çok açılı fotoğraf seti yoksa bunu çözüm diye sunma. Gerçekçi modüler cepheler (korniş, pencere derinliği, taş, balkon, vitrin) ve bağımsız landmark mesh kullan.
- Her kullanılan üçüncü taraf asset için `templates/ASSET_MANIFEST.example.json` formatında depo kökünde `asset_manifest.json` oluştur. URL, yazar, lisans, atıf, lisans kanıtı ve yerel yol kaydet. Lisans belirsizse release'e alma. `python MIDNIGHT_RESCUE/tools/validate_assets.py . asset_manifest.json` ile teknik kontrol et.

## 3 — Blender ve motor
- Blender kuruluysa CLI kullan; MCP gerekliyse resmi upstream talimatıyla kurulumunu incele ve bağlantıyı test et. Kullanıcı onayı gerektiren izinleri atlama. `blender -b -t 4 --python MIDNIGHT_RESCUE/tools/blender_asset_preview.py -- --model <GLB> --out evidence/car_preview` ile aday modelin gerçek önizlemesini üret. Blender'ın yolu PATH'te değilse tam yol kullan. Script hazır modeli render eder, profesyonel mesh üretmez.
- Aracın tekerlek pivotları, metre ölçeği, yönü, materyal slotları ve collision proxy kontrol edilsin. Gerekirse LOD'ları mesh sadeleştirme ile oluştur ve her LOD görselini kontrol et. Yakın araçta detay kaybı olmasın.
- Motorun mevcut renderer'ında PBR albedo/normal/roughness; araç clearcoat veya desteklenen eşdeğer; ıslak yol için roughness maskesi ve gerçek çevre yansımaları; baked ışık ve probe; sıcak sokak lambası / soğuk ortam; doğal kontrast. HDRI yalnız ışık/çevre için, gerçek binaların yerine koyma. Gece sis/neonla kusurları gizleme.
- Arka takip kamerasını ve mevcut HUD'u koru/iyileştir. Sahne 3D, araç sürülebilir, kamera hareket edebilir ve HUD gerçek state'ten beslenir.

## 4 — Stop/go: gerçek kanıt
- Gündüz ve gece aynı kamera ile `evidence/after_day.png`, `evidence/after_night.png`; gerçek yarış sırasında `evidence/gameplay.png`; mümkünse 10 sn kısa sürüş kaydı. Tüm çıktılar oyunun kendisinden, Blender render'ı ayrı klasörde.
- `03_QUALITY_GATE.md` tablosunu gerçek görseller üzerinden değerlendir. `templates/EVIDENCE.example.json` kopyasını `evidence/evidence.json` olarak doldur. Kullanıcının incelemesi için önce/sonra kanıtlarını sakla. `python MIDNIGHT_RESCUE/tools/check_evidence.py . evidence/evidence.json` çalıştır. Otomatik kontrol görsel gerçekçiliği doğrulamaz; görsel inceleme gereklidir.
- Bir kusur varsa en fazla iki hedefli düzeltme dene. Hâlâ başarısızsa yöntemi değiştir (asset kaynağı veya materyal); yeni harita, araç sayısı veya mekanik ekleme. Çözüm bulunmazsa çalışan sürümü koru ve gerçek engeli bildir.
- Görsel benchmark geçerse mevcut yarışın başlatma, bitiş, nitro, drift ve kayıt regression testlerini çalıştır. Performans için aynı sahnede frame-time / FPS ölç; PC ile iPhone sonuçlarını karıştırma. Sonrasında diğer bölgelere genişletme yapılabilir. AAA kalite veya App Store hazır iddiası ancak bağımsız görsel değerlendirme ve uygun cihaz/build doğrulaması ile yapılır.

## 5 — Teslim ve token kontrolü
- Uzun araştırma/rapor yerine bir sonraki somut işi uygula. `evidence/PROGRESS.md` maksimum 30 satır: HEAD, çalıştırma komutu, en son geçerli build, üç açık kusur, sonraki tek görev, engeller. Her önemli adımda güncelle.
- Mevcut test komutunu çalıştır, logun sadece sonuç ve hata bölümünü kaydet. Kullanıcı değişikliklerini commit'e dahil etme. Kendi doğrulanmış değişikliklerini ayrı commit yap; SHA'yı raporla.
- Teslim: gerçek önce/sonra görselleri, çalışan sahne, asset manifesti, build/test logları, FPS ölçümü ve SHA. iOS/Mac/Xcode yoksa açıkça bildir. Kullanım limiti oluşursa checkpoint'le dur. Kapsamı tamamlanmış gibi göstermeye çalışma.

Şimdi gerçek proje üzerinde başla. Bir başka master plan üretme.
