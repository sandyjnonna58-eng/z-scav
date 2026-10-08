--[[
    REM: депрессия (замена оригинального модуля Remorse).

    Копится от травм и тяжёлых состояний (как в оригинальном Remorse): боль, страх, кровопотеря,
    сильное кровотечение, удушье, переломы/обездвиженность, холод, паника, ампутации, отключки.
    Адреналин это глушит. Сама уходит со временем (в покое быстрее, глубокая - медленнее).
    Плюс работает поверх настроения (sv_mood.lua):
      * долго плохое настроение (org.mood < LOW_MOOD)  -> депрессия копится
      * хорошее настроение (org.mood > GOOD_MOOD)      -> депрессия уходит

    Эффекты депрессии:
      * экранный эффект и звук - клиент уже рисует их по org.depression (cl_screeneffects.lua)
      * персонаж медленнее ходит (movement/sh_inertia.lua)
      * грустные мысли по стадиям

    Механики самоповреждения и "позывов" из оригинала убраны.
    Сетевые сообщения оставлены пустыми, чтобы старый клиентский код не ругался.
]]

local max, min, Clamp = math.max, math.min, math.Clamp
hg.organism.module.depression = {}
local module = hg.organism.module.depression

hg.organism.depressionCfg = hg.organism.depressionCfg or {}
local CFG = hg.organism.depressionCfg

CFG.LOW_MOOD    = -0.75   -- ниже (отчаяние, -75) - начинается депрессия
CFG.GOOD_MOOD   = 0.2     -- выше - уходит
CFG.GAIN        = 0.006   -- рост в секунду при mood = -1  (~3 минуты до максимума)
CFG.HEAL        = 0.004   -- спад в секунду при mood = +1
CFG.NATURAL     = 0.0004  -- небольшой спад сам по себе
CFG.SLOW        = 0.10    -- -10% скорости при депрессии 1 (sh_inertia.lua)
CFG.THOUGHT_CD  = 30      -- пауза между мыслями одной стадии (как в оригинале)

-- источники депрессии из оригинального Remorse (в секунду, пока условие выполняется)
CFG.SRC = {
    pain      = {from = 60,   gain = 0.02},   -- боль выше
    fear      = {from = 3,    gain = 0.015},  -- страх выше
    blood     = {from = 3500, gain = 0.01},   -- крови меньше
    bleed     = {from = 5,    gain = 0.03, maxmul = 4}, -- сильное кровотечение (растёт с силой)
    o2        = {from = 15,   gain = 0.02},   -- кислорода меньше
    bones     = {gain = 0.012},               -- обездвижен / сломан позвоночник или нога
    cold      = {from = 35,   gain = 0.01},   -- переохлаждение
    panic     = {gain = 0.02},                -- паническая атака
    amputated = {gain = 0.015},               -- нет руки/ноги
    otrub     = {gain = 0.005},               -- без сознания
}
CFG.ADREN_FROM = 0.5      -- адреналин выше - депрессия от травм копится слабее
CFG.ADREN_MIN  = 0.1      -- (но не меньше 10% от обычного)
CFG.DRAIN_TIME       = 300  -- депрессия сама уходит за 5 минут
CFG.DRAIN_BOOST_TIME = 100  -- ...или за 100 с, если спокойно (боль < 30, страх < 2, кровь > 4000)
CFG.DRAIN_DEEP_DIV   = 2.5  -- глубокая депрессия (> 50%) уходит в 2.5 раза медленнее

-- "плохой день": иногда депрессия накатывает сама, без причины
CFG.BADDAY_CHANCE  = 1 / (25 * 60) -- шанс в секунду (~раз в 25 минут игры)
CFG.BADDAY_MIN     = 180            -- длительность эпизода, сек
CFG.BADDAY_MAX     = 360
CFG.BADDAY_POWER   = {0.4, 0.75}    -- насколько роняет настроение (0.5 ~ -100 настроения)
CFG.BADDAY_DEP     = 0.0015         -- депрессия растёт в секунду во время эпизода
CFG.BADDAY_CD      = 10 * 60        -- минимум между эпизодами
CFG.BADDAY_LINES = {
    "I don't know why.. but everything feels heavy today.",
    "Nothing happened. I just feel empty.",
    "Today is one of those days..",
    "It's like a grey cloud came out of nowhere.",
}
CFG.BADDAY_END = {"It's getting a little lighter..", "The heaviness is fading a bit."}

