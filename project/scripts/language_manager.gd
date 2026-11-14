class_name LanguageManager
extends RefCounted
## v0.6 SYSTEM 1 — Languages FR / EN / AR.
##
## Static API only — no autoload needed, no node in the scene tree.
## Any script can call `LanguageManager.translate("menu_deploy")` directly.
##
## - Default language: "en" (English). The choice persists in
##   user://settings.cfg (section "language", key "code") and is
##   re-loaded on first use at game start.
## - Missing key in the current language falls back to English, and
##   if it is missing there too it returns the key itself — never a crash.
## - Arabic UI needs the bundled font (Godot 4.2 shapes Arabic via
##   HarfBuzz; the font is what makes it render):
##   res://assets/fonts/NotoNaskhArabic.ttf (Noto Naskh Arabic, SIL OFL 1.1).
##   Call `LanguageManager.apply_font_to(control)` on every Control
##   that shows translated text, every time the language changes.
## - Tunisian spoken greetings (Salam / Marhaba / ...) stay in their
##   transliterated form in FR and EN, because that is how they are
##   spoken; only the AR entries use Arabic script.

const FONT_ARABIC_PATH := "res://assets/fonts/NotoNaskhArabic.ttf"
const SETTINGS_PATH := "user://settings.cfg"

static var _current: String = "en"
static var _loaded: bool = false
static var _arabic_font: FontFile = null

