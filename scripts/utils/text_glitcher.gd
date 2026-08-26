class_name TextGlitcher
extends RefCounted
## Converts readable strings into corrupted Unicode glitch text for the Hacked UI.

const GLITCH_CHARS := "*&%&%%(^%^R#$@!░▒▓█§№<>/\\|[]"


static func glitchify(original_text: String) -> String:
	var glitched := ""
	for i in original_text.length():
		var ch := original_text[i]
		if ch == " " or ch == "\n":
			glitched += ch
		else:
			glitched += GLITCH_CHARS[randi() % GLITCH_CHARS.length()]
	return glitched
