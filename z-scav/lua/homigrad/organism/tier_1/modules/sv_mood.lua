--[[
    REM: настроение.

    org.happiness 0..1 - внутреннее "счастье", медленно тянется к цели,
                         которая зависит от состояния тела.
    org.mood     -1..1 - то же самое для остальных систем (отправляется клиенту).

    Хорошее настроение (mood > HAPPY_FROM):
      * быстрее бег (до +SPEED_BONUS, см. movement/sh_inertia.lua)
      * персонаж иногда говорит что-нибудь хорошее
    Плохое настроение растёт из боли, голода, холода, кровопотери и страха.
    Долго плохое настроение превращается в депрессию (sv_depression.lua).
]]

local Clamp, max, min, Approach = math.Clamp, math.max, math.min, math.Approach

hg.organism.mood = hg.organism.mood or {}
local CFG = hg.organism.mood

CFG.HAPPY_FROM      = 0.3   -- с какого mood начинается "радостный"
CFG.SPEED_BONUS     = 0.12  -- +12% к скорости при mood = 1
CFG.FOLLOW_SPEED    = 0.012 -- как быстро happiness идёт к цели (в секунду)
CFG.EAT_BOOST       = 0.15  -- (устарело, см. JOY_*)
-- "радость" от приятных дел: копится и медленно уходит, поднимая настроение
CFG.JOY_PER_SATIETY = 0.015 -- за каждую единицу сытости (обед ~ +0.45)
CFG.JOY_DECAY       = 0.0025 -- уходит в секунду (~ 2-4 минуты после еды)
CFG.JOY_WEIGHT      = 0.6   -- насколько радость поднимает цель настроения
-- опиоиды (морфин, фентанил и всё, что даёт обезболивание-анальгезию)
CFG.OPIOID_EUPHORIA = 0.3   -- прибавка к цели за единицу анальгезии (до 2 единиц)
CFG.OPIOID_TOL_GAIN = 1 / 600  -- привыкание: чем чаще, тем слабее эйфория
CFG.OPIOID_TOL_MAX  = 0.7
CFG.OPIOID_TOL_DECAY = 1 / 1800
CFG.COMEDOWN_MUL    = 0.18  -- "отходняк": когда действие спадает, настроение проседает
CFG.COMEDOWN_DECAY  = 0.003
CFG.HIGH_WEIGHT     = 0.45  -- насколько "кайф" от препаратов поднимает настроение
CFG.HIGH_DECAY      = 1 / 180 -- кайф уходит за ~3 минуты
-- (CFG.DESPAIR_HEART_CHANCE убран: от настроения сердце больше не останавливается)
CFG.HURT_MOOD       = 0.006 -- удар по настроению за единицу урона (падение, удар, ранение)
-- боль
CFG.PAIN_MAX_DROP   = 0.8   -- насколько сильно боль может опустить цель (было 0.5)
CFG.PAIN_FULL       = 80    -- при такой боли цель опускается на максимум (было 120)
CFG.PAIN_FALL_MUL   = 3     -- во сколько раз быстрее падает настроение при боли = PAIN_FULL
CFG.PAIN_DRAIN      = 0.0004 -- прямое снижение happiness в секунду за 1 единицу боли (сверх 10)
CFG.PHRASE_MIN      = 70    -- пауза между хорошими фразами, сек
CFG.PHRASE_MAX      = 160

CFG.phrases = {
    {"Today is actually a pretty good day.", "I feel great right now!", "Things are going my way."},
    {"I could run all day!", "Man, I love being alive.", "Nothing can stop me today!"},
    {"Everything's gonna be alright.", "Life's not that bad, you know?", "I'm proud of myself."},
}