const STRINGS := {
	"en": {
		"menu_title": "PHANTOM OPS",
		"menu_subtitle": "KASSERINE POLICE",
		"menu_deploy": "DEPLOY",
		"menu_how_to_play": "HOW TO PLAY",
		"menu_sound": "SOUND",
		"menu_voices": "VOICES",
		"menu_adhan": "ADHAN",
		"menu_language": "LANGUAGE",
		"menu_close": "CLOSE",
		"language_fr": "FRANÇAIS",
		"language_en": "ENGLISH",
		"language_ar": "العربية",
		"sound_on": "SOUND: ON",
		"sound_off": "SOUND: OFF",
		"voices_on": "VOICES: ON",
		"voices_off": "VOICES: OFF",
		"adhan_on": "ADHAN: ON",
		"adhan_off": "ADHAN: OFF",
		"how_to_play_text": "HOW TO PLAY\n\n• You are a Kasserine police officer\n• Left thumb — move through Kasserine\n• Right thumb — look around\n• FIRE — shoot (hold for auto-fire)\n• JUMP — jump, RUN — sprint\n• AMMO 30/30 — it reloads automatically\n• Stop criminals to score — 100 points each\n• Civilians are not targets — never shoot them\n• Help citizens who ask for help\n• Waves get harder: 8 enemies, then more",
		"hud_controls": "Left thumb — move  •  Right thumb — look  •  FIRE to shoot (hold = auto)  •  RUN to sprint",
		"hud_fire": "FIRE",
		"hud_jump": "JUMP",
		"hud_run": "RUN",
		"hud_move": "MOVE",
		"hud_hold_fire": "HOLD FIRE = AUTO",
		"hud_ammo": "AMMO",
		"hud_hp": "HP",
		"hud_score": "SCORE",
		"hud_kills": "KILLS",
		"hud_wave": "WAVE",
		"hud_money": "MONEY",
		"hud_pause": "PAUSE",
		"hud_reloading": "RELOADING...",
		"pause_title": "MISSION PAUSED",
		"pause_resume": "RESUME",
		"pause_menu": "MAIN MENU",
		"pause_sound": "SOUND",
		"pause_voices": "VOICES",
		"death_title": "YOU DIED",
		"death_retry": "RETRY",
		"death_menu": "MAIN MENU",
		"death_score": "SCORE",
		"death_kills": "KILLS",
		"death_wave": "WAVE",
		"mission_title": "MISSION",
		"mission_respond": "Respond to the call",
		"mission_help": "Help the citizen",
		"mission_chase": "Chase the criminal",
		"mission_patrol": "Patrol Kasserine",
		"mission_respond_detail": "Robbery reported! Reach the marked location and stop the criminals.",
		"mission_help_detail": "A poor citizen needs help. Reach them and give what you can.",
		"mission_chase_detail": "A criminal is fleeing on foot! Catch him before he escapes.",
		"mission_patrol_detail": "Patrol duty: visit all 3 checkpoints in order.",
		"mission_complete": "MISSION COMPLETE",
		"mission_failed": "MISSION FAILED",
		"mission_reward": "Reward",
		"mission_all_complete": "ALL OBJECTIVES COMPLETE",
		"mission_return_safe": "Return to the safe zone. New operations incoming.",
		"prompt_help": "HELP",
		"prompt_give": "GIVE",
		"prompt_check": "CHECK",
		"prompt_enter_car": "ENTER CAR",
		"prompt_exit_car": "EXIT CAR",
		"prompt_talk": "TALK",
		"siren_on": "SIREN: ON",
		"siren_off": "SIREN: OFF",
		"greeting_salam": "Salam",
		"greeting_marhaba": "Marhaba",
		"greeting_salam_alaykum": "Salam alaykum",
		"greeting_ahla": "Ahla wa sahla",
		"citizen_help": "Please help!",
		"citizen_thanks": "Thank you, officer!",
		"citizen_joke_1": "I told my wife I joined the police... now she arrests me every time I leave dishes in the sink!",
		"citizen_joke_2": "In Kasserine, even the pigeons know the patrol routes — they fly away before the siren!",
		"citizen_funny": "Ha! Good one!",
		"criminal_flee": "Stop! Police!",
		"criminal_caught": "Criminal caught!",
		"day_label": "DAY",
		"night_label": "NIGHT",
		"rain_label": "RAIN",
		# v0.7 STORY CAMPAIGN — chapter titles, story text, ranks, results.
		"chapter_1_title": "First Patrol",
		"chapter_2_title": "The Souk Robbery",
		"chapter_3_title": "Night Shift",
		"chapter_4_title": "The Informant",
		"chapter_5_title": "The Wolf",
		"chapter_1_story": "Your first day on the Kasserine force.\nPatrol the city, help the people, and show the Wolves this city has a guardian.",
		"chapter_2_story": "The Wolves rob the souk market.\nStop them and chase the thief before he escapes.",
		"chapter_3_story": "Night shift. The Wolves attack the plaza and the mosque area under cover of darkness and rain.\nHold the line.",
		"chapter_4_story": "A suspicious man in the crowd knows where the Wolf hides.\nFind him, check him, and get the location.",
		"chapter_5_story": "The final fight at the plaza — Khaled \"The Wolf\" himself.\nEnd his gang and save Kasserine.",
		"chapter_complete": "Chapter Complete",
		"chapter_failed": "Mission Failed",
		"chapter_locked": "Complete the previous chapter to unlock",
		"continue_game": "Continue",
		"chapter_select": "Chapters",
		"rank_officer": "Officer",
		"rank_sergeant": "Sergeant",
		"rank_lieutenant": "Lieutenant",
		"rank_captain": "Captain",
		"rank_up": "Rank Up!",
		"boss_name": "Khaled — The Wolf",
		"boss_intro": "The Wolf himself. End this.",
		"ending_title": "Kasserine Is Safe",
		"ending_text": "The Wolves are defeated.\nKasserine is safe, thanks to Aymen.",
		"next_chapter": "Next Chapter",
		"retry_chapter": "Retry Chapter",
		"xp_earned": "XP Earned",
		"money_earned": "Money Earned",
		"time_label": "Time",
		"skip_label": "SKIP",
		"chapter_informant_hint": "Psst... I know where The Wolf hides.",
		"chapter_informant_search": "Searching the crowd...",
		"chapter_informant_label": "The suspicious man",
	},
	"fr": {
		"menu_title": "PHANTOM OPS",
		"menu_subtitle": "POLICE DE KASSERINE",
		"menu_deploy": "DÉPLOYER",
		"menu_how_to_play": "COMMENT JOUER",
		"menu_sound": "SON",
		"menu_voices": "VOIX",
		"menu_adhan": "ADHAN",
		"menu_language": "LANGUE",
		"menu_close": "FERMER",
		"language_fr": "FRANÇAIS",
		"language_en": "ENGLISH",
		"language_ar": "العربية",
		"sound_on": "SON : ON",
		"sound_off": "SON : OFF",
		"voices_on": "VOIX : ON",
		"voices_off": "VOIX : OFF",
		"adhan_on": "ADHAN : ON",
		"adhan_off": "ADHAN : OFF",
		"how_to_play_text": "COMMENT JOUER\n\n• Vous êtes un policier de Kasserine\n• Pouce gauche — vous déplacer dans Kasserine\n• Pouce droit — regarder autour de vous\n• TIRER — tirer (maintenir pour le tir automatique)\n• SAUTER — sauter, COURIR — sprinter\n• MUNITIONS 30/30 — rechargement automatique\n• Arrêtez les criminels pour marquer — 100 points chacun\n• Les civils ne sont pas des cibles — ne tirez jamais sur eux\n• Aidez les citoyens qui demandent de l'aide\n• Les vagues se durcissent : 8 ennemis, puis davantage",
		"hud_controls": "Pouce gauche — bouger  •  Pouce droit — regarder  •  TIRER pour tirer (maintenir = auto)  •  COURIR pour sprinter",
		"hud_fire": "TIRER",
		"hud_move": "DÉPLACER",
		"hud_hold_fire": "MAINTENIR = TIR AUTO",
		"hud_jump": "SAUTER",
		"hud_run": "COURIR",
		"hud_ammo": "MUNITIONS",
		"hud_hp": "PV",
		"hud_score": "SCORE",
		"hud_kills": "ÉLIMINATIONS",
		"hud_wave": "VAGUE",
		"hud_money": "ARGENT",
		"hud_pause": "PAUSE",
		"hud_reloading": "RECHARGEMENT...",
		"pause_title": "MISSION EN PAUSE",
		"pause_resume": "REPRENDRE",
		"pause_menu": "MENU PRINCIPAL",
		"pause_sound": "SON",
		"pause_voices": "VOIX",
		"death_title": "VOUS ÊTES MORT",
		"death_retry": "RÉESSAYER",
		"death_menu": "MENU PRINCIPAL",
		"death_score": "SCORE",
		"death_kills": "ÉLIMINATIONS",
		"death_wave": "VAGUE",
		"mission_title": "MISSION",
		"mission_respond": "Répondre à l'appel",
		"mission_help": "Aider le citoyen",
		"mission_chase": "Poursuivre le criminel",
		"mission_patrol": "Patrouiller à Kasserine",
		"mission_respond_detail": "Braquage signalé ! Rejoignez le lieu marqué et arrêtez les criminels.",
		"mission_help_detail": "Un citoyen pauvre a besoin d'aide. Rejoignez-le et donnez ce que vous pouvez.",
		"mission_chase_detail": "Un criminel s'enfuit à pied ! Attrapez-le avant qu'il ne s'échappe.",
		"mission_patrol_detail": "Patrouille : visitez les 3 points de contrôle dans l'ordre.",
		"mission_complete": "MISSION ACCOMPLIE",
		"mission_failed": "MISSION ÉCHOUÉE",
		"mission_reward": "Récompense",
		"mission_all_complete": "TOUS LES OBJECTIFS ACCOMPLIS",
		"mission_return_safe": "Retournez en zone sûre. De nouvelles opérations arrivent.",
		"prompt_help": "AIDER",
		"prompt_give": "DONNER",
		"prompt_check": "CONTRÔLER",
		"prompt_enter_car": "MONTER EN VOITURE",
		"prompt_exit_car": "SORTIR DE LA VOITURE",
		"prompt_talk": "PARLER",
		"siren_on": "SIRÈNE : ACTIVÉE",
		"siren_off": "SIRÈNE : DÉSACTIVÉE",
		"greeting_salam": "Salam",
		"greeting_marhaba": "Marhaba",
		"greeting_salam_alaykum": "Salam alaykum",
		"greeting_ahla": "Ahla wa sahla",
		"citizen_help": "S'il vous plaît, aidez-moi !",
		"citizen_thanks": "Merci, monsieur l'agent !",
		"citizen_joke_1": "J'ai dit à ma femme que j'étais policier... maintenant elle m'arrête chaque fois que je laisse la vaisselle dans l'évier !",
		"citizen_joke_2": "À Kasserine, même les pigeons connaissent les rondes — ils s'envolent avant la sirène !",
		"citizen_funny": "Ha ! Bien joué !",
		"criminal_flee": "Arrêtez ! Police !",
		"criminal_caught": "Criminel arrêté !",
		"day_label": "JOUR",
		"night_label": "NUIT",
		"rain_label": "PLUIE",
		# v0.7 STORY CAMPAIGN — titres des chapitres, textes, grades, résultats.
		"chapter_1_title": "Première patrouille",
		"chapter_2_title": "Le braquage du souk",
		"chapter_3_title": "La nuit de garde",
		"chapter_4_title": "L'informateur",
		"chapter_5_title": "Le Loup",
		"chapter_1_story": "Votre premier jour dans la police de Kasserine.\nPatrouillez la ville, aidez les habitants et montrez aux Loups que cette ville a un gardien.",
		"chapter_2_story": "Les Loups braquent le souk.\nArrêtez-les et poursuivez le voleur avant qu'il ne s'échappe.",
		"chapter_3_story": "Nuit de garde. Les Loups attaquent la place et les abords de la mosquée, cachés par l'obscurité et la pluie.\nTenez bon.",
		"chapter_4_story": "Un homme suspect dans la foule sait où se cache le Loup.\nTrouvez-le, contrôlez-le et obtenez l'adresse.",
		"chapter_5_story": "Le combat final sur la place — Khaled « Le Loup » en personne.\nMettez fin à son gang et sauvez Kasserine.",
		"chapter_complete": "Chapitre terminé",
		"chapter_failed": "Mission échouée",
		"chapter_locked": "Terminez le chapitre précédent pour débloquer",
		"continue_game": "Continuer",
		"chapter_select": "Chapitres",
		"rank_officer": "Agent",
		"rank_sergeant": "Sergent",
		"rank_lieutenant": "Lieutenant",
		"rank_captain": "Capitaine",
		"rank_up": "Promotion !",
		"boss_name": "Khaled — Le Loup",
		"boss_intro": "Le Loup en personne. Finissez-en.",
		"ending_title": "Kasserine est sauve",
		"ending_text": "Les Loups sont vaincus.\nKasserine est sauve, grâce à Aymen.",
		"next_chapter": "Chapitre suivant",
		"retry_chapter": "Recommencer le chapitre",
		"xp_earned": "XP gagnée",
		"money_earned": "Argent gagné",
		"time_label": "Temps",
		"skip_label": "PASSER",
		"chapter_informant_hint": "Psst... Je sais où se cache le Loup.",
		"chapter_informant_search": "Recherche dans la foule...",
		"chapter_informant_label": "L'homme suspect",
	},
	"ar": {
		"menu_title": "PHANTOM OPS",
		"menu_subtitle": "شرطة القصرين",
		"menu_deploy": "انطلق",
		"menu_how_to_play": "كيف تلعب",
		"menu_sound": "الصوت",
		"menu_voices": "الأصوات",
		"menu_adhan": "الأذان",
		"menu_language": "اللغة",
		"menu_close": "إغلاق",
		"language_fr": "FRANÇAIS",
		"language_en": "ENGLISH",
		"language_ar": "العربية",
		"sound_on": "الصوت: مفعّل",
		"sound_off": "الصوت: متوقف",
		"voices_on": "الأصوات: مفعّلة",
		"voices_off": "الأصوات: متوقفة",
		"adhan_on": "الأذان: مفعّل",
		"adhan_off": "الأذان: متوقف",
		"how_to_play_text": "كيف تلعب\n\n• أنت شرطي في القصرين\n• الإبهام الأيسر — التحرك في القصرين\n• الإبهام الأيمن — النظر من حولك\n• أطلق النار — اضغط باستمرار للإطلاق التلقائي\n• اقفز — اقفز، اركض — للجري السريع\n• الذخيرة 30/30 — تُعاد تعبئتها تلقائيًا\n• أوقف المجرمين لتسجيل النقاط — 100 نقطة لكل مجرم\n• المدنيون ليسوا أهدافًا — لا تطلق النار عليهم أبدًا\n• ساعد المواطنين الذين يطلبون المساعدة\n• الموجات تصبح أصعب: 8 أعداء، ثم أكثر",
		"hud_controls": "الإبهام الأيسر — التحرك  •  الإبهام الأيمن — النظر  •  أطلق النار للتصويب (اضغط باستمرار = تلقائي)  •  اركض للجري السريع",
		"hud_fire": "أطلق النار",
		"hud_move": "تحرّك",
		"hud_hold_fire": "اضغط باستمرار = إطلاق تلقائي",
		"hud_jump": "اقفز",
		"hud_run": "اركض",
		"hud_ammo": "الذخيرة",
		"hud_hp": "الصحة",
		"hud_score": "النقاط",
		"hud_kills": "القتلى",
		"hud_wave": "الموجة",
		"hud_money": "المال",
		"hud_pause": "إيقاف مؤقت",
		"hud_reloading": "جارٍ إعادة التلقيم...",
		"pause_title": "المهمة متوقفة مؤقتًا",
		"pause_resume": "استئناف",
		"pause_menu": "القائمة الرئيسية",
		"pause_sound": "الصوت",
		"pause_voices": "الأصوات",
		"death_title": "لقد مت",
		"death_retry": "حاول مجددًا",
		"death_menu": "القائمة الرئيسية",
		"death_score": "النقاط",
		"death_kills": "القتلى",
		"death_wave": "الموجة",
		"mission_title": "المهمة",
		"mission_respond": "استجب للنداء",
		"mission_help": "ساعد المواطن",
		"mission_chase": "طارد المجرم",
		"mission_patrol": "دورية في القصرين",
		"mission_respond_detail": "تم الإبلاغ عن سرقة! توجّه إلى الموقع المحدد وأوقف المجرمين.",
		"mission_help_detail": "مواطن فقير يحتاج إلى المساعدة. توجّه إليه وقدّم ما تستطيع.",
		"mission_chase_detail": "مجرم يفرّ على قدميه! أمسك به قبل أن يهرب.",
		"mission_patrol_detail": "دورية: قم بزيارة نقاط التفتيش الثلاث بالترتيب.",
		"mission_complete": "اكتملت المهمة",
		"mission_failed": "فشلت المهمة",
		"mission_reward": "المكافأة",
		"mission_all_complete": "اكتملت جميع الأهداف",
		"mission_return_safe": "عُد إلى المنطقة الآمنة. عمليات جديدة في الطريق.",
		"prompt_help": "ساعد",
		"prompt_give": "أعطِ",
		"prompt_check": "تحقق",
		"prompt_enter_car": "اركب السيارة",
		"prompt_exit_car": "اخرج من السيارة",
		"prompt_talk": "تحدث",
		"siren_on": "صفارة الإنذار: مفعّلة",
		"siren_off": "صفارة الإنذار: متوقفة",
		"greeting_salam": "سلام",
		"greeting_marhaba": "مرحبا",
		"greeting_salam_alaykum": "السلام عليكم",
		"greeting_ahla": "أهلا وسهلا",
		"citizen_help": "ساعدني من فضلك!",
		"citizen_thanks": "شكرًا لك يا حضرة الشرطي!",
		"citizen_joke_1": "قلت لزوجتي إنني شرطي... فأصبحت تعتقلني كلما تركت الصحون في الحوض!",
		"citizen_joke_2": "في القصرين، حتى الحمام يعرف طرق الدوريات — يطير قبل أن تدوي صفارة الإنذار!",
		"citizen_funny": "ها! أحسنت!",
		"criminal_flee": "توقف! الشرطة!",
		"criminal_caught": "تم القبض على المجرم!",
		"day_label": "نهار",
		"night_label": "ليل",
		"rain_label": "مطر",
		# v0.7 STORY CAMPAIGN — عناوين الفصول، نصوص القصة، الرتب، النتائج.
		"chapter_1_title": "الدورية الأولى",
		"chapter_2_title": "سرقة السوق",
		"chapter_3_title": "مناوبة الليل",
		"chapter_4_title": "المخبر",
		"chapter_5_title": "الذئب",
		"chapter_1_story": "يومك الأول في شرطة القصرين.\nقم بدورية في المدينة، وساعد الناس، وأظهر للذئاب أن لهذه المدينة حارسًا.",
		"chapter_2_story": "الذئاب يسرقون السوق.\nأوقفهم وطارد اللص قبل أن يهرب.",
		"chapter_3_story": "مناوبة الليل. الذئاب يهاجمون الساحة ومنطقة الجامع مستترين بالظلام والمطر.\nاصمد في موقعك.",
		"chapter_4_story": "رجل مشبوه بين الحشود يعرف أين يختبئ الذئب.\nاعثر عليه، وتحقق منه، واحصل على الموقع.",
		"chapter_5_story": "المعركة الأخيرة في الساحة — خالد «الذئب» نفسه.\nأنهِ عصابته وأنقذ القصرين.",
		"chapter_complete": "اكتمل الفصل",
		"chapter_failed": "فشلت المهمة",
		"chapter_locked": "أكمل الفصل السابق لفتحه",
		"continue_game": "متابعة",
		"chapter_select": "الفصول",
		"rank_officer": "شرطي",
		"rank_sergeant": "رقيب",
		"rank_lieutenant": "ملازم",
		"rank_captain": "نقيب",
		"rank_up": "ترقية!",
		"boss_name": "خالد — الذئب",
		"boss_intro": "الذئب نفسه. أنهِ الأمر.",
		"ending_title": "القصرين آمنة",
		"ending_text": "تمت هزيمة الذئاب.\nالقصرين آمنة، بفضل أيمن.",
		"next_chapter": "الفصل التالي",
		"retry_chapter": "إعادة الفصل",
		"xp_earned": "النقاط المكتسبة",
		"money_earned": "المال المكتسب",
		"time_label": "الوقت",
		"skip_label": "تخطَّ",
		"chapter_informant_hint": "همسًا... أعرف أين يختبئ الذئب.",
		"chapter_informant_search": "جارٍ البحث في الحشد...",
		"chapter_informant_label": "الرجل المشبوه",
	},
}


