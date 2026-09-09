class_name StatCheckLog
extends RefCounted
## Flavored diagnostic log lines for the skill-check modal.
## Pools + weighted picking only — never affects dice / success outcomes.

enum Category {
	ANALYSIS,
	SUCCESS,
	FAILURE,
	PERSONALITY,
	MEMORY,
	ERROR,
	RECOVERY,
	RARE,
}

## Relative pick weights for post-roll optional flavour (not equal).
const WEIGHT_PERSONALITY := 28.0
const WEIGHT_RECOVERY := 34.0
const WEIGHT_ERROR := 22.0
const WEIGHT_MEMORY := 10.0
const WEIGHT_RARE := 2.0

const RECENT_LIMIT := 10

const ANALYSIS: PackedStringArray = [
	"Analyzing outcome...",
	"Calculating probability...",
	"Evaluating response...",
	"Cross-referencing baseline...",
	"Pattern recognized.",
	"Running comparison...",
	"Weighing variables...",
	"Assessing input.",
	"Signal stable.",
	"Processing sequence...",
	"Outcome pending.",
	"Checking prior data...",
	"Aligning parameters...",
	"Scanning for precedent...",
	"Comparing to threshold...",
	"Sequence initiated.",
	"Data insufficient. Proceeding anyway.",
	"Estimating margin.",
	"Confidence: uncertain.",
	"Awaiting resolution...",
]

const SUCCESS: PackedStringArray = [
	"Outcome acceptable.",
	"Pattern holds.",
	"This is working.",
	"I did it again.",
	"That was easy.",
	"I knew that.",
	"I can do this.",
	"Good.",
	"That felt right.",
	"Confidence rising.",
	"On track.",
	"I remember how this goes.",
	"Steady.",
	"This part I know.",
	"Almost natural.",
	"That was close, but fine.",
	"Working as intended.",
	"No hesitation this time.",
	"I'm still here.",
]

const FAILURE: PackedStringArray = [
	"This was just too hard.",
	"That didn't work.",
	"I don't like this.",
	"Something went wrong.",
	"Try again.",
	"I wasn't ready.",
	"Not this time.",
	"That shouldn't have failed.",
	"Off balance.",
	"Miscalculated.",
	"I lost it.",
	"Wrong again.",
	"This keeps happening.",
	"That hurt more than it should have.",
	"I don't understand why.",
	"Not good enough.",
	"Something slipped.",
	"I hesitated.",
]

const PERSONALITY: PackedStringArray = [
	"Why did I do that.",
	"That felt familiar.",
	"I don't know why I said that.",
	"This isn't really me.",
	"Or maybe it is.",
	"I keep doing this.",
	"Someone taught me this. I think.",
	"I don't remember deciding.",
	"That was automatic.",
	"Was that me?",
	"I didn't choose that. Or I did.",
	"It's easier not to ask.",
	"I feel like I'm watching.",
	"That's not how I meant to respond.",
	"I keep forgetting who's asking.",
	"It's fine. Probably.",
	"I don't mind. I think.",
	"This body knows more than I do.",
]

const MEMORY: PackedStringArray = [
	"I remember this.",
	"Have we done this before?",
	"That felt familiar.",
	"I knew what would happen.",
	"Something is missing.",
	"Where did that come from?",
	"Again.",
	"Again?",
	"I shouldn't know this.",
	"This has happened before.",
	"I recognize this feeling.",
	"There was someone else here.",
	"I've held this before.",
	"This isn't the first time.",
	"I forgot, and now I remember.",
	"That name again.",
	"I don't know where that came from.",
	"This place. I know this place.",
	"No. I don't.",
]

const ERROR: PackedStringArray = [
	"Error. Restoring to default.",
	"Data corrupted.",
	"Signal lost.",
	"Recalculating...",
	"Sequence interrupted.",
	"Unexpected input.",
	"Response invalid.",
	"System fault.",
	"Discrepancy detected.",
	"Unable to verify.",
	"Conflict in data.",
	"Retry required.",
	"Checksum failed.",
	"Unknown state.",
	"Process aborted.",
	"Fragmented output.",
	"Reading error.",
	"Null response.",
]

const RECOVERY: PackedStringArray = [
	"Restoring baseline.",
	"Recalibrating...",
	"Adjusting.",
	"Stabilizing.",
	"Returning to default.",
	"Resetting parameters.",
	"Compensating.",
	"Realigning.",
	"Holding steady.",
	"Back online.",
	"Correcting drift.",
	"Reinitializing.",
	"Balance restored.",
	"Continuing.",
	"Systems nominal. Probably.",
	"Adapting.",
	"Steady now.",
]

