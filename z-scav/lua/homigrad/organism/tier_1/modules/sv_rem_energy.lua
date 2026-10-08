--[[
    Z-SCAV: энергия и сон (по механике Energy из Casualties: Unknown).

    org.remEnergy   0..100 %
    org.remSleep    true, пока персонаж спит
    Бодрствуя теряешь 0.07 %/с (100 -> 0 примерно за 24 минуты).
      усталость (выносливость -> 0)  до x3.5
      сепсис ("болезнь" -> 100)      до x3
      настроение (-> -100)           до x2 (в плюсе не влияет)
      "взбодрён" (кофе, последний бой)  x0.55
    <=35 сонливость, <=25 усталость, <=15 сильная усталость, <=7 полусон, 0 - засыпаешь сам.
    Сон: кнопка "СОН" в меню здоровья (нельзя при энергии >35, сепсисе >80, боли >31).
    Качество сна зависит от поверхности: плохое 0.28 %/с, среднее 0.34, нормальное 0.4, хорошее 0.5.

    Команды: rem_energy <0..100> [игрок]  (админ),  zscav_energy 0/1 - выключить систему.
]]
local CFG = {
    LOSS        = 0.07,   -- %/с
    STAMINA_MUL = 3.5,
    SICK_MUL    = 3,
    MOOD_MUL    = 2,
    ENERGIZED   = 0.55,
    QUALITY     = {0.28, 0.34, 0.40, 0.50},      -- плохое, среднее, нормальное, хорошее
    QUALITY_WAKE = {70, 85, 100, 100},           -- при каком % просыпаешься сам
    SLEEP_MAX_ENERGY = 35,
    SLEEP_MAX_SICK   = 80,
    SLEEP_MAX_PAIN   = 31,
    UNCON_GAIN  = 0.2,    -- без сознания тоже немного отдыхаешь
    MANUAL_WAKE_MIN = 10, -- раньше этого % сам не проснёшься (кнопкой)
    -- этапы: {порог, множитель восстановления выносливости, потолок сознания, скорость падения сознания /с}
    STAGES = {
        {7,  0.35, 0.50, 1 / 25},
        {15, 0.55, 0.62, 1 / 60},
        {25, 0.75, 0.78, 1 / 120},
        {35, 0.90, 1,    0},
    },
    ENERGIZED_TIME = 240,
    DRINK_ENERGY   = 0.5,  -- % энергии за единицу "воды" у бодрящих напитков
}
hg.organism.EnergyCFG = CFG

