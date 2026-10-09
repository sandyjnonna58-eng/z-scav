--[[
    Z-SCAV: настроение по механике Mood из Casualties: Unknown.

    Настроение -100..100 = ПОСТОЯННОЕ + ВРЕМЕННОЕ.
      Постоянное (org.happiness 0..1 = -100..100) копится от событий и состояний и само
        медленно возвращается к 0: из плюса 0.45/мин, из минуса 0.6/мин.
        Плюс: вкусная еда и питьё, сытость, сон, вправленный вывих (+3), удачные процедуры.
        Минус: боль, голод, жажда, кровотечение, холод/жар, болезнь, убийство человека,
               ранения, грязь, рвота.
        Хорошее настроение смягчает минусы (буфер).
      Временное считается заново каждый тик и пропадает вместе с причиной:
        плюс: опиаты и другие препараты;  минус: ломка, боль, голод/жажда ниже 40,
        страх/паника, болезнь, глухота, низкий объём крови, кровотечение (только ниже -50).
    Старт жизни: случайно от -10 до 10.

    Стадии (значки):  >10 Satisfied, >30 Excited, >50 Happy, >80 Gleeful
                      <-10 Feeling down, <-30 Gloomy, <-50 Depressed, <-75 Miserable
      ниже 0   - растущий шанс отказаться от действия (sv_rem_apathy.lua, таблица из вики)
      ниже -20 - разгон медленнее (movement/sh_inertia.lua)
      ниже -30 - последний бой не сработает (sv_rem_laststand.lua)
      ниже -75 - в меню здоровья можно использовать только опиаты (sv_rem_meduse.lua)
      энергия тратится до x2 быстрее при -100 (sv_rem_energy.lua)
    Сверху Z-SCAV: в хорошем настроении бег чуть быстрее и персонаж говорит хорошие фразы.
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
-- Casualties: Unknown
CFG.DECAY_POS       = 0.45 / 60 -- возврат постоянного настроения к 0 из плюса, в секунду
CFG.DECAY_NEG       = 0.60 / 60 -- ... из минуса
CFG.JOY_TO_MOOD     = 25    -- AddJoy(1) = +25 постоянного настроения
CFG.KILL_MOOD       = -8    -- убил человека
CFG.HURT_MAX        = 10    -- максимум минуса за один удар
CFG.PHRASE_MIN      = 70    -- пауза между хорошими фразами, сек
CFG.PHRASE_MAX      = 160

CFG.phrases = {
    {"А сегодня, вообще-то, неплохой день.", "Мне сейчас отлично!", "Всё идёт как надо."},
    {"Я бы мог бегать весь день!", "Как же здорово быть живым.", "Сегодня меня ничто не остановит!"},
    {"Всё будет хорошо.", "Жизнь не так уж плоха, знаешь?", "Я горжусь собой."},
}

local function N(v, d) return isnumber(v) and v or (d or 0) end
local function RawPain(org) return max(N(org.pain), N(org.avgpain) * 0.85) end
local function Hydration(org) return 100 - N(org.thirst) end
local function Sick(org) return Clamp(N(org.remSepsis), 0, 1) end

-- постоянные влияния: скорость изменения постоянного настроения, единиц в МИНУТУ
local function PermanentRate(org)
    local plus, minus = 0, 0
    local pain = RawPain(org)
    if pain > 10 then minus = minus + (min(pain, 100) - 10) / 90 * 8 end
    local sat = N(org.satiety, 70)
    if sat < 40 then minus = minus + (40 - sat) / 40 * 4 end
    local hyd = Hydration(org)
    if hyd < 40 then minus = minus + (40 - hyd) / 40 * 4 end
    if N(org.bleed) > 0 then minus = minus + 2 end
    local temp = N(org.temperature, 36.7)
    if temp < 35.5 or temp > 38.5 then minus = minus + 3 end
    if Sick(org) > 0.2 then minus = minus + 4 * Sick(org) end
    if sat >= 100 then plus = plus + 1.5 elseif sat >= 70 then plus = plus + 0.8 end -- сыт / наелся
    if org.remSleep then plus = plus + 2 end
    return plus, minus
end

-- временные влияния: сколько добавить к настроению прямо сейчас (-100..100)
local function Temporary(org, perm)
    local t = 0
    local pain = RawPain(org)
    t = t - min(pain * 0.3, 30)
    local sat = N(org.satiety, 70)
    if sat < 40 then t = t - (40 - sat) / 40 * 15 end
    local hyd = Hydration(org)
    if hyd < 40 then t = t - (40 - hyd) / 40 * 15 end
    t = t - Clamp(N(org.fear), 0, 2) * 8
    if N(org.panicattack) > 0 then t = t - 15 end
    t = t - Sick(org) * 30
    t = t - Clamp(N(org.remDeaf), 0, 1) * 10
    local blood = N(org.blood, 5000)
    if blood < 4500 then t = t - min((4500 - blood) / 1500 * 20, 30) end
    -- препараты
    local tol = N(org.remOpioidTol)
    t = t + Clamp(N(org.analgesia), 0, 2) * 20 * (1 - tol)
    t = t + N(org.remHigh) * 30 * (1 - tol * 0.5)
    t = t - N(org.remComedown) * 60
    -- депрессия и "плохой день" (sv_depression.lua)
    t = t - N(org.depression) * 20
    if N(org.remBadDayUntil) > CurTime() then t = t - N(org.remBadDayPower, 0.55) * 60 end
    -- кровотечение давит только когда уже совсем плохо
    if N(org.bleed) > 0 and perm + t < -50 then t = t - 10 end
    return t
end

local function AddPerm(org, amount)
    org.happiness = Clamp(N(org.happiness, 0.5) + amount / 200, 0, 1)
end
hg.organism.AddMoodPermanent = function(org, amount) if org then AddPerm(org, amount) end end

-- препарат, от которого "весело" (морфин, фентанил, обезболивающие, бета-блокатор, тиамин...)
function hg.organism.AddDrugHigh(org, amount)
    if not org then return end
    org.remHigh = Clamp((org.remHigh or 0) + amount, 0, 1.5)
end

-- любое приятное событие из других систем: hg.organism.AddJoy(org, 0.1)
function hg.organism.AddJoy(org, amount)
    if not org then return end
    -- Z-SCAV (CU): приятное событие = постоянная прибавка настроения
    AddPerm(org, amount * CFG.JOY_TO_MOOD)
end

-- любой урон (падение, удар, ранение) - сразу удар по настроению
hook.Add("EntityTakeDamage", "REM_MoodHurt", function(ent, dmg)
    local ply = ent:IsPlayer() and ent or (IsValid(ent.ply) and ent.ply) or nil
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local org = ply.organism
    if not org or not org.alive or org.moodLockUntil then return end
    local d = dmg:GetDamage()
    if d < 2 then return end
    AddPerm(org, -math.min(d * 0.3, CFG.HURT_MAX))
end)

-- CU: убил человека - тяжело на душе (постоянно)
hook.Add("PlayerDeath", "ZSCAV_MoodKill", function(victim, _, attacker)
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    local org = attacker.organism
    if org and org.alive then AddPerm(org, CFG.KILL_MOOD) end
end)

hook.Add("Org Clear", "REM_Mood", function(org)
    org.remJoy, org.remOpioidTol, org.remComedown, org.remLastAnalgesia = 0, 0, 0, 0
    org.remHigh = 0
    org.moodLockUntil, org.moodLockHappiness = nil, nil
    local start = math.Rand(-10, 10) -- CU: старт от -10 до 10
    org.happiness = (start / 100 + 1) / 2
    org.mood = math.Round(start / 100, 2)
    org.moodLastSatiety = org.satiety or 0
    org.moodNextPhrase = CurTime() + math.Rand(CFG.PHRASE_MIN, CFG.PHRASE_MAX)
end)

hook.Add("Org Think", "REM_Mood", function(owner, org, timeValue)
    if not org.alive or (org.otrub and not org.remSleep) then return end -- во сне настроение восстанавливается
    if org.happiness == nil then org.happiness = 0.5 end

    -- поел - радость (сытость растёт по чуть-чуть за укус, поэтому считаем каждую прибавку)
    local sat = org.satiety or 0
    local last = org.moodLastSatiety or sat
    if sat > last then
        hg.organism.AddJoy(org, (sat - last) * CFG.JOY_PER_SATIETY)
    end
    org.moodLastSatiety = sat
    org.remJoy = 0

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

    -- постоянное настроение: возврат к 0 + постоянные влияния (хорошее настроение смягчает минусы)
    local perm = N(org.happiness, 0.5) * 200 - 100
    if perm > 0 then perm = max(0, perm - CFG.DECAY_POS * timeValue)
    elseif perm < 0 then perm = min(0, perm + CFG.DECAY_NEG * timeValue) end
    local plus, minus = PermanentRate(org)
    local buffer = 1 - 0.5 * Clamp(perm, 0, 100) / 100
    perm = Clamp(perm + (plus - minus * buffer) / 60 * timeValue, -100, 100)

    local mood100
    if org.moodLockUntil and CurTime() < org.moodLockUntil then
        perm = N(org.moodLockHappiness, 0.5) * 200 - 100 -- выдано командой: держим
        mood100 = perm
    else
        org.moodLockUntil, org.moodLockHappiness = nil, nil
        mood100 = Clamp(perm + Temporary(org, perm), -100, 100)
    end
    org.happiness = (perm + 100) / 200
    org.remMoodTemp = mood100 - perm
    org.mood = math.Round(mood100 / 100, 2)

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
