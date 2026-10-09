
local allowedchars = {
	"ah",
	"AH",
	"ghh",
	"GH",
	"AHHH",
}

local audible_pain = {
	"АААААА... ЧЁРТ... КАК БОЛЬНО.",
	"Я БОЛЬШЕ НЕ МОГУ!",
    "Пусть это ПРЕКРАТИТСЯ пусть ПРЕКРАТИТСЯ ПУСТЬ ПРЕКРАТИТСЯ",
    "Почему ЭТО НЕ ПРЕКРАЩАЕТСЯ",
    "Пусть я отключусь. ПОЖАЛУЙСТА",
    "Зачем я родился, чтобы это чувствовать, зачем...",
    "Я на всё готов, лишь бы это прекратилось... НА ВСЁ.",
    "Это не жизнь, это ПЫТКА",
    "Мне уже всё равно, только ОСТАНОВИТЕ БОЛЬ",
    "Ничего не важно, КРОМЕ ТОГО, ЧТОБЫ ЭТО ПРЕКРАТИЛОСЬ...",
    "Каждая секунда — вечность в ОГНЕ.",
    "СМЕРТЬ СЕЙЧАС БЫЛА БЫ МИЛОСТЬЮ...",
    "Хоть одно мгновение без боли..",
	"ВОТ БЫ СЕЙЧАС ОБЕЗБОЛИВАЮЩЕГО. ЧЁРТ.",
}

local sharp_pain = {
	"AAAHH",
	"AAAH",
	"AAaaAH",
	"AAaaAH",
	"AAaaAAAGH",
	"AAaaAH",
	"AAaAaaH",
	"AAAAAaaH",
	"AAaaAHHHH",
	"AAaAA",
	"AAAAAa",
	"AAAAaAAAaaaaghh",
	"AAAaaAa",
	"AaaAAaghf",
	"aaAaaAaff",
	"aaahhh",
	"AAAaaGHHH",
	"AAAaaAAHH",
	"AAAaaAAAAAaGHHHH",
	"AAAaaAAAAAaGHAAAHHH",
	"AAAaaAAAAAaGHHAAAAAAHH",
	"AAAaaAAAAAaGHHHH",
	"AAAaaAAAaaAAAaGHHHH",
	"AAAaaAAAaaAAAaAAAAAAAGHHHH",
	"AAAaaAAAAAaGHHHH",
	"AAAaaAAAAAAAAAHHH",
	"AAAaaAAAAAaGHAaaaHH",
	"AAAaaAAAAAaAaaaaaAAAAHH",
	"AAAaaAAAAAaAAAAAAAADGHHHH",
	"AAAaaAAAaaAAAaAAAAAAAAAAAAGGGGGGAGHHHH",
	"AAAaaAAAaaAAAaAAAAAAAAAAAAAAAAAAH",
}

hg.sharp_pain = sharp_pain

local random_phrase = {
	"Что-то здесь прохладно...",
	"Всё как-то слишком тихо...",
	"Дышать сейчас почему-то особенно приятно.",
	"А что, если эта тишина навсегда?",
	"Почему ничего не происходит?",
}

local fear_hurt_ironic = {
	"Наверное, в этом есть какой-то урок... если выживу.",
	"Мой будущий биограф в это не поверит.",
	"Ну и дурацкий способ умереть.",
	"Зато жизнь не была скучной.",
	"Заметка себе: больше никогда так не делать.",
	"Не худший день, чтобы умереть.",
}

local fear_phrases = {
	"Всё не так уж плохо... правда?",
	"Я не хочу так умирать.",
	"Неужели всё так и закончится?",
	"Это плохо.",
	"Неужели всё так и закончится?",
	"Я не хочу так умирать.",
	"Вот бы найти выход.",
	"Я о стольком жалею.",
	"Не может быть, что это всё.",
	"Не верится, что это происходит со мной.",
	"Надо было отнестись к этому серьёзнее.",
	"А если я не выкарабкаюсь..?",
	"Всё хуже, чем я думал.",
	"Это так несправедливо.",
	"Я пока не могу сдаться.",
	"Никогда не думал, что будет вот так.",
	"Надо было слушать своё чутьё.",
	"Дыши. Просто дыши.",
	"Холодные руки. Твёрдые руки.",
}

