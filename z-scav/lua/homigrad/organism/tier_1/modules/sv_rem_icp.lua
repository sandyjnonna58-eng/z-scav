--[[
    Z-SCAV: внутричерепное давление (ВЧД), org.remICP в мм рт. ст. (норма ~10).

    Что поднимает:
      * кровоизлияние в мозг (org.brainHemorrhage)      до +35
      * повреждение мозга (отёк)                         до +25
      * перелом черепа (гематома)                        +6
      * нехватка кислорода (углекислота расширяет сосуды) до +12
      * высокое давление (систолическое > 160)           +0.1 за мм
      * жар выше 39 °C                                   +3 за градус
      * нейроцистицеркоз (sv_rem_diseases.lua)           до +38
    Что снижает: маннитол (weapon_zscav_mannitol) -15 на 4 минуты; само уходит, если причины нет.

    Эффекты:
      > 20  головная боль
      > 25  рвота, мутное зрение
      > 30  триада Кушинга: пульс падает, давление растёт; сознание мутнеет
      > 35  судороги
      > 40  вклинение мозга - мозг повреждается (чем выше, тем быстрее), может убить
    zscav_icp 0 - выключить. Админ: zscav_icp_set <мм> - выставить себе.
]]

local cv = CreateConVar("zscav_icp", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: внутричерепное давление", 0, 1)

hg.organism.icpCfg = hg.organism.icpCfg or {}
local CFG = hg.organism.icpCfg
CFG.BASE      = 10
CFG.RISE      = 1.5    -- мм/с к цели вверх
CFG.FALL      = 0.25   -- мм/с вниз (спадает медленно)
CFG.MANNITOL  = 15
CFG.MAX       = 70

local LINES = {
    [20] = {"Голова тяжёлая...", "Давит в висках."},
    [25] = {"Голова раскалывается. Тошнит.", "Всё плывёт перед глазами."},
    [30] = {"Голову распирает изнутри...", "Не могу сосредоточиться..."},
    [40] = {"Глаза... будто выдавливает...", "Я... отключаюсь..."},
}

local function Target(org)
    local t = CFG.BASE
    t = t + (org.brainHemorrhage or 0) * 35
    t = t + math.Clamp(org.brain or 0, 0, 1) * 25
    if (org.skull or 0) >= 1 then t = t + 6 end
    local o2 = istable(org.o2) and org.o2[1] or 30
    if o2 < 15 then t = t + (15 - o2) * 0.8 end
    if (org.systolic or 120) > 160 then t = t + ((org.systolic or 120) - 160) * 0.1 end
    if (org.temperature or 36.7) > 39 then t = t + ((org.temperature or 36.7) - 39) * 3 end
    t = t + (org.remICPAdd or 0)
    if (org.remMannitolUntil or 0) > CurTime() then t = t - CFG.MANNITOL end
    return math.Clamp(t, 5, CFG.MAX)
end

function hg.organism.ICPThink(owner, org, timeValue, isPly)
    local add = org.remICPAdd
    org.remICPAdd = 0
    org.remICPHR = 0
    if not cv:GetBool() or not isPly or not org.alive then org.remICP = CFG.BASE return end
    org.remICPAdd = add -- для расчёта цели в этом тике
    local dt, now = timeValue or 0, CurTime()
    local icp = org.remICP or CFG.BASE
    local target = Target(org)
    org.remICPAdd = 0
    icp = math.Approach(icp, target, (target > icp and CFG.RISE or CFG.FALL) * dt)
    if org.remICPForce then icp = org.remICPForce end
    org.remICP = icp

    if icp <= 20 then return end

    -- головная боль
    org.pain = math.max(org.pain or 0, math.min((icp - 20) * 1.6, 45))

    -- мысли
    if (org.remICPLine or 0) < now then
        org.remICPLine = now + math.Rand(45, 80)
        local lvl = icp >= 40 and 40 or icp >= 30 and 30 or icp >= 25 and 25 or 20
        local t = LINES[lvl]
        if IsValid(owner) and owner.Notify then owner:Notify(t[math.random(#t)], 4, "zscav_icp", 0) end
    end

    -- рвота
    if icp > 25 and (org.remICPVomit or 0) < now then
        org.remICPVomit = now + math.Rand(60, 120) * math.Clamp(30 / icp, 0.4, 1)
        if hg.organism.Vomit then
            local blood = org.blood
            hg.organism.Vomit(owner)
            if blood then org.blood = math.max(org.blood or 0, blood - 40) end
        end
    end

    -- триада Кушинга и сознание
    if icp > 30 then
        org.remICPHR = -math.min((icp - 30) * 1.2, 35)
        org.consciousness = math.min(org.consciousness or 1, math.Clamp(1 - (icp - 30) / 35, 0.25, 1))
        org.disorientation = math.max(org.disorientation or 0, 1 + (icp - 30) / 10)
    end

    -- судороги
    if icp > 35 and hg.organism.AddSeizure and math.Rand(0, 1) < dt * 0.004 * (icp - 34) then
        hg.organism.AddSeizure(org, 1)
    end

    -- вклинение: мозг повреждается
    if icp > 40 then
        org.brain = math.min((org.brain or 0) + dt * (icp - 40) * 0.00025, 1)
    end
end

hook.Add("Org Clear", "ZSCAV_ICP", function(org)
    org.remICP, org.remICPAdd, org.remICPHR, org.remMannitolUntil, org.remICPForce = CFG.BASE, 0, 0, 0, nil
end)

concommand.Add("zscav_icp_set", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not IsValid(ply) or not ply.organism then return end
    local v = tonumber(args[1] or "")
    ply.organism.remICPForce = v and math.Clamp(v, 5, CFG.MAX) or nil
    ply.organism.remICP = v or ply.organism.remICP
    ply:ChatPrint(v and ("ВЧД зафиксировано: %d мм рт.ст. (zscav_icp_set без числа - отпустить)"):format(v) or "ВЧД отпущено.")
end)
