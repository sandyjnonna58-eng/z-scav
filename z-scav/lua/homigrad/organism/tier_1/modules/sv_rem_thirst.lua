--[[
    Z-SCAV: жажда + общая функция "съел/выпил".

    org.thirst 0..100 - жажда. Растёт со временем, быстрее при беге, жаре и кровопотере.
    Напитки (банки, сок, вода, кола, молоко...) сильно утоляют жажду, еда - чуть-чуть.

    Стадии:
      30+  хочется пить - мысли, настроение падает (sv_mood.lua)
      50+  жажда        - выносливость восстанавливается медленнее, болит голова
      70+  обезвоживание - слабость: медленнее ходишь (movement/sh_inertia.lua), давление падает
      90+  сильное обезвоживание - медленно теряешь здоровье, включается "Is this the end"
    Выключить: zscav_thirst 0
]]

local zscav_thirst = CreateConVar("zscav_thirst", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: жажда", 0, 1)
local max, min, Clamp = math.max, math.min, math.Clamp

hg.organism.thirstCfg = hg.organism.thirstCfg or {}
local CFG = hg.organism.thirstCfg
CFG.GROW        = 100 / (25 * 60) -- в секунду в покое (0 -> 100 примерно за 25 минут)
CFG.FOOD_MUL    = 2.5             -- еда в предметах рассчитана на старую систему - масштабируем под шкалу сытости 0..100
CFG.RUN_MUL     = 2.2             -- при беге
CFG.HOT_MUL     = 1.8             -- при температуре выше 37.5
CFG.BLEED_MUL   = 1.6             -- при кровопотере (крови меньше 4500)
CFG.STAMINA_FROM = 50
CFG.WEAK_FROM   = 70
CFG.HURT_FROM   = 90
CFG.HURT_HP     = 1
CFG.HURT_TICK   = 5
CFG.THOUGHT_CD  = 70

-- еда/питьё из любых предметов: food - сытость, water - сколько жажды снять
function hg.organism.Consume(org, food, water, wep)
    if not org then return end
    -- Z-SCAV: кофе, газировка и энергетики бодрят (sv_rem_energy.lua)
    if hg.organism.IsEnergyDrink and hg.organism.AddEnergy and hg.organism.IsEnergyDrink(wep) then
        hg.organism.AddEnergy(org, (water or 0) * hg.organism.EnergyCFG.DRINK_ENERGY, true)
    end
    -- Z-SCAV: можно переесть (выше 100) - тогда может вырвать (sv_rem_overeat.lua)
    org.satiety = min((org.satiety or 0) + (food or 0) * CFG.FOOD_MUL, 150)
    org.hungry = max(0, 100 - org.satiety)
    local before = org.thirst or 0
    org.thirst = max(0, before - (water or 0))
    -- утолил жажду - приятно (сильнее, если очень хотелось пить)
    local relief = before - org.thirst
    if relief > 0 and hg.organism.AddJoy then
        hg.organism.AddJoy(org, relief * 0.004 * (0.4 + before / 100))
    end
end

hook.Add("Org Clear", "ZSCAV_Thirst", function(org)
    org.thirst = 0
    org.thirstHurtT = 0
    org.thirstThought = 0
end)

local THOUGHTS = {
    [1] = {"I could use a drink.", "My mouth is dry."},
    [2] = {"I'm really thirsty..", "My head hurts, I need water."},
    [3] = {"I need water. Now.", "Everything feels weak.. I need a drink."},
    [4] = {"I'm so dehydrated..", "Water.. please.."},
}

hook.Add("Org Think", "ZSCAV_Thirst", function(owner, org, timeValue)
    if not zscav_thirst:GetBool() or not org.alive then return end
    org.thirst = org.thirst or 0

    local mul = 1
    if IsValid(owner) and owner:IsPlayer() and owner:KeyDown(IN_SPEED) and owner:GetVelocity():Length2DSqr() > 150 * 150 then mul = mul * CFG.RUN_MUL end
    if (org.temperature or 36.7) > 37.5 then mul = mul * CFG.HOT_MUL end
    if (org.blood or 5000) < 4500 then mul = mul * CFG.BLEED_MUL end
    org.thirst = min(100, org.thirst + timeValue * CFG.GROW * mul)

    local t = org.thirst
    -- жажда: выносливость восстанавливается хуже
    if t >= CFG.STAMINA_FROM and istable(org.stamina) and isnumber(org.stamina[1]) then
        org.stamina[1] = max(0, org.stamina[1] - timeValue * (t - CFG.STAMINA_FROM) / 50 * 1.5)
    end
    if t >= CFG.STAMINA_FROM then
        org.painadd = (org.painadd or 0) + timeValue * 0.15 * (t - CFG.STAMINA_FROM) / 50 -- головная боль
    end
    -- обезвоживание: давление падает
    if t >= CFG.WEAK_FROM and org.bloodPressure then
        org.bloodPressure = max(40, org.bloodPressure - timeValue * 0.3 * (t - CFG.WEAK_FROM) / 30)
    end
    if not IsValid(owner) or not owner:IsPlayer() then return end

    -- сильное обезвоживание: уходит здоровье
    if t >= CFG.HURT_FROM and CurTime() >= (org.thirstHurtT or 0) then
        org.thirstHurtT = CurTime() + CFG.HURT_TICK
        local hp = owner:Health() - CFG.HURT_HP
        if hp <= 0 then owner:Kill() else owner:SetHealth(hp) end
    end

    -- мысли
    local stage = t >= 90 and 4 or (t >= 70 and 3 or (t >= 50 and 2 or (t >= 30 and 1 or 0)))
    if stage > 0 and not org.otrub and CurTime() >= (org.thirstThought or 0) then
        org.thirstThought = CurTime() + CFG.THOUGHT_CD + math.Rand(0, 40)
        local list = THOUGHTS[stage]
        owner:Notify(list[math.random(#list)], 5, "zscav_thirst", 0)
    end
end)