-- приступ навязчивых мыслей (мини-игра, cl_rem_thoughts.lua)
CFG.EPISODE_FROM   = 0.45   -- с какой депрессии бывают приступы
CFG.EPISODE_CHANCE = 1 / 150 -- шанс в секунду при депрессии 1 (меньше депрессия - реже)
CFG.EPISODE_CD     = 150    -- минимум секунд между приступами
CFG.WIN_DEPRESSION = 0.12   -- победа: депрессия уменьшается
CFG.WIN_MOOD       = 0.15   -- и настроение растёт
CFG.LOSE_DEPRESSION = 0.12  -- поражение: депрессия растёт
CFG.LOSE_STUN      = 3      -- сек: персонажа "накрывает" (оглушение)

-- стадии и мысли. Только грусть, без подталкивания к вреду себе.
-- стадии как в оригинальном Remorse (0.25 / 0.35 / 0.5), мысли без подталкивания к вреду себе
CFG.stages = {
    {from = 0.25, lines = {
        "You are feeling down.",
        "A heavy weight settles on your chest.",
        "Everything looks duller than it should.",
        "You feel tired for no reason.",
    }},
    {from = 0.35, lines = {
        "You are feeling upset.",
        "A quiet sadness creeps over you.",
        "Nothing feels worth the effort.",
        "You can feel yourself slipping.",
    }},
    {from = 0.5, lines = {
        "You are feeling depressed.",
        "A grey fog settles over everything.",
        "You feel hollow, like something is missing.",
        "Nothing seems to matter anymore.",
    }},
}

util.AddNetworkString("rem_thoughts_mg")
util.AddNetworkString("rem_thoughts_mg_done")
util.AddNetworkString("rem_selfharm_press")
util.AddNetworkString("rem_selfharm_end")
net.Receive("rem_selfharm_press", function() end)

local function StageOf(dep)
    local s = 0
    for i, st in ipairs(CFG.stages) do
        if dep >= st.from then s = i end
    end
    return s
end

-- другие системы могут добавить депрессию плавно (как org.depressionadd в оригинале)
function hg.organism.AddDepression(org, amount)
    if not org then return end
    org.depressionadd = (org.depressionadd or 0) + amount
end

module[1] = function(org)
    org.depression = 0
    org.depressionadd = 0
    org.depressionStage = 0
    org.depressionNextThought = 0

    local owner = org.owner
    if IsValid(owner) and owner:IsPlayer() then
        owner.selfharming = nil
        owner:SetNWBool("selfharming", false)
    end
end

