# Kaynak ve edinme sırası — 26.11.2026

Kaynaklar ön eleme içindir. İndirme, mesh kalitesi ve oyuna dağıtım hakkı her bir dosya için yeniden doğrulanmalı. Bu pakette üçüncü taraf modeller yoktur.

| Öncelik | Kaynak | İş | Lisans / kontrol |
|---|---|---|---|
| P0 | https://vinish.dev/free-3d-models/realistic-cars | Detaylı araç GLB adayları | Sayfa CC BY 4.0 bildiriyor; araç başına atıf, marka ve geometri kontrolü |
| P0 | https://vinish.dev/free-3d-models/sports-cars | Spor coupe ve supercar adayları | CC BY 4.0 bildiriliyor; aynı kontroller |
| P0 | https://polyhaven.com/a/asphalt_01 | Fotoğraf tabanlı asfalt | CC0 |
| P0 | https://polyhaven.com/textures | Taş, beton, metal, kaldırım | CC0; normal ve roughness indir |
| P0 | https://polyhaven.com/models | Şehir mobilyası, çevre detayları | CC0; model bazında incele |
| P1 | https://polyhaven.com/hdris | Gece/dusk çevre aydınlatması | CC0; HDRI ile çevreyi düz resme dönüştürme |
| P1 | https://ambientcg.com/ | Yüzey alternatifleri | Varlık lisansını kaydet |
| P1 | https://sketchfab.com/3d-models/istanbul-galata-tower-model-4778557dd0c54152aec8e77864f59e09 | Galata adayı (sonraki aşama) | CC Attribution listeleniyor; indirme ve kalite doğrulanmadı |
| Araç | https://github.com/ahujasid/mcp-for-blender | İsteğe bağlı Blender kontrolü | Güvenli kurulum ve bağlantı testi gerekli; ücretli entegrasyonları kullanma |
| Araç | https://www.blender.org/download/ | Yerel DCC ve CLI | Blender kurulumu ve GPU testi gerekli |
| İsteğe bağlı | https://www.realityscan.com/ / https://github.com/alicevision/meshroom | Gerçek örtüşen fotoğraf setiyle fotogrametri | Güncel kullanım şartları, donanım ve fotoğraf haklarını kontrol et |

Poly Haven API: https://polyhaven.com/our-api — GET /files/{id}, özgün User-Agent, dosya hash'i. Varlıklar CC0; canlı API ürün içinde kullanılırsa kaynak atfı gerekir. Yardımcı script yalnız geliştirme sırasında yerel indirme yapar.

**Ortaköy riski:** Cami ve köprünün ticari kullanıma hazır, yüksek kaliteli ücretsiz modeli henüz doğrulanmadı. Bir model bulmadan bunu tamamlanmış sayma. Lisanslı özgün geometri için maliyetsiz alternatif, yeterli mimari fotoğraf/referans ve Blender'da gerçek modelleme. OSM/OSM2World yalnız geometrik blokaj; fotogerçekçi cephe değil. Her hazır asset aynı sanat yönüne uymayabilir.

Claude Code skill/agent konfigürasyonu: https://code.claude.com/docs/en/settings ve https://code.claude.com/docs/en/skills . Sürüm ve hesap erişimi doğrulansın. Fable/Haiku adlarını zorla varsayma. Ek ajanların tüketimi sıfır değildir.
