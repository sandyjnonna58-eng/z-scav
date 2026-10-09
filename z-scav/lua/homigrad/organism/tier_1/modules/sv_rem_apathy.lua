--[[
    Z-SCAV: апатия.

    При плохом настроении (любом ниже 0, по таблице Casualties: Unknown) и депрессии
    персонаж иногда "не хочет" что-то делать:
      * поднять предмет / оружие с земли
      * взять предмет в руки (физический подбор на E)
      * нажать/открыть (двери, кнопки, ящики - E)
      * использовать предмет в руках (еда, медицина и т.п.)
    Решение принимается один раз на попытку (и держится пару секунд), так что можно
    попробовать снова - иногда получится. Чем глубже депрессия, тем чаще отказ.

    Сила апатии = max(депрессия, насколько настроение ниже -30).
    Выключить: zscav_apathy 0
]]

local cv = CreateConVar("zscav_apathy", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: апатия при депрессии", 0, 1)

hg.organism.apathyCfg = hg.organism.apathyCfg or {}
local CFG = hg.organism.apathyCfg
CFG.FROM        = 0.2   -- с какой силы апатии начинаются отказы
CFG.CHANCE_MIN  = 0.15  -- шанс отказа на пороге
CFG.CHANCE_MAX  = 0.6   -- шанс отказа при максимальной апатии
CFG.DECISION_T  = 2.5   -- сколько секунд держится решение по одной попытке
CFG.THOUGHT_CD  = 6     -- не спамить мыслями

local THOUGHTS = {
    "Не хочется..",
    "Какой смысл..",
    "Не сейчас.. Я просто не могу.",
    "Зачем стараться..",
    "Не могу себя заставить.",
    "Может, потом..",
}

local function ApathyLevel(org)
    if not org or not org.alive then return 0 end
    local dep = org.depression or 0
    local mood = org.mood or 0
    local fromMood = math.Clamp((-mood - 0.3) / 0.7, 0, 1)
    return math.max(dep, fromMood)
end
hg.organism.ApathyLevel = ApathyLevel

-- Casualties: Unknown: шанс отказа от действия по настроению
--   -100: 90%   -50: 36.43%   -30: 15%   -10: 5%   0 и выше: 0%
local REFUSE = {{-100, 0.90}, {-50, 0.3643}, {-30, 0.15}, {-10, 0.05}, {0, 0}}
function hg.organism.RefuseChance(org)
    if not org or not org.alive then return 0 end
    local m = math.Clamp((org.mood or 0) * 100, -100, 100)
    local c = 0
    if m < 0 then
        for i = 1, #REFUSE - 1 do
            local a, b = REFUSE[i], REFUSE[i + 1]
            if m >= a[1] and m <= b[1] then c = math.Remap(m, a[1], b[1], a[2], b[2]) break end
        end
    end
    -- депрессия добавляет апатии сверху (Z-SCAV)
    local dep = org.depression or 0
    if dep > 0.2 then c = math.max(c, 0.15 + 0.45 * math.Clamp((dep - 0.2) / 0.8, 0, 1)) end
    return c
end

-- true = персонаж отказывается. key - что именно пытаемся сделать (сущность/предмет)
function hg.ZSCAVApathyRefuse(ply, key)
    if not cv:GetBool() or not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    local org = ply.organism
    if hg.organism.RefuseChance(org) <= 0 then return false end

    -- одно решение на попытку
    ply.zscavApathy = ply.zscavApathy or {}
    local now = CurTime()
    local d = ply.zscavApathy[key]
    if d and now - d.t < CFG.DECISION_T then return d.refuse end

    local chance = hg.organism.RefuseChance(org)
    local refuse = math.Rand(0, 1) < chance
    ply.zscavApathy[key] = {t = now, refuse = refuse}

    if refuse and now >= (ply.zscavApathyThought or 0) then
        ply.zscavApathyThought = now + CFG.THOUGHT_CD
        ply:Notify(THOUGHTS[math.random(#THOUGHTS)], 3, "zscav_apathy", 0)
    end
    -- чистим старые решения
    if math.random() < 0.05 then
        for k, v in pairs(ply.zscavApathy) do
            if now - v.t > CFG.DECISION_T * 2 then ply.zscavApathy[k] = nil end
        end
    end
    return refuse
end

-- поднять оружие/предмет с земли (только лежащее в мире, не выдачу при спавне)
hook.Add("PlayerCanPickupWeapon", "ZSCAV_Apathy", function(ply, wep)
    if not IsValid(wep) or not wep.IsSpawned then return end
    if hg.ZSCAVApathyRefuse(ply, wep) then return false end
end)

-- взять предмет в руки (физический подбор)
hook.Add("AllowPlayerPickup", "ZSCAV_Apathy", function(ply, ent)
    if hg.ZSCAVApathyRefuse(ply, ent) then return false end
end)

-- E по двери/кнопке/ящику/предмету
hook.Add("PlayerUse", "ZSCAV_Apathy", function(ply, ent)
    if not IsValid(ent) then return end
    if hg.ZSCAVApathyRefuse(ply, ent) then return false end
end)

hook.Add("PlayerDeath", "ZSCAV_Apathy", function(ply) ply.zscavApathy = nil end)