-- Z-SCAV: депрессия включена. Выключить: zscav_depression 0
local cvDepression = CreateConVar("zscav_depression", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: депрессия", 0, 1)

module[2] = function(owner, org, timeValue)
    if not cvDepression:GetBool() then
        org.depression = 0
        org.depressionadd = 0
        org.depressionStage = 0
        return
    end
    if not org.alive then return end
    org.depression = org.depression or 0

    local mood = org.mood or 0
    local dep = org.depression

    -- 1) травмы и тяжёлые состояния (механика оригинального Remorse)
    local S = CFG.SRC
    local add = 0
    local pain = org.pain or 0
    local fear = org.fear or 0
    local blood = org.blood or 5000
    if pain > S.pain.from then add = add + S.pain.gain * timeValue end
    if fear > S.fear.from then add = add + S.fear.gain * timeValue end
    if blood < S.blood.from then add = add + S.blood.gain * timeValue end
    local bleed = org.bleed or 0
    if bleed > S.bleed.from then add = add + S.bleed.gain * min(bleed / S.bleed.from, S.bleed.maxmul) * timeValue end
    local o2 = istable(org.o2) and org.o2[1] or 30
    if o2 < S.o2.from then add = add + S.o2.gain * timeValue end
    if (org.immobilization or 0) > 0 or (org.spine1 or 0) > 0.5 or (org.spine2 or 0) > 0.5 or (org.spine3 or 0) > 0.5
        or (org.lleg or 0) >= 0.5 or (org.rleg or 0) >= 0.5 then
        add = add + S.bones.gain * timeValue
    end
    if (org.temperature or 36.7) < S.cold.from then add = add + S.cold.gain * timeValue end
    if org.panicattackActive or (org.panicattack or 0) > 0 then add = add + S.panic.gain * timeValue end
    if org.larmamputated or org.rarmamputated or org.llegamputated or org.rlegamputated then add = add + S.amputated.gain * timeValue end
    if org.otrub then add = add + S.otrub.gain * timeValue end
    -- внешние добавки (другие системы: hg.organism.AddDepression / org.depressionadd)
    if (org.depressionadd or 0) > 0 then
        local applied = min(org.depressionadd, timeValue / 5)
        org.depressionadd = max(org.depressionadd - applied, 0)
        add = add + applied
    end
    -- адреналин глушит
    local adrenaline = org.adrenaline or 0
    if adrenaline > CFG.ADREN_FROM then
        add = add * max(1 - adrenaline * 0.2, CFG.ADREN_MIN)
    end
    dep = dep + add

    -- 2) настроение: отчаяние добавляет, хорошее настроение лечит
    if mood < CFG.LOW_MOOD then
        dep = dep + timeValue * CFG.GAIN * (-mood)
    elseif mood > CFG.GOOD_MOOD then
        dep = dep - timeValue * CFG.HEAL * mood
    end

    -- 3) естественный спад (как в оригинале: в покое быстрее, глубокая - медленнее)
    local drain = timeValue / CFG.DRAIN_TIME
    if pain < 30 and fear < 2 and blood > 4000 and not org.otrub then
        drain = drain * (CFG.DRAIN_TIME / CFG.DRAIN_BOOST_TIME)
    end
    if org.superfighter then drain = drain * 4 end
    if dep > 0.5 then drain = drain / CFG.DRAIN_DEEP_DIV end
    dep = dep - drain
    org.depression = Clamp(dep, 0, 1)

    if org.otrub or not IsValid(owner) or not owner:IsPlayer() then return end

    -- "плохой день"
    local nowB = CurTime()
    if (org.remBadDayUntil or 0) > nowB then
        org.depression = math.min(1, org.depression + timeValue * CFG.BADDAY_DEP)
    elseif org.remBadDayUntil and org.remBadDayUntil > 0 then
        org.remBadDayUntil = 0
        owner:Notify(CFG.BADDAY_END[math.random(#CFG.BADDAY_END)], 5, "rem_badday_end", 0)
    elseif nowB >= (org.remBadDayNext or 0) and math.Rand(0, 1) < CFG.BADDAY_CHANCE * timeValue then
        hg.organism.StartBadDay(owner)
    end

    -- приступ навязчивых мыслей
    local now0 = CurTime()
    if org.depression >= CFG.EPISODE_FROM and not owner.remThoughts and now0 >= (org.remThoughtsNext or 0)
        and math.Rand(0, 1) < CFG.EPISODE_CHANCE * org.depression * timeValue then
        hg.organism.StartThoughtsEpisode(owner)
    end

    local stage = StageOf(org.depression)
    local now = CurTime()
    local entered = stage > (org.depressionStage or 0)
    org.depressionStage = stage

    if stage > 0 and (entered or now >= (org.depressionNextThought or 0)) then
        org.depressionNextThought = now + CFG.THOUGHT_CD + math.Rand(0, CFG.THOUGHT_CD)
        local lines = CFG.stages[stage].lines
        local text = lines[math.random(#lines)]
        if owner:GetInfoNum("hg_newthoughts", 0) > 0 and owner.Thought then
            owner:Thought(text, 6, "rem_depression", 0)
        else
            owner:Notify(text, 6, "rem_depression", 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- приступ навязчивых мыслей: в ушах писк, по экрану летят мысли,
-- нужно поймать хорошие. Проиграл - персонажа "накрывает", депрессия глубже.
-- ---------------------------------------------------------------------------
-- Z-SCAV: мини-игра приступа мыслей убрана - функция больше ничего не запускает
local THOUGHTS_MINIGAME = false

function hg.organism.StartThoughtsEpisode(ply)
    if not THOUGHTS_MINIGAME or not cvDepression:GetBool() then return end
    local org = ply.organism
    if not org or not org.alive or ply.remThoughts then return end
    org.remThoughtsNext = CurTime() + CFG.EPISODE_CD
    ply.remThoughts = {start = CurTime(), dep = org.depression or 0}
    net.Start("rem_thoughts_mg")
        net.WriteFloat(math.Clamp(org.depression or 0, 0, 1))
    net.Send(ply)
end

net.Receive("rem_thoughts_mg_done", function(_, ply)
    local st = ply.remThoughts
    ply.remThoughts = nil
    local win = net.ReadBool()
    if not st then return end
    local org = ply.organism
    if not org or not org.alive then return end
    if win and CurTime() - st.start < 3 then win = false end -- слишком быстро - подозрительно

    if win then
        org.depression = math.max(0, (org.depression or 0) - CFG.WIN_DEPRESSION)
        if hg.organism.AddJoy then hg.organism.AddJoy(org, CFG.WIN_MOOD) end
        ply:Notify("It's okay. I'm still here. It will pass.", 6, "rem_thoughts_win", 0)
    else
        org.depression = math.min(1, (org.depression or 0) + CFG.LOSE_DEPRESSION)
        if org.happiness then org.happiness = math.max(0, org.happiness - 0.15) end
        org.fear = math.min(2, (org.fear or 0) + 0.5)
        if hg.LightStunPlayer then hg.LightStunPlayer(ply, CFG.LOSE_STUN) end
        ply:Notify("Everything is too much right now.. I need to talk to someone.", 7, "rem_thoughts_lose", 0)
    end
end)

hook.Add("PlayerDeath", "REM_Thoughts", function(ply) ply.remThoughts = nil end)

-- тест: rem_thoughts <игрок|^|*>  (админ)
concommand.Add("rem_thoughts", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local who = args[1] or "^"
    for _, p in ipairs(player.GetAll()) do
        if (who == "^" and p == caller) or who == "*" or (who ~= "^" and string.find(string.lower(p:Nick()), string.lower(who), 1, true)) then
            p.remThoughts = nil
            if p.organism then p.organism.remThoughtsNext = 0 end
            hg.organism.StartThoughtsEpisode(p)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- "плохой день" - депрессивный эпизод без причины
-- ---------------------------------------------------------------------------
function hg.organism.StartBadDay(ply, duration, power)
    local org = IsValid(ply) and ply.organism
    if not org or not org.alive then return end
    local now = CurTime()
    org.remBadDayUntil = now + (duration or math.Rand(CFG.BADDAY_MIN, CFG.BADDAY_MAX))
    org.remBadDayPower = power or math.Rand(CFG.BADDAY_POWER[1], CFG.BADDAY_POWER[2])
    org.remBadDayNext = org.remBadDayUntil + CFG.BADDAY_CD
    ply:Notify(CFG.BADDAY_LINES[math.random(#CFG.BADDAY_LINES)], 6, "rem_badday", 0)
end

hook.Add("Org Clear", "REM_BadDay", function(org)
    org.remBadDayUntil = 0
    org.remBadDayNext = CurTime() + 5 * 60 -- не сразу после появления
end)

-- тест: rem_badday <игрок|^|*> [секунд]  (админ)
concommand.Add("rem_badday", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local who, secs = args[1] or "^", tonumber(args[2])
    for _, p in ipairs(player.GetAll()) do
        if (who == "^" and p == caller) or who == "*" or (who ~= "^" and string.find(string.lower(p:Nick()), string.lower(who), 1, true)) then
            hg.organism.StartBadDay(p, secs)
        end
    end
end)