local panicattack_phrases = {
	"Я НЕ МОГУ... Я ЕДВА ДЫШУ!",
	"Моя грудь... её сводит...?",
	"Я справлюсь... Я справлюсь..",
	"Какого чёрта..?",
	"Чёрт.. Что происходит?",
	"Со мной что-то очень не так.",
	"Relax..!",
	"Мне нужна секунда.. Всего одна секунда.",
	"Ни одной мысли в голове не могу собрать!",
	"Не могу ясно думать..!",
	"Руки не перестают трястись.",
	"Мне нужно пространство..",
	"Я теряю контроль над собой..",
	"Сосредоточься.",
	"Не сейчас.. Не сейчас..",
	"Не могу успокоиться!",
	"Это уже слишком..!",
    "Я не хочу умирать.",
}

local is_aimed_at_phrases = {
    "Боже. Вот и всё.",
    "Не. двигайся.",
    "Неужели я так и умру?",
    "Надо было бежать. Почему я не убежал?",
    "Пожалуйста, не нажимай на курок. Пожалуйста.",
    "Я вижу их палец на спуске.",
    "Я не хочу умирать. Только не так.",
    "Если я буду умолять, станет хуже?",
    "Это не может быть правдой. Не может быть.",
    "Помогите. Пожалуйста. Кто-нибудь.",
    "Не хочу умирать в таком месте.",
    "Не хочу, чтобы моей последней мыслью был страх.",
    "Я не хочу умирать.",
}

local near_death_poetic = {
	"Пытаюсь встать... но не могу...",
	"Дыхание — лишь мелкие глотки пустоты...",
	"Уже не понимаю, открыты у меня глаза или нет...",
	"Последнее, что почувствую — вкус собственной крови и меди.",
	"Взгляд всё время соскальзывает.",
	"Не помню, как стоять.",
	"Всё отдаётся эхом в черепе.",
	"После моргания глаза открываются слишком долго.",
	"Пальцы ни за что не могут ухватиться.",
	"Лёгкие не наполняются.",
	"Сожалеть уже бессмысленно.",
}

local near_death_positive = {
	"Я не хочу умирать.",
	"Я должен выжить.",
	"Шанс ещё есть.",
	"Нельзя дать страху победить.",
	"Ещё одна попытка.",
	"Я отказываюсь здесь умирать.",
	"Так... надо всё обдумать.",
	"Просто не двигайся. От движений хуже.",
	"Дыши медленно. Паника не поможет.",
	"Ничего не кончено, пока не кончено.",
	"Боль — просто сигнал. Не обращай внимания.",
	"Если это конец... то хотя бы быстрый.",
	"Я переживал и хуже. Наверное.",
	"Я не так себе это представлял.",
}

local broken_limb = {
	"ЧЁРТ. ЧЁРТ. ТОЧНО СЛОМАНО!",
	"Я ЧУВСТВУЮ, КАК ДВИГАЮТСЯ ОСКОЛКИ КОСТИ!",
	"ЧЁРТ, СЛОМАНО. КАЖЕТСЯ..",
	"Больно даже думать об этом. Точно перелом.",
	"Не думаю, что оно должно здесь гнуться.",
	"О чёрт. Переломилось.",
	"Открытого перелома не вижу, но, кажется, я что-то сломал",
}

local dislocated_limb = {
	"Да, так оно гнуться не должно.",
	"Надо вправить кость обратно.",
	"Нет... надо поставить её на место.",
	"Там так больно. Может, нужно провериться.",
	"Конечность не на месте.",
}

local hungry_a_bit = {
    "Мгх, есть хочу...",
    "Поесть бы чего-нибудь...",
    "Я голоден...",
    "Надо бы что-нибудь съесть.",
}

local very_hungry = {
    "Мой живот... Ух...",
    "Если не поем, станет ещё хуже...",
    "Живот... Чёрт... Меня мутит",
}

local after_unconscious = {
    "Что случилось? Больно...",
	"Где я? Почему так больно...",
	"Я-я думал, что умру...",
	"Моя голова... Что случилось?",
	"Я только что чуть не умер?",
	"Будто я умер.",
	"Небеса меня не забрали?",
	"Ох-чёрт... голова раскалывается...",
	"Ох, сейчас будет тяжело встать... но надо...",
	"Совсем не узнаю это место... или узнаю?",
	"Не хочу пережить такое НИКОГДА СНОВА!",
}

