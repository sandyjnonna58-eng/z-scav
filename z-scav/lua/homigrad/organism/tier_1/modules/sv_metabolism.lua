--[[
    Голод (Z-SCAV), одна шкала - как в Casualties: Unknown.

    org.satiety 0..100 - СЫТОСТЬ. Тратится постоянно, в реальном времени
                         (100 -> 0 примерно за 30 минут, при беге быстрее). Еда её восполняет.
    org.hungry  0..100 - голод = 100 - сытость (оставлен для совместимости со старым кодом).

    Сытая (60+)  - кровь и здоровье понемногу восстанавливаются
    Стадии голода (по сытости):
      < 75  "хочется есть" - мысли, настроение падает (sv_mood.lua)
      < 55  голоден        - меньше выносливость, приступы боли в животе
      < 35  очень голоден  - слабость: медленнее ходишь (movement/sh_inertia.lua)
      < 15  истощение      - урон желудку, медленно уходит здоровье; включается "Is this the end"
    Выключить голод: zscav_hunger 0
]]
local hg_hungersystem = CreateConVar("hg_hungersystem", 0, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Enables/disabled hunger system", 0, 1)
local zscav_hunger = CreateConVar("zscav_hunger", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: голод", 0, 1)
local max, min, Round = math.max, math.min, math.Round

hg.organism.hungerCfg = hg.organism.hungerCfg or {}
local CFG = hg.organism.hungerCfg
CFG.PAIN_FROM   = 45      -- голод (100 - сытость), с которого приступы боли в животе
CFG.WEAK_FROM   = 65      -- слабость
CFG.STARVE_FROM = 85      -- истощение
CFG.STARVE_HP   = 1       -- здоровья за тик истощения
CFG.STARVE_TICK = 6       -- сек

local function Enabled()
    return zscav_hunger:GetBool() or hg_hungersystem:GetBool()
end
hg.organism.HungerEnabled = Enabled

--local Organism = hg.organism
hg.organism.module.metabolism = {}
local module = hg.organism.module.metabolism
CFG.SPEND       = 100 / (30 * 60) -- сытости в секунду (100 -> 0 примерно за 30 минут)
CFG.RUN_MUL     = 1.6             -- при беге тратится быстрее
CFG.REGEN_FROM  = 60              -- с какой сытости идёт восстановление
CFG.START       = 80              -- сытость после возрождения

module[1] = function(org)
	org.satiety = CFG.START
    org.hungry = 100 - CFG.START
    org.hungryDmgCd = 0
    org.hungerStarveT = 0
end

module[2] = function(owner, org, timeValue)
    if Enabled() then
        local mul = 1
        if IsValid(owner) and owner:IsPlayer() and owner:KeyDown(IN_SPEED) and owner:GetVelocity():Length2DSqr() > 150 * 150 then mul = CFG.RUN_MUL end
        org.satiety = math.Clamp((org.satiety or 0) - timeValue * CFG.SPEND * mul, 0, 150) -- выше 100 - переедание
    end
    org.hungry = Round(math.max(0, 100 - (org.satiety or 0)), 3)

    if not Enabled() then return end

    org.hungryDmgCd = org.hungryDmgCd or 0
    if org.alive and org.hungryDmgCd < CurTime() and org.hungry > CFG.PAIN_FROM then
        -- приступ боли в животе
        org.painadd = org.painadd + 12 * (org.hungry / CFG.PAIN_FROM)
        org.hungryDmgCd = CurTime() + (math.random(40, 55) - (org.hungry / 5.5))
        if org.hungry > 80 then
            org.stomach = math.min(org.stomach + 0.05, 1)
            if org.stomach > 0.85 and org.heart < 0.3 then
                org.heart = org.heart + 0.05
            end
        end
    end

    -- истощение: медленно уходит здоровье
    if org.alive and org.hungry >= CFG.STARVE_FROM and IsValid(owner) and owner:IsPlayer() and CurTime() >= (org.hungerStarveT or 0) then
        org.hungerStarveT = CurTime() + CFG.STARVE_TICK
        local hp = owner:Health() - CFG.STARVE_HP
        if hp <= 0 then owner:Kill() else owner:SetHealth(hp) end
    end

    -- больной живот после еды
    if (org.intestines > 0.5 or org.stomach > 0.5) and not org.otrub and IsValid(owner) and owner:IsPlayer() and org.satiety > 1 then
        if not org.randomPainSound or org.randomPainSound < CurTime() then
            org.randomPainSound = CurTime() + math.random(20,45)
            owner:EmitSound("zcitysnd/"..(ThatPlyIsFemale(owner) and "female" or "male").."/pain_"..math.random(1,8)..".mp3")
            org.painadd = org.painadd + 20
        end
    end

    -- сытый организм восстанавливается
    if org.satiety >= CFG.REGEN_FROM and IsValid(owner) then
        local k = math.min(1, (org.satiety - CFG.REGEN_FROM) / (100 - CFG.REGEN_FROM))
        org.blood = min(org.blood + timeValue * 4 * k, 5000)
        if owner:IsPlayer() then
            org.regeneratehp = (!((org.regeneratehp or 0) >= 1) and min((org.regeneratehp or 0) + timeValue * 0.3 * k, 1)) or 0
            owner:SetHealth(min(owner:Health() + org.regeneratehp, 100))
        end
    end
end