-- чего персонаж "хочет" сейчас: 0 - совсем плохо, 1 - отлично
local function TargetHappiness(org)
    -- нейтральное состояние ~ настроение 0. Еда, лекарства и приятные дела поднимают выше.
    local t = 0.5

    -- депрессия немного "держит" настроение внизу, но не загоняет его в ноль сама
    local dep = org.depression or 0
    t = t - dep * 0.3

    -- "сырая" боль: адреналин после падения/удара её глушит в org.pain, но настроение всё равно портится
    local pain = max(org.pain or 0, (org.avgpain or 0) * 0.85)
    t = t - min(pain / CFG.PAIN_FULL, 1) * CFG.PAIN_MAX_DROP

    local hungry = org.hungry or 0
    t = t - (hungry / 100) * 0.4
    local thirst = org.thirst or 0
    if thirst > 30 then t = t - (thirst - 30) / 70 * 0.4 end
    if (org.satiety or 0) > 60 then t = t + 0.06 end -- сытый

    local blood = org.blood or 5000
    if blood < 4500 then t = t - (4500 - blood) / 2000 * 0.4 end

    local temp = org.temperature or 36.7
    if temp < 35.5 then t = t - 0.2 elseif temp > 38.5 then t = t - 0.15 end

    t = t - Clamp(org.fear or 0, 0, 2) * 0.15
    if org.panicattack and org.panicattack > 0 then t = t - 0.3 end

    -- целый и здоровый - уже повод радоваться
    local hurt = (org.lleg or 0) + (org.rleg or 0) + (org.larm or 0) + (org.rarm or 0) + (org.chest or 0) + (org.skull or 0)
    if hurt <= 0 and pain < 5 and (org.bleed or 0) <= 0 then t = t + 0.1 end
    -- адреналин настроение НЕ поднимает (иначе падение/удар "радовали" бы)

    -- "плохой день": депрессивный эпизод без причины (sv_depression.lua)
    if (org.remBadDayUntil or 0) > CurTime() then t = t - (org.remBadDayPower or 0.55) end

    -- приятные дела
    t = t + (org.remJoy or 0) * CFG.JOY_WEIGHT

    -- опиоиды: эйфория (слабее с привыканием) и отходняк после
    local an = Clamp(org.analgesia or 0, 0, 2)
    t = t + an * CFG.OPIOID_EUPHORIA * (1 - (org.remOpioidTol or 0))
    -- остальные препараты (бета-блокатор, тиамин...): "кайф" org.remHigh
    t = t + (org.remHigh or 0) * CFG.HIGH_WEIGHT * (1 - (org.remOpioidTol or 0) * 0.5)
    t = t - (org.remComedown or 0)

    return Clamp(t, 0, 1)
end

-- препарат, от которого "весело" (морфин, фентанил, обезболивающие, бета-блокатор, тиамин...)
function hg.organism.AddDrugHigh(org, amount)
    if not org then return end
    org.remHigh = Clamp((org.remHigh or 0) + amount, 0, 1.5)
    if org.happiness then org.happiness = min(1, org.happiness + amount * 0.25) end
end

-- любое приятное событие из других систем: hg.organism.AddJoy(org, 0.1)
function hg.organism.AddJoy(org, amount)
    if not org then return end
    org.remJoy = Clamp((org.remJoy or 0) + amount, 0, 1)
    -- чуть-чуть сразу, чтобы было заметно
    if org.happiness then org.happiness = min(1, org.happiness + amount * 0.5) end
end

-- любой урон (падение, удар, ранение) - сразу удар по настроению
hook.Add("EntityTakeDamage", "REM_MoodHurt", function(ent, dmg)
    local ply = ent:IsPlayer() and ent or (IsValid(ent.ply) and ent.ply) or nil
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local org = ply.organism
    if not org or not org.alive or org.moodLockUntil then return end
    local d = dmg:GetDamage()
    if d < 2 then return end
    org.happiness = math.max(0, (org.happiness or 0.6) - math.min(d * CFG.HURT_MOOD, 0.35))
    org.remJoy = math.max(0, (org.remJoy or 0) - d * 0.01)
end)

hook.Add("Org Clear", "REM_Mood", function(org)
    org.remJoy, org.remOpioidTol, org.remComedown, org.remLastAnalgesia = 0, 0, 0, 0
    org.remHigh = 0
    org.moodLockUntil, org.moodLockHappiness = nil, nil
    org.happiness = 0.6
    org.mood = 0.2
    org.moodLastSatiety = org.satiety or 0
    org.moodNextPhrase = CurTime() + math.Rand(CFG.PHRASE_MIN, CFG.PHRASE_MAX)
end)