local slight_braindamage_phraselist = {
	"Я не понимаю...",
	"Это не имеет смысла...",
	"Где я?",
	"А? Что это..?",
	"Не понимаю, что происходит...",
	"Hello?",
	"Уххх оххх...      а...",
	"Что... происходит?",
}

local braindamage_phraselist = {
	"Bbbee.. wheea mgh?!",
	"Bmmeee... mehk...",
	"Mm--hhhh. Mmm?",
	"Ghmgh whhh...",
	"Ahgg...mg?",
	"Hgghh... D-Dmmh.",
	"Lmmmphf, mp-hf!",
	"Heeelllhhpphp...",
	"Nghh... Gmh?",
	"Ggg... Bgh..",
	"Bhrhraihin.",
}

local cold_phraselist = {
	"Становится очень холодно..",
	"Для меня слишком холодно.",
	"Меня трясёт, чёрт возьми.",
	"Здесь ужасно холодно..",
	"Надо чем-то согреться...",
	"Мне довольно холодно...",
	"Меня мутит от холода, чёрт."
}

local freezing_phraselist = {
	"Я.. н-не.. ч-чувствую с-своё т-тело..",
	"Я не.. ч-чувствую ног...",
	"Я ч-чёрт-това з-замерзаю..",
	"К-кажется, л-лицо онем-мело..",
	"Cold-d..",
	"Я.. н-ничего не ч-чувствую..",
}

local numb_phraselist = {
	"Уже.. не холодно..",
	"Почему... стало тепло..?",
	"Кажется, я в порядке... кажется...",
	"Наконец-то тепло...",
	"Мне снова тепло... Как-то...",
	"Я только что замерзал... Откуда это тепло..?",
}

local hot_phraselist = {
	"Я весь в поту..",
	"Эта жара меня убивает..",
	"Одежда вся мокрая от пота, чёрт.",
	"От меня ужасно несёт потом. Надо остыть...",
	"Слишком жарко, чёрт возьми.",
	"Я сильно перегреваюсь...",
	"Почему здесь так жарко?",
}

local heatstroke_phraselist = {
	"МНЕ НУЖНА ВОДА!!",
	"Пожалуйста... воды...",
	"Голова кружится... Чёёёрт-",
	"МОЯ ГОЛОВА!- Больно..",
	"Голова болит..",
}

local heatvomit_phraselist = {
	"Эта жара..- меня сейчас вырвет-",
	"Уггхх... меня сейчас стошнит-",
	"Чёёрт.. Оуххх.. Мне плохо-"
}

local hg_showthoughts = ConVarExists("hg_showthoughts") and GetConVar("hg_showthoughts") or CreateClientConVar("hg_showthoughts", "1", true, true, "Toggle thoughts of your character", 0, 1)