## Languages the game offers, in menu order.
static func available() -> Array:
	return ["fr", "en", "ar"]


## Current language code: "fr", "en" or "ar". Default "en".
static func current() -> String:
	_ensure_loaded()
	return _current


## True when the current language reads right-to-left (Arabic).
static func is_rtl() -> bool:
	return current() == "ar"


## Switch language immediately and persist the choice.
## Invalid codes are ignored (with a warning) — never a crash.
static func set_language(code: String) -> void:
	_ensure_loaded()
	var c := code.strip_edges().to_lower()
	if not c in available():
		push_warning("LanguageManager: unknown language '%s', keeping '%s'." % [code, _current])
		return
	if c == _current:
		return
	_current = c
	_save()


## Translate a key. Falls back to English, then to the key itself.
## NOTE — why this is called translate(), not tr(): the spec asked for
## `static func tr(key)`, but that is impossible in Godot 4.2 GDScript.
## Every class inherits Object.tr() (a NON-static native method), and a
## static function can never override it — the parser rejects it with
## "The function signature doesn't match the parent" (verified with
## --check-only, both with `String` and with the exact parent signature
## `tr(StringName, StringName = <default>)`). So the static API is
## translate() (+ short alias t()). The instance tr() below exists only
## so code holding a LanguageManager instance can still call .tr().
static func translate(key: String) -> String:
	_ensure_loaded()
	var lang: Dictionary = STRINGS.get(_current, {})
	if lang.has(key):
		return String(lang[key])
	var en: Dictionary = STRINGS.get("en", {})
	if en.has(key):
		return String(en[key])
	push_warning("LanguageManager: missing key '%s'." % key)
	return key