hook.Add("Org Think", "REM_Mood", function(owner, org, timeValue)
    if not org.alive or org.otrub then return end
    if org.happiness == nil then org.happiness = 0.6 end

    -- поел - радость (сытость растёт по чуть-чуть за укус, поэтому считаем каждую прибавку)
    local sat = org.satiety or 0
    local last = org.moodLastSatiety or sat
    if sat > last then
        hg.organism.AddJoy(org, (sat - last) * CFG.JOY_PER_SATIETY)
    end
    org.moodLastSatiety = sat
    org.remJoy = max(0, (org.remJoy or 0) - timeValue * CFG.JOY_DECAY)

    -- опиоиды: привыкание и отходняк
    local an = org.analgesia or 0
    local lastAn = org.remLastAnalgesia or an
    if an > 0.05 then
        org.remOpioidTol = min(CFG.OPIOID_TOL_MAX, (org.remOpioidTol or 0) + timeValue * CFG.OPIOID_TOL_GAIN * min(an, 2))
    else
        org.remOpioidTol = max(0, (org.remOpioidTol or 0) - timeValue * CFG.OPIOID_TOL_DECAY)
    end
    if an < lastAn then
        org.remComedown = min(0.5, (org.remComedown or 0) + (lastAn - an) * CFG.COMEDOWN_MUL)
    end
    -- отходняк держится, пока действие спадает, и рассасывается после
    if an < 0.05 then
        org.remComedown = max(0, (org.remComedown or 0) - timeValue * CFG.COMEDOWN_DECAY)
    end
    org.remLastAnalgesia = an

    -- кайф от препаратов уходит, оставляя небольшой отходняк
    if (org.remHigh or 0) > 0 then
        local drop = min(org.remHigh, timeValue * CFG.HIGH_DECAY)
        org.remHigh = org.remHigh - drop
        org.remComedown = min(0.5, (org.remComedown or 0) + drop * CFG.COMEDOWN_MUL)
    end

    local target = TargetHappiness(org)
    if org.moodLockUntil and CurTime() < org.moodLockUntil then
        target = org.moodLockHappiness or target -- выдано командой: держим
    else
        org.moodLockUntil, org.moodLockHappiness = nil, nil
    end
    -- от боли настроение падает быстрее: ускоряем движение вниз + прямое "выжигание"
    local pain = max(org.pain or 0, (org.avgpain or 0) * 0.85) -- "сырая" боль, как и в цели
    local painF = Clamp(pain / CFG.PAIN_FULL, 0, 1)
    local speed = CFG.FOLLOW_SPEED
    if target < org.happiness then speed = speed * (1 + (CFG.PAIN_FALL_MUL - 1) * painF) end
    org.happiness = Approach(org.happiness, target, timeValue * speed)
    if pain > 10 and not org.moodLockUntil then
        org.happiness = max(0, org.happiness - timeValue * CFG.PAIN_DRAIN * (pain - 10))
    end
    org.mood = math.Round(Clamp(org.happiness * 2 - 1, -1, 1), 2)

    -- Z-SCAV: остановки сердца от настроения больше нет (даже при -100)

    local happy = org.mood > CFG.HAPPY_FROM
    if not happy then return end
    local f = (org.mood - CFG.HAPPY_FROM) / (1 - CFG.HAPPY_FROM)

    -- хорошие слова
    if owner:IsPlayer() and CurTime() >= (org.moodNextPhrase or 0) then
        org.moodNextPhrase = CurTime() + math.Rand(CFG.PHRASE_MIN, CFG.PHRASE_MAX)
        local tier = CFG.phrases[math.Clamp(math.ceil(f * #CFG.phrases), 1, #CFG.phrases)]
        owner:Notify(tier[math.random(#tier)], 6, "rem_mood_happy", 0)
    end
end)

-- ---------------------------------------------------------------------------
-- выдача настроения (только админы / серверная консоль)
--
--   rem_mood <игрок> <-100..100> [секунд]
--       задать настроение. Если указаны секунды - настроение держится это время,
--       иначе дальше меняется само от состояния персонажа.
--   rem_depression <игрок> <0..100>
--       задать депрессию.
--
--   <игрок>: часть ника, ^ - я сам, * - все
--   примеры: rem_mood ^ 100 120     rem_mood * -60     rem_depression Steven 0
-- ---------------------------------------------------------------------------
local function FindTargets(caller, who)
    if who == "^" then return IsValid(caller) and {caller} or {} end
    if who == "*" then return player.GetAll() end
    local res = {}
    who = string.lower(who or "")
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), who, 1, true) then res[#res + 1] = p end
    end
    return res
end

local function Reply(caller, msg)
    if IsValid(caller) then caller:ChatPrint("[REM] " .. msg) else print("[REM] " .. msg) end
end

local function CanUse(caller)
    return not IsValid(caller) or caller:IsAdmin()
end

concommand.Add("rem_mood", function(caller, _, args)
    if not CanUse(caller) then return end
    local value = tonumber(args[2])
    if not args[1] or not value then
        Reply(caller, "rem_mood <игрок|^|*> <-100..100> [секунд]")
        return
    end
    local mood = Clamp(value / 100, -1, 1)
    local secs = tonumber(args[3])
    local targets = FindTargets(caller, args[1])
    for _, p in ipairs(targets) do
        local org = p.organism
        if org and org.alive then
            org.happiness = (mood + 1) / 2
            org.mood = mood
            if secs and secs > 0 then
                org.moodLockUntil = CurTime() + secs
                org.moodLockHappiness = org.happiness
            else
                org.moodLockUntil, org.moodLockHappiness = nil, nil
            end
            org.moodNextPhrase = CurTime() + 3 -- если стал радостным - скажет что-нибудь почти сразу
            if hg.send_organism then hg.send_organism(org, p) end
        end
    end
    Reply(caller, ("настроение %+d выдано: %d игрок(ов)%s"):format(value, #targets, secs and (" на " .. secs .. " сек") or ""))
end)

concommand.Add("rem_depression", function(caller, _, args)
    if not CanUse(caller) then return end
    local value = tonumber(args[2])
    if not args[1] or not value then
        Reply(caller, "rem_depression <игрок|^|*> <0..100>")
        return
    end
    local targets = FindTargets(caller, args[1])
    for _, p in ipairs(targets) do
        local org = p.organism
        if org and org.alive then
            org.depression = Clamp(value / 100, 0, 1)
            org.depressionStage = 0 -- мысль новой стадии появится сразу
            if hg.send_organism then hg.send_organism(org, p) end
        end
    end
    Reply(caller, ("депрессия %d%% выдана: %d игрок(ов)"):format(value, #targets))
end)