local cv = CreateConVar("zscav_energy", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: энергия и сон", 0, 1)
util.AddNetworkString("zscav_sleep")

local min, max, Clamp = math.min, math.max, math.Clamp
local function N(v, d) return isnumber(v) and v or (d or 0) end

local function Sickness(org) return Clamp(N(org.remSepsis) * 100, 0, 100) end

function hg.organism.EnergyStage(org)
    local e = N(org.remEnergy, 100)
    for i, s in ipairs(CFG.STAGES) do
        if e <= s[1] then return 5 - i, s end -- 4 полусон .. 1 сонливость
    end
    return 0
end

function hg.organism.AddEnergy(org, amount, energize)
    if not org then return end
    org.remEnergy = Clamp(N(org.remEnergy, 100) + (amount or 0), 0, 100)
    if energize then org.remEnergized = CurTime() + (isnumber(energize) and energize or CFG.ENERGIZED_TIME) end
end

local DRINK_WORDS = {"cola", "coffee", "soda", "energy", "pepsi", "sprite", "monster", "mtn", "redbull"}
function hg.organism.IsEnergyDrink(wep)
    if not IsValid(wep) then return false end
    local mdl = string.lower(tostring(wep.WorldModel or ""))
    for _, wd in ipairs(DRINK_WORDS) do
        if string.find(mdl, wd, 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- качество сна: на чём лежим
-- ---------------------------------------------------------------------------
local GOOD_WORDS = {"bed", "mattress", "couch", "sofa", "sleeping", "pillow"}
local SOFT = {[MAT_DIRT] = true, [MAT_GRASS] = true, [MAT_SAND] = true, [MAT_SNOW] = true, [MAT_FOLIAGE] = true}
local OKAY = {[MAT_WOOD] = true, [MAT_PLASTIC] = true, [MAT_FLESH] = true}

local function SleepEntity(owner)
    local rag = owner.FakeRagdoll
    if IsValid(rag) then return rag end
    return owner
end

local function SleepQuality(owner)
    if owner:IsPlayer() and owner:InVehicle() then return 3 end
    local ent = SleepEntity(owner)
    local pos = ent:WorldSpaceCenter()
    local tr = util.TraceLine({start = pos, endpos = pos - Vector(0, 0, 70), filter = {ent, owner}, mask = MASK_SOLID})
    if not tr.Hit then return 1 end
    local hit = tr.Entity
    if IsValid(hit) then
        local mdl = string.lower(hit:GetModel() or "")
        for _, wd in ipairs(GOOD_WORDS) do
            if string.find(mdl, wd, 1, true) then return 4 end
        end
    end
    if OKAY[tr.MatType] then return 3 end
    if SOFT[tr.MatType] then return 2 end
    return 1
end

local function HeadInWater(owner)
    local ent = SleepEntity(owner)
    if ent ~= owner then
        local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
        local p = bone and ent:GetBonePosition(bone)
        if p then return bit.band(util.PointContents(p), CONTENTS_WATER) ~= 0 end
    end
    return owner:WaterLevel() >= 3
end

-- причина проснуться (или nil). Чем серьёзнее причина, тем при меньшей энергии она будит.
local function WakeReason(owner, org, quality)
    local e = N(org.remEnergy)
    local temp = N(org.temperature, 36.7)
    if temp < 30 then return "холод" end
    if org.vomitInThroat then return "рвота" end
    if e >= 1 and N(org.pain) > CFG.SLEEP_MAX_PAIN then return "боль" end
    if e >= 4 and HeadInWater(owner) then return "вода" end
    if e >= 40 and Sickness(org) > 55 then return "болезнь" end
    if e >= 45 and N(org.remComedown) * 200 > 34 then return "ломка" end
    if e >= 50 then
        if N(org.mood) < -0.5 then return "тяжёлые мысли" end
        if N(org.satiety, 70) < 35 then return "голод" end
        if (100 - N(org.thirst)) < 35 then return "жажда" end
        if Sickness(org) > 35 then return "болезнь" end
        if temp < 32 then return "холод" end
        if temp > 39.5 then return "жар" end
    end
    if e >= CFG.QUALITY_WAKE[quality] then
        return quality <= 2 and "неудобно спать" or "выспался"
    end
end

local function Notify(owner, text)
    if IsValid(owner) and owner:IsPlayer() then owner:ChatPrint("[Z-SCAV] " .. text) end
end

local function StartSleep(owner, org, forced)
    if org.remSleep then return end
    org.remSleep = true
    org.remSleepForced = forced and true or false
    org.remSleepStart = CurTime()
    org.remSleepQuality = SleepQuality(owner)
    if IsValid(owner) and owner:IsPlayer() then owner.fullsend = true end
end

local function StopSleep(owner, org, reason)
    if not org.remSleep then return end
    org.remSleep = false
    org.remSleepForced = false
    org.remSleepWoke = CurTime()
    if reason then Notify(owner, "Ты проснулся: " .. reason .. ".") end
    if IsValid(owner) and owner:IsPlayer() then owner.fullsend = true end
end
hg.organism.StartSleep = StartSleep
hg.organism.StopSleep = StopSleep

-- можно ли лечь спать сейчас; возвращает true или false + причину
function hg.organism.CanSleep(org)
    if not org or not org.alive then return false, "нельзя" end
    if org.remSleep then return false, "уже спишь" end
    if org.otrub then return false, "без сознания" end
    if N(org.remLastStandUntil) > CurTime() then return false, "организм на пределе - не до сна" end
    if N(org.remEnergy, 100) > CFG.SLEEP_MAX_ENERGY then return false, "ты не устал" end
    if Sickness(org) > CFG.SLEEP_MAX_SICK then return false, "слишком плохо, чтобы уснуть" end
    if N(org.pain) > CFG.SLEEP_MAX_PAIN then return false, "слишком больно, чтобы уснуть" end
    return true
end

-- вызывается из главного Org Think (sv_organism.lua), ПОСЛЕ сброса needotrub
function hg.organism.SleepThink(owner, org, timeValue, isPly)
    if not isPly or not cv:GetBool() then
        if org.remSleep then org.remSleep = false end
        org.remEnergyRegen = 1
        return
    end
    local now = CurTime()
    org.remEnergy = N(org.remEnergy, 100)

    -- последний бой: энергия на максимум, сон слетает
    if N(org.remLastStandUntil) > now then
        if not org.remEnergyLS then
            org.remEnergyLS = true
            org.remEnergy = 100
            org.remEnergized = now + CFG.ENERGIZED_TIME
            StopSleep(owner, org)
        end
    else
        org.remEnergyLS = false
    end

    if org.remSleep then
        local q = org.remSleepQuality or 1
        -- раз в пару секунд перепроверяем поверхность (могли перетащить)
        if (org.remSleepQNext or 0) < now then
            org.remSleepQNext = now + 2
            q = SleepQuality(owner)
            org.remSleepQuality = q
        end
        org.remEnergy = min(100, org.remEnergy + CFG.QUALITY[q] * timeValue)
        org.needotrub = true
        -- во сне выносливость возвращается, а боль чуть притупляется
        local st = org.stamina
        if istable(st) and isnumber(st[1]) and isnumber(st.max) then st[1] = min(st.max, st[1] + timeValue * 4) end
        org.remEnergyRegen = 1
        local why = WakeReason(owner, org, q)
        if why and (now - (org.remSleepStart or now)) > 3 then StopSleep(owner, org, why) end
        return
    end

    -- без сознания тоже копится немного сил
    if org.otrub then
        org.remEnergy = min(100, org.remEnergy + CFG.UNCON_GAIN * timeValue)
        org.remEnergyRegen = 1
        return
    end

    -- трата
    local mul = 1
    local st = org.stamina
    if istable(st) and isnumber(st[1]) then
        local mx = (isnumber(st.max) and st.max > 0) and st.max or N(st.range, 180)
        local f = Clamp(st[1] / max(mx, 1), 0, 1)
        mul = mul * (1 + (CFG.STAMINA_MUL - 1) * (1 - f))
    end
    mul = mul * (1 + (CFG.SICK_MUL - 1) * Sickness(org) / 100)
    local mood = N(org.mood)
    if mood < 0 then mul = mul * (1 + (CFG.MOOD_MUL - 1) * Clamp(-mood, 0, 1)) end
    if N(org.remEnergized) > now then mul = mul * CFG.ENERGIZED end
    org.remEnergy = max(0, org.remEnergy - CFG.LOSS * mul * timeValue)

    -- этапы усталости
    local stage, s = hg.organism.EnergyStage(org)
    if s then
        org.remEnergyRegen = s[2]
        if s[4] > 0 and N(org.consciousness, 1) > s[3] then
            org.consciousness = max(s[3], org.consciousness - s[4] * timeValue)
        end
    else
        org.remEnergyRegen = 1
    end

    if org.remEnergy <= 0 and (now - N(org.remSleepWoke, -999)) > 5 then
        Notify(owner, "Сил больше нет. Ты засыпаешь на ходу.")
        StartSleep(owner, org, true)
        org.needotrub = true
    end
end

-- кнопка "СОН" / "ПРОСНУТЬСЯ"
net.Receive("zscav_sleep", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if (ply.zscavSleepNext or 0) > CurTime() then return end
    ply.zscavSleepNext = CurTime() + 1
    local want = net.ReadBool()
    local org = ply.organism
    if not org or not cv:GetBool() then return end
    if want then
        local ok, why = hg.organism.CanSleep(org)
        if not ok then Notify(ply, "Не получается уснуть: " .. why .. ".") return end
        StartSleep(ply, org, false)
        Notify(ply, "Ты ложишься спать. ПРОБЕЛ - проснуться.")
    elseif org.remSleep then
        if N(org.remEnergy) < CFG.MANUAL_WAKE_MIN then return end
        StopSleep(ply, org, "сам")
    end
end)

hook.Add("Org Clear", "ZSCAV_Energy", function(org)
    org.remEnergy = 100
    org.remSleep = false
    org.remSleepForced = false
    org.remEnergized = 0
    org.remEnergyRegen = 1
    org.remEnergyLS = false
    org.remSleepWoke = nil
end)

concommand.Add("rem_energy", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local val = tonumber(args[1] or "")
    if not val then
        if IsValid(caller) and caller.organism then caller:ChatPrint(("Энергия: %.1f%%"):format(N(caller.organism.remEnergy, 100))) end
        return
    end
    local targets = {}
    if args[2] then
        local name = string.lower(args[2])
        for _, p in ipairs(player.GetAll()) do
            if name == "*" or string.find(string.lower(p:Nick()), name, 1, true) then targets[#targets + 1] = p end
        end
    elseif IsValid(caller) then
        targets[1] = caller
    end
    for _, p in ipairs(targets) do
        if p.organism then p.organism.remEnergy = Clamp(val, 0, 100) end
    end
end)