## Short alias for translate().
static func t(key: String) -> String:
	return translate(key)


## Instance override of Object.tr() (NOT static — static overrides of
## native methods are rejected by the parser). Delegates to translate().
## The signature must match Object.tr() exactly.
@warning_ignore("native_method_override")
func tr(message: StringName, _context: StringName = &"") -> String:
	return translate(String(message))


## The Arabic font (Noto Naskh Arabic), loaded once and cached.
## Returns null if the file is missing — callers must handle null.
static func arabic_font() -> Font:
	if _arabic_font == null:
		_arabic_font = load(FONT_ARABIC_PATH) as FontFile
		if _arabic_font == null:
			push_warning("LanguageManager: Arabic font not found at %s." % FONT_ARABIC_PATH)
	return _arabic_font


## Font to use for translated UI text: the Arabic font when the
## current language is Arabic, otherwise null (use the default theme font).
## Useful for custom-drawn text (e.g. mobile_hud draw_string calls).
static func font_for_current() -> Font:
	if current() == "ar":
		return arabic_font()
	return null


## Apply the right font to a Control showing translated text.
## - Arabic: sets the Noto Naskh Arabic font override + RTL layout
##   direction, so Arabic shapes and aligns correctly.
## - FR/EN: removes any font override (back to the default theme font)
##   and restores LTR layout direction.
## Call this on every translated Control each time the language changes.
static func apply_font_to(control: Control) -> void:
	if control == null:
		return
	if current() == "ar":
		var font := arabic_font()
		if font != null:
			control.add_theme_font_override("font", font)
		control.layout_direction = Control.LAYOUT_DIRECTION_RTL
	else:
		control.remove_theme_font_override("font")
		control.layout_direction = Control.LAYOUT_DIRECTION_LTR


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var code := String(cfg.get_value("language", "code", "en"))
		if code in available():
			_current = code


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("language", "code", _current)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("LanguageManager: could not save %s (err %d)." % [SETTINGS_PATH, err])
