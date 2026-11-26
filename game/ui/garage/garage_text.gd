class_name GarageText
extends RefCounted
## TR and EN strings for the car shop. i18n.gd belongs to another change: to merge, copy DICT into I18n.DICT and
## replace GarageText.t(...) with I18n.t(...). Until then t() falls back to I18n for every other key.

const DICT: Dictionary = {
	"garage.class_hatch": {"tr": "SICAK HATCH", "en": "HOT HATCH"},
	"garage.class_classic": {"tr": "KLASİK TUNING", "en": "CLASSIC TUNER"},
	"garage.class_muscle": {"tr": "MUSCLE", "en": "MUSCLE"},
	"garage.class_gt": {"tr": "GT", "en": "GT"},
	"garage.car_buy": {"tr": "SATIN AL  %d TL", "en": "BUY  $%d"},
	"garage.car_select": {"tr": "SEÇ", "en": "SELECT"},
	"garage.car_selected": {"tr": "SEÇİLİ", "en": "SELECTED"},
	"garage.car_rep": {"tr": "KİLİTLİ · %d İTİBAR", "en": "LOCKED · %d REP"},
	"garage.car_bought": {"tr": "ARAÇ ALINDI", "en": "CAR PURCHASED"},
	"garage.car_not_owned": {"tr": "ÖNCE ARACI AL", "en": "BUY THE CAR FIRST"},
	"garage.car_selected_msg": {"tr": "ARAÇ SEÇİLDİ", "en": "CAR SELECTED"},
	"garage.not_enough_car": {"tr": "YETERSİZ NAKİT", "en": "NOT ENOUGH CASH"},
}


static func t(key: String) -> String:
	if not DICT.has(key):
		return I18n.t(key)
	var entry: Dictionary = DICT[key]
	return str(entry.get(Settings.language, entry.get("en", key)))