function string.Random(length)
	local length = tonumber(length)

    if length < 1 then return end

    local result = {}

    for i = 1, length do
        result[i] = allowedchars[math.random(#allowedchars)]
    end

    return table.concat(result)
end

function hg.nothing_happening(ply)
	if not IsValid(ply) then return end

	return ply.organism and ply.organism.fear < -0.6
end

function hg.fearful(ply)
	if not IsValid(ply) then return end

	return ply.organism and ply.organism.fear > 0.5
end

function hg.likely_to_phrase(ply)
	local org = ply.organism

	local pain = org.pain
	local brain = org.brain
	local blood = org.blood
	local fear = org.fear
	local panicattack = org.panicattack or 0
	local temperature = org.temperature
	local broken_dislocated = org.just_damaged_bone and ((org.just_damaged_bone - CurTime()) < -3)

	return (broken_dislocated) and 5
		or (pain > 65) and 5
		or (panicattack > 0.55 and 1.2)
		or (temperature < 31 and 0.5)
		or (temperature > 38 and 0.5)
		or (blood < 3000 and 0.3)
		--or (fear > 0.5 and 0.7)
		or (brain > 0.1 and brain * 5)
		or (fear < -0.5 and 0.05)
		or -0.1
end

function IsAimedAt(ply)
    return ply.aimed_at or 0
end

local function get_status_message(ply)
	if not IsValid(ply) then
		if CLIENT then
			ply = lply
		else
			return
		end
	end

	local nomessage = hook.Run("HG_CanThoughts", ply) --ply.PlayerClassName == "Gordon" || ply.PlayerClassName == "Combine"
	if nomessage ~= nil and nomessage == false then return "" end

    if ply:GetInfoNum("hg_showthoughts", 1) == 0 then return "" end

	local org = ply.organism
	
	if not org or not org.brain then return "" end

	local pain = org.pain
	local brain = org.brain
	local temperature = org.temperature
	local blood = org.blood
	local hungry = org.hungry
	local panicattack = org.panicattack or 0
	local broken_dislocated = org.just_damaged_bone and ((org.just_damaged_bone + 3 - CurTime()) < -3)

	if broken_dislocated and org.just_damaged_bone then
		org.just_damaged_bone = nil
	end
	
	local broken_notify = (org.rarm == 1) or (org.larm == 1) or (org.rleg == 1) or (org.lleg == 1)
	local dislocated_notify = (org.rarm == 0.5) or (org.larm == 0.5) or (org.rleg == 0.5) or (org.lleg == 0.5)
	local after_unconscious_notify = org.after_otrub

	if not isnumber(pain) then return "" end

	local str = ""

	local most_wanted_phraselist
	
	if temperature < 35 then
		most_wanted_phraselist = temperature > 31 and cold_phraselist or (temperature < 28 and numb_phraselist or freezing_phraselist)
	elseif temperature > 38 then
		most_wanted_phraselist = temperature < 40 and hot_phraselist or heatstroke_phraselist
	end

	if not most_wanted_phraselist and hungry and hungry > 25 and math.random(3) == 1 then
		most_wanted_phraselist = hungry > 45 and very_hungry or hungry_a_bit
	end

	if (blood < 3100) or (pain > 75) or (broken_dislocated) or (broken_notify) or (dislocated_notify) then
		if pain > 75 and (broken_dislocated) then
			most_wanted_phraselist = math.random(2) == 1 and audible_pain or (broken_notify and broken_limb or dislocated_limb)
		elseif pain > 75 then
			most_wanted_phraselist = audible_pain
		elseif broken_dislocated then
			most_wanted_phraselist = (broken_notify and broken_limb or dislocated_limb)
		end

		if pain > 100 then
			most_wanted_phraselist = sharp_pain
		end

		if not most_wanted_phraselist then
			if (broken_dislocated_notify) and (blood < 3100) then
				most_wanted_phraselist = blood < 2900 and (near_death_poetic) or (math.random(2) == 1 and (broken_notify and broken_limb or dislocated_limb) or near_death_poetic)
			--elseif(broken_dislocated_notify)then
				--most_wanted_phraselist = (broken_notify and broken_limb or dislocated_limb)
			elseif(blood < 3100)then
				most_wanted_phraselist = near_death_poetic
			end
		end
	elseif after_unconscious_notify then
		most_wanted_phraselist = after_unconscious
	elseif panicattack > 0.55 then
		most_wanted_phraselist = panicattack_phrases
	elseif hg.nothing_happening(ply) then
		most_wanted_phraselist = random_phrase

		if hungry and hungry > 25 and math.random(5) == 1 then
			most_wanted_phraselist = hungry > 45 and very_hungry or hungry_a_bit
		end
	elseif hg.fearful(ply) then
		most_wanted_phraselist = ((IsAimedAt(ply) > 0.9) and is_aimed_at_phrases or (math.random(10) == 1 and fear_hurt_ironic or fear_phrases))
	end

	if brain > 0.1 then
		most_wanted_phraselist = brain < 0.2 and slight_braindamage_phraselist or braindamage_phraselist
	end
	
	if most_wanted_phraselist then
		str = most_wanted_phraselist[math.random(#most_wanted_phraselist)]

		return str
	else
		return ""
	end
end

local allowedlist_types = {
	heatvomit = heatvomit_phraselist,
}

function hg.get_phraselist(ply, type)
	if not IsValid(ply) then
		if CLIENT then
			ply = lply
		else
			return
		end
	end
	
	local nomessage = ply.PlayerClassName == "Gordon" || ply.PlayerClassName == "Combine"

	if nomessage then return "" end
    if ply:GetInfoNum("hg_showthoughts", 1) == 0 then return "" end

	local org = ply.organism	
	if not org or not org.brain then return "" end

	if not isstring(type) or not allowedlist_types[type] then return "" end

	local needed_list = allowedlist_types[type]

	local str = needed_list[math.random(#needed_list)]
	return str
end

function hg.get_status_message(ply)
	local txt = get_status_message(ply)

	return txt
end
