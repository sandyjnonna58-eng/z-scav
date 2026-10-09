--[[
    Z-SCAV: срывы (психоз) - персонаж иногда сам стреляет или бьёт.

    Кого накрывает (сила срыва 0..1, берётся самая большая):
      * черта Schizophrenia                 0.5
      * черта Maniac                        0.4
      * черта PTSD + сильный страх          0.5
      * паническая атака                    0.6
      * отчаяние (настроение -75 и ниже)    0.3 .. 0.6 (растёт с депрессией)
      * сильный страх                       0.4
      * повреждение мозга от 40%            = повреждению
    Шанс срыва в секунду = сила * RATE, не чаще раза в COOLDOWN секунд.

    Что происходит при срыве:
      * огнестрел в руках - палец сам жмёт на спуск (короткая очередь), ствол дёргается
      * кулаки / холодное оружие и рядом кто-то есть - персонаж разворачивается к нему и бьёт
      * рядом никого - бьёт воздух
    Выключить: zscav_psychosis 0
]]

local cv = CreateConVar("zscav_psychosis", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: срывы - сам стреляет/бьёт", 0, 1)

hg.organism.psychosisCfg = hg.organism.psychosisCfg or {}
local CFG = hg.organism.psychosisCfg
CFG.RATE        = 1 / 180  -- шанс в секунду при силе 1 (~раз в 3 минуты)
CFG.COOLDOWN    = 45
CFG.FIRE_MIN    = 0.08     -- сек удержания спуска
CFG.FIRE_MAX    = 0.45
CFG.MELEE_RANGE = 90       -- на каком расстоянии бьёт ближайшего
CFG.MELEE_HITS  = {1, 3}   -- сколько ударов подряд

-- отчаяние (настроение -75 и ниже) с огнестрелом в руках: ствол сам тянется к случайному
-- игроку рядом, и если не отвести прицел - палец жмёт на спуск (клиент: cl_rem_aimpull.lua)
CFG.AIMPULL_MOOD     = -0.75
CFG.AIMPULL_RATE     = 1 / 90   -- шанс в секунду (~раз в полторы минуты)
CFG.AIMPULL_COOLDOWN = 60
CFG.AIMPULL_RANGE    = 1500
CFG.AIMPULL_TIME     = 4        -- сек на то, чтобы отвести прицел

util.AddNetworkString("zscav_aimpull")

local PHRASES = {
    "Мои руки.. двигались сами..",
    "Я не хотел.. Я не...",
    "Что я делаю?!",
    "Что-то взяло верх..",
    "Стой.. СТОЙ!",
}

local function HasTrait(ply, id)
    local en = GetConVar("zcity_delta_traits_enabled")
    if en and not en:GetBool() then return false end
    local t = ply.__zcity_delta_traits
    return istable(t) and t[id] == true
end

local function Level(ply, org)
    local L = 0
    if HasTrait(ply, "schizophrenia") then L = math.max(L, 0.5) end
    if HasTrait(ply, "maniac") then L = math.max(L, 0.4) end
    local fear = org.fear or 0
    if HasTrait(ply, "ptsd") and fear > 0.6 then L = math.max(L, 0.5) end
    if (org.panicattack or 0) > 0 then L = math.max(L, 0.6) end
    if (org.mood or 0) <= -0.75 then L = math.max(L, 0.3 + (org.depression or 0) * 0.3) end
    if fear > 1 then L = math.max(L, 0.4) end
    if (org.brain or 0) >= 0.4 then L = math.max(L, math.min(org.brain, 1)) end
    return L
end
hg.organism.PsychosisLevel = Level

local function NearestTarget(ply)
    local eye = ply:EyePos()
    local best, bestD
    for _, other in ipairs(player.GetAll()) do
        if other ~= ply and other:Alive() then
            local pos = other:WorldSpaceCenter()
            local d = pos:Distance(eye)
            if d <= CFG.MELEE_RANGE and (not bestD or d < bestD) then
                local tr = util.TraceLine({start = eye, endpos = pos, filter = {ply, other}, mask = MASK_SOLID_BRUSHONLY})
                if not tr.Hit then best, bestD = other, d end
            end
        end
    end
    return best
end

local function PressAttack(ply, hold)
    ply:ConCommand("+attack")
    timer.Simple(hold, function() if IsValid(ply) then ply:ConCommand("-attack") end end)
end

function hg.organism.PsychosisEpisode(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local wep = ply:GetActiveWeapon()
    local isGun = IsValid(wep) and ishgweapon and ishgweapon(wep) and not wep.ismelee
    ply:Notify(PHRASES[math.random(#PHRASES)], 4, "zscav_psychosis", 0)

    if isGun then
        -- ствол дёргается, палец жмёт на спуск
        ply:SetEyeAngles(ply:EyeAngles() + Angle(math.Rand(-6, 6), math.Rand(-15, 15), 0))
        PressAttack(ply, math.Rand(CFG.FIRE_MIN, CFG.FIRE_MAX))
        return
    end

    local target = NearestTarget(ply)
    if IsValid(target) then
        local dir = (target:WorldSpaceCenter() - ply:EyePos()):GetNormalized()
        ply:SetEyeAngles(dir:Angle())
    end
    local hits = math.random(CFG.MELEE_HITS[1], CFG.MELEE_HITS[2])
    for i = 0, hits - 1 do
        timer.Simple(i * 0.45, function()
            if not IsValid(ply) or not ply:Alive() then return end
            if IsValid(target) and target:Alive() then
                local dir = (target:WorldSpaceCenter() - ply:EyePos()):GetNormalized()
                ply:SetEyeAngles(dir:Angle())
            end
            PressAttack(ply, 0.12)
        end)
    end
end

local function AimPullTarget(ply)
    local eye = ply:EyePos()
    local list = {}
    for _, other in ipairs(player.GetAll()) do
        if other ~= ply and other:Alive() then
            local pos = other:WorldSpaceCenter()
            if pos:DistToSqr(eye) <= CFG.AIMPULL_RANGE * CFG.AIMPULL_RANGE then
                local tr = util.TraceLine({start = eye, endpos = pos, filter = {ply, other}, mask = MASK_SHOT})
                if not tr.Hit then list[#list + 1] = other end
            end
        end
    end
    return list[math.random(#list)]
end

function hg.organism.StartAimPull(ply)
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and ishgweapon and ishgweapon(wep) and not wep.ismelee) then return false end
    local target = AimPullTarget(ply)
    if not IsValid(target) then return false end
    net.Start("zscav_aimpull")
        net.WriteEntity(target)
        net.WriteFloat(CFG.AIMPULL_TIME)
    net.Send(ply)
    local t = {"Они все против меня..", "Это было бы так просто..", "Почему они так на меня смотрят..", "Рука не слушается.."}
    ply:Notify(t[math.random(#t)], 4, "zscav_aimpull", 0)
    return true
end

hook.Add("Org Think", "ZSCAV_Psychosis", function(owner, org, timeValue)
    if not cv:GetBool() or not IsValid(owner) or not owner:IsPlayer() then return end
    if not org.alive or org.otrub or not owner:Alive() then return end
    if owner:InVehicle() or (owner.GlideGetVehicle and IsValid(owner:GlideGetVehicle())) then return end
    local now = CurTime()

    -- отчаяние: ствол тянется к людям
    if (org.mood or 0) <= CFG.AIMPULL_MOOD and now >= (org.remAimPullNext or 0)
        and math.Rand(0, 1) < CFG.AIMPULL_RATE * timeValue then
        if hg.organism.StartAimPull(owner) then
            org.remAimPullNext = now + CFG.AIMPULL_COOLDOWN
            org.remPsychosisNext = math.max(org.remPsychosisNext or 0, now + 20)
            return
        end
    end

    if now < (org.remPsychosisNext or 0) then return end
    local L = Level(owner, org)
    if L <= 0 then return end
    if math.Rand(0, 1) < L * CFG.RATE * timeValue then
        org.remPsychosisNext = now + CFG.COOLDOWN
        hg.organism.PsychosisEpisode(owner)
    end
end)

hook.Add("Org Clear", "ZSCAV_Psychosis", function(org) org.remPsychosisNext = CurTime() + 60 end)

-- тест: rem_aimpull ^   (админ)
concommand.Add("rem_aimpull", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local who = args[1] or "^"
    for _, p in ipairs(player.GetAll()) do
        if (who == "^" and p == caller) or who == "*" or (who ~= "^" and string.find(string.lower(p:Nick()), string.lower(who), 1, true)) then
            hg.organism.StartAimPull(p)
        end
    end
end)

-- тест: rem_psychosis ^   (админ)
concommand.Add("rem_psychosis", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local who = args[1] or "^"
    for _, p in ipairs(player.GetAll()) do
        if (who == "^" and p == caller) or who == "*" or (who ~= "^" and string.find(string.lower(p:Nick()), string.lower(who), 1, true)) then
            hg.organism.PsychosisEpisode(p)
        end
    end
end)
