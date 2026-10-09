--[[
    Z-SCAV: здоровье кожи (по Casualties: Unknown, Limb health -> Skin health).

    У каждой части тела своя кожа 0..100.
      * рана (пуля, нож, осколок, ссадина, укус...) - кожа на этой части повреждается,
        тем сильнее, чем больше рана
      * огонь/ожоги - кожа горит по всему телу
    Повреждённая кожа:
      * болит: до 15 боли на часть (как в CU)
      * ниже 80 - шанс ИНФЕКЦИИ, растёт с повреждением и если часть кровит
        инфекция: боль, жар (температура), со временем хуже; уходит, когда кожа зажила выше 80
    Заживление: ~0.0694/с (ниже 10 - ~0.0137/с, как в CU), сытым - быстрее.
    Данные для меню здоровья уходят клиенту сетевой переменной "remSkin".
    Выключить: zscav_skin 0
]]

local cv = CreateConVar("zscav_skin", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: здоровье кожи", 0, 1)

hg.organism.skinCfg = hg.organism.skinCfg or {}
local CFG = hg.organism.skinCfg
CFG.REGEN       = 0.0694  -- в секунду
CFG.REGEN_LOW   = 0.0137  -- ниже LOW
CFG.LOW         = 10
CFG.FED_MUL     = 1.5     -- сытость выше 60 - заживает быстрее
CFG.WOUND_MUL   = 6       -- урон коже за единицу "крови" раны
CFG.WOUND_MIN   = 8       -- минимум за любую рану
CFG.BURN_MUL    = 1.2     -- урон коже за единицу урона огнём (на все части)
CFG.PAIN_MAX    = 15      -- боль от кожи на часть
CFG.INFECT_FROM = 80      -- ниже - шанс инфекции
CFG.INFECT_RATE = 0.0025  -- шанс в секунду при коже 0 (масштабируется)
CFG.INFECT_GROW = 0.12    -- запасная скорость инфекции (%/с), если нет модуля иммунитета
-- (спад инфекции теперь считает иммунитет: sv_rem_immunity.lua)
CFG.SYNC        = 1       -- сек между отправками клиенту
-- сепсис: запущенная инфекция переходит в заражение крови
CFG.SEPSIS_FROM  = 70     -- инфекция (на любой части) выше - сепсис растёт
CFG.SEPSIS_GROW  = 0.004  -- в секунду (~4 минуты до максимума)
CFG.SEPSIS_HEAL  = 0.002  -- спад, когда инфекций нет
CFG.SEPSIS_HP_FROM = 0.6  -- выше - уходит здоровье
CFG.SEPSIS_HP_TICK = 6

local PARTS = {"head", "neck", "chest", "abdomen", "r_upperarm", "r_forearm", "r_hand", "l_upperarm", "l_forearm", "l_hand",
    "r_thigh", "r_shin", "r_foot", "l_thigh", "l_shin", "l_foot"}

local function Init(org)
    org.remSepsis = 0
    org.remSkin, org.remInfect = {}, {}
    for _, p in ipairs(PARTS) do org.remSkin[p], org.remInfect[p] = 100, 0 end
    org.remSkinSeen = setmetatable({}, {__mode = "k"})
end

local function PartOfBone(owner, bone)
    if isnumber(bone) and IsValid(owner) then bone = owner:GetBoneName(bone) end
    return bone and hg.RemPartByBone and hg.RemPartByBone[bone]
end

-- Z-SCAV: бинт / аптечка подлечивают кожу части тела
function hg.organism.HealSkin(org, part, amount)
    if not org or not org.remSkin or not org.remSkin[part] then return end
    org.remSkin[part] = math.Clamp(org.remSkin[part] + amount, 0, 100)
end

function hg.organism.DamageSkin(org, part, amount)
    if not org or not org.remSkin or not org.remSkin[part] then return end
    org.remSkin[part] = math.Clamp(org.remSkin[part] - amount, 0, 100)
end

local function Sync(owner, org)
    if not IsValid(owner) or not owner.SetNetVar then return end
    local t = {}
    for _, p in ipairs(PARTS) do
        local s, i = org.remSkin[p] or 100, org.remInfect[p] or 0
        if s < 99.5 or i > 0.5 then t[p] = {math.Round(s), math.Round(i)} end
    end
    owner:SetNetVar("remSkin", t)
end

hook.Add("Org Clear", "ZSCAV_Skin", function(org)
    Init(org)
    if IsValid(org.owner) then Sync(org.owner, org) end
end)

-- ожоги
hook.Add("HomigradDamage", "ZSCAV_SkinBurn", function(ply, dmg)
    if not cv:GetBool() or not IsValid(ply) then return end
    local org = ply.organism
    if not org or not org.remSkin then return end
    if dmg:IsDamageType(DMG_BURN) or dmg:IsDamageType(DMG_SLOWBURN) then
        local d = dmg:GetDamage() * CFG.BURN_MUL
        for _, p in ipairs(PARTS) do hg.organism.DamageSkin(org, p, d * math.Rand(0.5, 1)) end
    end
end)

hook.Add("Org Think", "ZSCAV_Skin", function(owner, org, timeValue)
    if not cv:GetBool() or not org.alive or not IsValid(owner) or not owner:IsPlayer() then return end
    if not org.remSkin then Init(org) end

    -- новые раны -> урон коже на их части
    local seen = org.remSkinSeen
    local bleedingPart = {}
    for _, w in ipairs(org.wounds or {}) do
        local part = PartOfBone(owner, w[4])
        if part then
            bleedingPart[part] = true
            if not seen[w] then
                seen[w] = true
                local mul = org.remSkinNextMul or 1 -- ссадины и т.п. бьют по коже слабее
                org.remSkinNextMul = nil
                hg.organism.DamageSkin(org, part, math.max(CFG.WOUND_MIN, (w[1] or 0) * 2 * CFG.WOUND_MUL) * mul)
            end
        end
    end
    for _, w in ipairs(org.arterialwounds or {}) do
        local part = PartOfBone(owner, w[4])
        if part then bleedingPart[part] = true end
    end

    local fed = (org.satiety or 0) > 60 and CFG.FED_MUL or 1
    local pain, fever = 0, 0
    for _, p in ipairs(PARTS) do
        local s = org.remSkin[p]
        -- заживление
        local r = (s < CFG.LOW and CFG.REGEN_LOW or CFG.REGEN) * fed
        s = math.min(100, s + r * timeValue)
        org.remSkin[p] = s
        -- боль
        pain = pain + (100 - s) / 100 * CFG.PAIN_MAX
        -- инфекция
        local inf = org.remInfect[p] or 0
        if s < CFG.INFECT_FROM then
            if inf <= 0 then
                local chance = CFG.INFECT_RATE * (CFG.INFECT_FROM - s) / CFG.INFECT_FROM * (bleedingPart[p] and 2 or 1)
                -- грязь (sv_rem_dirt.lua) повышает шанс заражения
                if hg.organism.DirtInfectMul then chance = chance * hg.organism.DirtInfectMul(org) end
                if math.Rand(0, 1) < chance * timeValue then
                    inf = 1
                    owner:Notify("This wound looks bad.. it's getting infected.", 5, "zscav_infect", 0)
                end
            end
        end
        -- развитие/регрессия инфекции по иммунитету (sv_rem_immunity.lua);
        -- часть считается продезинфицированной после перевязки или если рана закрылась (кожа 80+)
        if inf > 0 then
            local dis = (org.remDisinfect and (org.remDisinfect[p] or 0) > CurTime()) or s >= CFG.INFECT_FROM
            local rate = hg.organism.InfectionRate and hg.organism.InfectionRate(org, dis) or (CFG.INFECT_GROW)
            inf = math.Clamp(inf + rate * timeValue, 0, 100)
        end
        org.remInfect[p] = inf
        if inf > 0 then
            pain = pain + inf / 100 * 10
            fever = math.max(fever, inf / 100)
        end
    end

    -- боль от кожи и инфекции: постоянный небольшой приток (организм сам её "гасит", так что держится на уровне)
    org.remSkinPain = pain
    org.painadd = (org.painadd or 0) + timeValue * math.min(pain * 0.08, 4)
    -- сепсис
    local maxInf = 0
    for _, p in ipairs(PARTS) do maxInf = math.max(maxInf, org.remInfect[p] or 0) end
    local sep = org.remSepsis or 0
    if maxInf >= CFG.SEPSIS_FROM then
        if sep <= 0 then owner:Notify("I feel feverish and weak.. something is very wrong.", 6, "zscav_sepsis", 0) end
        sep = math.min(1, sep + timeValue * CFG.SEPSIS_GROW * (maxInf / 100))
    elseif maxInf <= 0 then
        sep = math.max(0, sep - timeValue * CFG.SEPSIS_HEAL)
    end
    org.remSepsis = sep
    if sep > 0 then
        fever = math.max(fever, 0.6 + sep * 0.4)
        -- слабость, частое сердце
        if istable(org.stamina) and isnumber(org.stamina[1]) then
            org.stamina[1] = math.max(0, org.stamina[1] - timeValue * 2 * sep)
        end
        org.heartbeat = math.max(org.heartbeat or 70, 90 + 40 * sep)
        if org.happiness then org.happiness = math.max(0, org.happiness - timeValue * 0.002 * sep) end
        if sep >= CFG.SEPSIS_HP_FROM and CurTime() >= (org.remSepsisHpT or 0) then
            org.remSepsisHpT = CurTime() + CFG.SEPSIS_HP_TICK
            local hp = owner:Health() - 1
            if hp <= 0 then owner:Kill() else owner:SetHealth(hp) end
        end
    end

    -- жар от инфекции/сепсиса
    if fever > 0 and org.temperature then
        org.temperature = math.min(org.temperature + timeValue * 0.01 * fever, 36.7 + 3 * fever)
    end

    if CurTime() >= (org.remSkinSync or 0) then
        org.remSkinSync = CurTime() + CFG.SYNC
        Sync(owner, org)
    end
end)
