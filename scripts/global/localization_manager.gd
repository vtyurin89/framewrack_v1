extends Node
## Autoload: loads CSV translations and switches locale (en primary; ru secondary).

signal language_changed(new_locale: String)

const CSV_PATHS: PackedStringArray = [
	"res://translations/translations.csv",
	"res://translations/traits.csv",
]
const FALLBACK_LOCALE := "en"
const SUPPORTED_LOCALES: PackedStringArray = ["en", "ru"]

var _loaded_paths: Dictionary = {}


func _ready() -> void:
	for path in CSV_PATHS:
		_load_translations_from_csv(path)
	_apply_fallback_locale(FALLBACK_LOCALE)
	# Primary default language.
	set_language(FALLBACK_LOCALE)


func _apply_fallback_locale(locale: String) -> void:
	## Portable fallback: ProjectSettings always works; setter varies by Godot version.
	ProjectSettings.set_setting("internationalization/locale/fallback", locale)
	if TranslationServer.has_method("set_fallback_locale"):
		TranslationServer.call("set_fallback_locale", locale)


func get_locale() -> String:
	return TranslationServer.get_locale()


func get_supported_locales() -> PackedStringArray:
	return SUPPORTED_LOCALES


func is_supported(locale_code: String) -> bool:
	return locale_code in SUPPORTED_LOCALES


func set_language(locale_code: String) -> void:
	var locale := locale_code
	if not is_supported(locale):
		push_warning("LocalizationManager: unsupported locale '%s'; falling back to %s." % [locale_code, FALLBACK_LOCALE])
		locale = FALLBACK_LOCALE
	TranslationServer.set_locale(locale)
	language_changed.emit(locale)


func cycle_language() -> String:
	## Convenience for a simple EN ↔ RU toggle button.
	var next := "ru" if get_locale().begins_with("en") else "en"
	set_language(next)
	return next


static func pick_en_ru(en: String, ru: String, fallback: String = "") -> String:
	## Runtime bilingual pick for content authored outside CSV (e.g. god JSON).
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("ru"):
		if not ru.is_empty():
			return ru
		if not fallback.is_empty():
			return fallback
		return en
	if not en.is_empty():
		return en
	if not fallback.is_empty():
		return fallback
	return ru


func _load_translations_from_csv(path: String) -> void:
	if _loaded_paths.has(path):
		return
	if not FileAccess.file_exists(path):
		push_error("LocalizationManager: missing translation CSV at %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LocalizationManager: failed to open %s" % path)
		return

	var header: PackedStringArray = file.get_csv_line()
	if header.is_empty() or header[0] != "keys":
		push_error("LocalizationManager: CSV must start with 'keys' column (%s)." % path)
		return

	var translations: Dictionary = {}  # locale -> Translation
	for i in range(1, header.size()):
		var locale := String(header[i]).strip_edges()
		if locale.is_empty():
			continue
		var t := Translation.new()
		t.locale = locale
		translations[locale] = t

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty():
			continue
		var key := String(row[0]).strip_edges()
		if key.is_empty() or key.begins_with("#"):
			continue
		for i in range(1, header.size()):
			var locale := String(header[i]).strip_edges()
			if not translations.has(locale):
				continue
			var message := ""
			if i < row.size():
				message = String(row[i])
			(translations[locale] as Translation).add_message(key, message)

	for locale in translations.keys():
		TranslationServer.add_translation(translations[locale])

	_loaded_paths[path] = true
