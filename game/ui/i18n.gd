class_name I18n
extends RefCounted
## Every visible UI string goes through I18n.t(key). Language comes from Settings.language ("tr" or "en").
## Every key must have both languages (checked by tests/test_ui.gd).

const DICT: Dictionary = {
	"menu.race": {"tr": "YARIŞ", "en": "RACE"},
	"menu.garage": {"tr": "GARAJ", "en": "GARAGE"},
	"menu.settings": {"tr": "AYARLAR", "en": "SETTINGS"},
	"menu.quit": {"tr": "ÇIKIŞ", "en": "QUIT"},
	"menu.version": {"tr": "SÜRÜM %s", "en": "VERSION %s"},
	"menu.tagline": {"tr": "GECE SOKAK YARIŞI", "en": "NIGHT STREET RACING"},
	"menu.coming_soon": {"tr": "Yakında", "en": "Coming soon"},
	"hud.lap": {"tr": "TUR", "en": "LAP"},
	"hud.lap_of": {"tr": "%d / %d", "en": "%d / %d"},
	"hud.of": {"tr": "/ %d", "en": "/ %d"},
	"hud.time": {"tr": "SÜRE", "en": "TIME"},
	"hud.lap_time": {"tr": "TUR SÜRESİ", "en": "LAP TIME"},
	"hud.best": {"tr": "EN İYİ", "en": "BEST"},
	"hud.kmh": {"tr": "km/sa", "en": "KM/H"},
	"hud.nitro": {"tr": "NİTRO", "en": "NITRO"},
	"hud.drift": {"tr": "DRIFT", "en": "DRIFT"},
	"hud.banked": {"tr": "KAYDEDİLDİ", "en": "BANKED"},
	"hud.wrong_way": {"tr": "TERS YÖN", "en": "WRONG WAY"},
	"hud.go": {"tr": "BAŞLA", "en": "GO"},
	"hud.finished": {"tr": "BİTTİ", "en": "FINISHED"},
	"hud.gear_reverse": {"tr": "R", "en": "R"},
	"hud.gear_neutral": {"tr": "N", "en": "N"},
	"hud.no_time": {"tr": "--:--.--", "en": "--:--.--"},
	"ord.st": {"tr": ".", "en": "ST"},
	"ord.nd": {"tr": ".", "en": "ND"},
	"ord.rd": {"tr": ".", "en": "RD"},
	"ord.th": {"tr": ".", "en": "TH"},
	"results.title": {"tr": "SONUÇLAR", "en": "RESULTS"},
	"results.won": {"tr": "KAZANDIN", "en": "YOU WON"},
	"results.done": {"tr": "YARIŞ BİTTİ", "en": "RACE COMPLETE"},
	"results.col_pos": {"tr": "SIRA", "en": "POS"},
	"results.col_driver": {"tr": "SÜRÜCÜ", "en": "DRIVER"},
	"results.col_time": {"tr": "SÜRE", "en": "TIME"},
	"results.col_gap": {"tr": "ARA", "en": "GAP"},
	"results.col_best": {"tr": "EN İYİ TUR", "en": "BEST LAP"},
	"results.leader": {"tr": "LİDER", "en": "LEADER"},
	"results.reward_cash": {"tr": "NAKİT", "en": "CASH"},
	"results.reward_rep": {"tr": "İTİBAR", "en": "REP"},
	"results.retry": {"tr": "TEKRAR", "en": "RETRY"},
	"results.garage": {"tr": "GARAJ", "en": "GARAGE"},
	"results.menu": {"tr": "MENÜ", "en": "MENU"},
	"pause.title": {"tr": "DURAKLATILDI", "en": "PAUSED"},
	"pause.resume": {"tr": "DEVAM ET", "en": "RESUME"},
	"pause.restart": {"tr": "YENİDEN BAŞLA", "en": "RESTART"},
	"pause.settings": {"tr": "AYARLAR", "en": "SETTINGS"},
	"pause.quit": {"tr": "MENÜYE DÖN", "en": "QUIT TO MENU"},
	"settings.title": {"tr": "AYARLAR", "en": "SETTINGS"},
	"settings.graphics": {"tr": "GRAFİK", "en": "GRAPHICS"},
	"settings.preset": {"tr": "KALİTE", "en": "QUALITY"},
	"settings.preset_low": {"tr": "DÜŞÜK", "en": "LOW"},
	"settings.preset_medium": {"tr": "ORTA", "en": "MEDIUM"},
	"settings.preset_high": {"tr": "YÜKSEK", "en": "HIGH"},
	"settings.dynres": {"tr": "DİNAMİK ÇÖZÜNÜRLÜK", "en": "DYNAMIC RESOLUTION"},
	"settings.audio": {"tr": "SES", "en": "AUDIO"},
	"settings.master": {"tr": "ANA SES", "en": "MASTER"},
	"settings.music": {"tr": "MÜZİK", "en": "MUSIC"},
	"settings.sfx": {"tr": "EFEKTLER", "en": "EFFECTS"},
	"settings.engine": {"tr": "MOTOR", "en": "ENGINE"},
	"settings.controls": {"tr": "KONTROLLER", "en": "CONTROLS"},
	"settings.steering": {"tr": "DİREKSİYON", "en": "STEERING"},
	"settings.steer_buttons": {"tr": "DÜĞMELER", "en": "BUTTONS"},
	"settings.steer_tilt": {"tr": "EĞME", "en": "TILT"},
	"settings.auto_accel": {"tr": "OTOMATİK GAZ", "en": "AUTO ACCELERATE"},
	"settings.haptics": {"tr": "TİTREŞİM", "en": "HAPTICS"},
	"settings.camera_shake": {"tr": "KAMERA SARSINTISI", "en": "CAMERA SHAKE"},
	"settings.language": {"tr": "DİL", "en": "LANGUAGE"},
	"settings.lang_tr": {"tr": "TÜRKÇE", "en": "TÜRKÇE"},
	"settings.lang_en": {"tr": "ENGLISH", "en": "ENGLISH"},
	"settings.on": {"tr": "AÇIK", "en": "ON"},
	"settings.off": {"tr": "KAPALI", "en": "OFF"},
	"common.back": {"tr": "GERİ", "en": "BACK"},
}

const ORDINAL_SUFFIX_KEYS: Dictionary = {1: "ord.st", 2: "ord.nd", 3: "ord.rd"}


## Current language's text for key. Falls back to English, then to the key itself.
static func t(key: String) -> String:
	if not DICT.has(key):
		push_warning("I18n: unknown key " + key)
		return key
	var entry: Dictionary = DICT[key]
	var lang: String = Settings.language
	return str(entry.get(lang, entry.get("en", key)))


static func has_key(key: String) -> bool:
	return DICT.has(key)


static func all_keys() -> Array:
	return DICT.keys()


## Ordinal suffix for a 1-based place: "ST", "ND", "RD", "TH" in English, "." in Turkish.
static func ordinal(n: int) -> String:
	if Settings.language == "tr":
		return t("ord.st")
	var tens: int = n % 100
	if tens >= 11 and tens <= 13:
		return t("ord.th")
	var one: int = n % 10
	if ORDINAL_SUFFIX_KEYS.has(one):
		return t(ORDINAL_SUFFIX_KEYS[one])
	return t("ord.th")
