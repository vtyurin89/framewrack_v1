class_name StatCheckLog
extends RefCounted
## Static pools of flavored log lines for stat checks, stored like the
## BootSequence SYSTEM_LOG / OMINOUS_LOG const arrays. No state.

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