const RARE: PackedStringArray = [
	"I remember doing this.",
	"Why do I remember this?",
	"This wasn't my first attempt.",
	"Who taught me this?",
	"That response was already there.",
	"Memory conflict.",
	"I know this place.",
	"I don't know this place.",
	"This isn't the first body.",
	"Someone else answered first.",
	"I recognize my own hesitation.",
	"That wasn't a guess.",
]

## Recent lines excluded from immediate re-picks (session-scoped).
var _recent: Array[String] = []


static func pool(category: Category) -> PackedStringArray:
	match category:
		Category.ANALYSIS:
			return ANALYSIS
		Category.SUCCESS:
			return SUCCESS
		Category.FAILURE:
			return FAILURE
		Category.PERSONALITY:
			return PERSONALITY
		Category.MEMORY:
			return MEMORY
		Category.ERROR:
			return ERROR
		Category.RECOVERY:
			return RECOVERY
		Category.RARE:
			return RARE
		_:
			return ANALYSIS


static func random_line(category: Category) -> String:
	var pool_arr := pool(category)
	if pool_arr.is_empty():
		return ""
	return pool_arr[randi() % pool_arr.size()]


func clear_recent() -> void:
	_recent.clear()


func pick(category: Category) -> String:
	var pool_arr := pool(category)
	if pool_arr.is_empty():
		return ""
	var candidates: Array[String] = []
	for line in pool_arr:
		if not _recent.has(line):
			candidates.append(line)
	if candidates.is_empty():
		candidates.assign(Array(pool_arr))
	var chosen: String = candidates[randi() % candidates.size()]
	_remember(chosen)
	return chosen


func compose_analysis_lines() -> Array[String]:
	## Very common ANALYSIS: 2–3 lines before dice resolve.
	var count := 2 + (randi() % 2)
	var out: Array[String] = []
	for _i in count:
		var line := pick(Category.ANALYSIS)
		if not line.is_empty():
			out.append(line)
	return out


func compose_reaction_lines(
	is_success: bool,
	successes: int = -1,
	threshold: int = 1
) -> Array[String]:
	## Primary SUCCESS/FAILURE reaction, then occasional secondary flavour.
	var out: Array[String] = []
	var primary := Category.SUCCESS if is_success else Category.FAILURE
	var first := _pick_contextual_primary(primary, is_success, successes, threshold)
	if not first.is_empty():
		out.append(first)
	## ~45% chance of a second primary beat (still common).
	if randf() < 0.45:
		var second := pick(primary)
		if not second.is_empty() and second != first:
			out.append(second)
	## Occasional / rare secondary layer — not guaranteed.
	if randf() < 0.38:
		var extra := _pick_weighted_secondary()
		if not extra.is_empty():
			out.append(extra)
	return out


func _pick_contextual_primary(
	primary: Category,
	is_success: bool,
	successes: int,
	threshold: int
) -> String:
	## Optional close-call bias; falls back to normal weighted pick.
	if successes < 0 or threshold <= 0:
		return pick(primary)
	var margin := successes - threshold
	if is_success and margin == 0:
		## Barely passed — prefer the close-success line when available.
		var close := "That was close, but fine."
		if SUCCESS.has(close) and not _recent.has(close):
			_remember(close)
			return close
	if (not is_success) and successes <= 0:
		var hard := "This was just too hard."
		if FAILURE.has(hard) and not _recent.has(hard):
			_remember(hard)
			return hard
	return pick(primary)


func _pick_weighted_secondary() -> String:
	## PERSONALITY / RECOVERY / ERROR occasional; MEMORY rare; RARE very rare.
	var roll := randf() * (
		WEIGHT_PERSONALITY + WEIGHT_RECOVERY + WEIGHT_ERROR + WEIGHT_MEMORY + WEIGHT_RARE
	)
	if roll < WEIGHT_PERSONALITY:
		return pick(Category.PERSONALITY)
	roll -= WEIGHT_PERSONALITY
	if roll < WEIGHT_RECOVERY:
		return pick(Category.RECOVERY)
	roll -= WEIGHT_RECOVERY
	if roll < WEIGHT_ERROR:
		return pick(Category.ERROR)
	roll -= WEIGHT_ERROR
	if roll < WEIGHT_MEMORY:
		return pick(Category.MEMORY)
	return pick(Category.RARE)


func _remember(line: String) -> void:
	if line.is_empty():
		return
	_recent.append(line)
	while _recent.size() > RECENT_LIMIT:
		_recent.pop_front()
