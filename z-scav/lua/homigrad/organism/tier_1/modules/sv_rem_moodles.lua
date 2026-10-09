--[[
    Z-SCAV: эффекты мудлов из Casualties: Unknown (wiki: Moodles), которых ещё не было.

      Голод     <50 Hungry      - выносливость восстанавливается на 10% медленнее
                <35 Very hungry - на 20% медленнее
                <=15 Starving   - на 35% медленнее (здоровье уходит - sv_metabolism.lua)
      Сытость   >100 Satiated / >120 Full - чуть медленнее движение (movement/sh_inertia.lua)
      Вода      >100 Slaked        - жажда тратится вдвое быстрее, давление выше
                >125 Overhydrated  - движение чуть медленнее
                >=174 Water-intoxicated - давление сильно выше, шанс фибрилляции (sv_pulse.lua)
      Болезнь   (сепсис) >30% Nauseous - может стошнить, >50% Sick - часто тошнит
      Жар       >39 Hot - жажда быстрее, >40.25 Hyperthermia - намного быстрее (sv_rem_thirst.lua)
      Боль      >55 Severe pain - полусознание (сознание не выше 75%)
                >80 Agony       - движение затруднено (sh_inertia.lua)
      Сломанные рёбра - дышать больно: боль при беге
      Вывих/перелом челюсти, сломанная шея - есть больно (sv_rem_thirst.lua, Consume)
      Ломка ниже -34% (Dying of withdrawal) - растёт фибрилляция (sv_pulse.lua)

    Выключить: zscav_moodle_effects 0
]]
local cv = CreateConVar("zscav_moodle_effects", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: эффекты мудлов CU", 0, 1)
local function N(v, d) return isnumber(v) and v or (d or 0) end

local NAUSEA_MSG = {"Меня тошнит..", "Живот крутит..", "Меня сейчас вырвет.."}

hook.Add("Org Think", "ZSCAV_MoodleEffects", function(owner, org, timeValue)
    if not cv:GetBool() or not org.alive or not IsValid(owner) or not owner:IsPlayer() then
        org.remMoodleRegen = 1
        return
    end
    local now = CurTime()

    -- голод -> восстановление выносливости
    local sat = N(org.satiety, 70)
    local regen = 1
    if sat <= 15 then regen = 0.65 elseif sat < 35 then regen = 0.8 elseif sat < 50 then regen = 0.9 end
    org.remMoodleRegen = regen

    -- тошнота от болезни
    local sick = math.Clamp(N(org.remSepsis), 0, 1)
    if sick > 0.3 and not org.otrub and now >= N(org.remNauseaNext) then
        local chance = sick > 0.5 and 0.012 or 0.004
        if math.Rand(0, 1) < chance * timeValue * 4 then
            org.remNauseaNext = now + 25
            if hg.organism.FoodVomit then hg.organism.FoodVomit(owner, org, NAUSEA_MSG[math.random(#NAUSEA_MSG)]) end
        end
    end

    -- сильная боль: полусознание
    local pain = N(org.pain)
    if pain > 55 and N(org.consciousness, 1) > 0.75 then
        org.consciousness = math.max(0.75, org.consciousness - timeValue * 0.05)
    end

    -- сломанные рёбра: больно дышать на бегу
    if N(org.chest) >= 1 and owner:KeyDown(IN_SPEED) and owner:GetVelocity():Length2DSqr() > 150 * 150 then
        org.painadd = N(org.painadd) + timeValue * 2.5
    end
end)

hook.Add("Org Clear", "ZSCAV_MoodleEffects", function(org)
    org.remMoodleRegen = 1
    org.remNauseaNext = 0
end)
