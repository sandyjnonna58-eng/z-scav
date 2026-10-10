--[[
    Z-SCAV: типы депрессии.

    Каждому персонажу при появлении достаётся свой тип (проявляется, только когда
    персонаж в депрессии или настроение ниже -30):
      despair   ОТЧАЯННЫЙ   - намного чаще отказывается от действий (подобрать, взять, нажать,
                              использовать предмет): шанс отказа x1.6
      deprived  ОБДЕЛЁННЫЙ  - отказывается от ЛЮБЫХ действий: кроме обычных - стрелять/бить,
                              прыгать, бежать, перезаряжаться, присесть (шанс отказа x1.25)
      sadist    САДИСТ      - чаще сам стреляет/бьёт (срывы) и ствол чаще сам тянется к людям;
                              урон, полученный в бою от других, ПОДНИМАЕТ настроение
                              (свой урон, падения и окружение - нет)

    zscav_deptypes 0 - выключить. Админ: zscav_deptype <despair|deprived|sadist|random> [ник]
]]

local cv = CreateConVar("zscav_deptypes", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: типы депрессии", 0, 1)

hg.organism.depTypes = {
    despair  = {name = "ОТЧАЯННАЯ",  refuse = 1.6},
    deprived = {name = "ОБДЕЛЁННАЯ", refuse = 1.25},
    sadist   = {name = "САДИСТСКАЯ", refuse = 0.7},
}
local TYPES = hg.organism.depTypes
local ORDER = {"despair", "deprived", "sadist"}

local SADIST_PSYCHO_RATE = 1 / 70   -- доп. срыв: раз в ~70 с
local SADIST_AIM_RATE    = 1 / 45   -- доп. "ствол тянется": раз в ~45 с
local SADIST_AIM_MOOD    = -0.3     -- у садиста тяга начинается уже с -30 настроения

-- активен ли тип (есть депрессия или плохое настроение)
local function Active(org)
    if not cv:GetBool() or not org or not org.alive or not org.remDepType then return false end
    return (org.depression or 0) >= 0.2 or (org.mood or 0) <= -0.3
end
hg.organism.DepTypeActive = function(org) return Active(org) and org.remDepType or nil end

hook.Add("Org Clear", "ZSCAV_DepTypes", function(org)
    org.remDepType = ORDER[math.random(#ORDER)]
end)

-- шанс отказа зависит от типа (оборачиваем функцию из sv_rem_apathy.lua)
timer.Simple(0, function()
    local orig = hg.organism.RefuseChance
    if not orig or hg.organism.RefuseChanceBase then return end
    hg.organism.RefuseChanceBase = orig
    hg.organism.RefuseChance = function(org)
        local c = orig(org)
        if c > 0 and Active(org) then c = math.min(c * TYPES[org.remDepType].refuse, 0.95) end
        return c
    end
end)

-- ОБДЕЛЁННЫЙ: отказ от любых действий (кнопки)
local BUTTONS = {
    {IN_ATTACK, "dep_attack"}, {IN_ATTACK2, "dep_attack2"}, {IN_JUMP, "dep_jump"},
    {IN_SPEED, "dep_sprint"}, {IN_RELOAD, "dep_reload"}, {IN_DUCK, "dep_duck"},
}
hook.Add("StartCommand", "ZSCAV_DepDeprived", function(ply, cmd)
    if not ply:Alive() then return end
    local org = ply.organism
    if not Active(org) or org.remDepType ~= "deprived" or not hg.ZSCAVApathyRefuse then return end
    local btn = cmd:GetButtons()
    local changed = false
    for _, b in ipairs(BUTTONS) do
        if bit.band(btn, b[1]) ~= 0 and hg.ZSCAVApathyRefuse(ply, b[2]) then
            btn = bit.band(btn, bit.bnot(b[1]))
            changed = true
        end
    end
    if changed then cmd:SetButtons(btn) end
end)

-- САДИСТ: чаще срывы и тяга ствола
hook.Add("Org Think", "ZSCAV_DepSadist", function(owner, org, timeValue)
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() or org.otrub then return end
    if not Active(org) or org.remDepType ~= "sadist" then return end
    if GetConVar("zscav_psychosis") and not GetConVar("zscav_psychosis"):GetBool() then return end
    local now = CurTime()
    if (org.mood or 0) <= SADIST_AIM_MOOD and now >= (org.remAimPullNext or 0) and hg.organism.StartAimPull
        and math.Rand(0, 1) < SADIST_AIM_RATE * timeValue then
        if hg.organism.StartAimPull(owner) then
            org.remAimPullNext = now + 30
            org.remPsychosisNext = math.max(org.remPsychosisNext or 0, now + 15)
            return
        end
    end
    if now >= (org.remPsychosisNext or 0) and hg.organism.PsychosisEpisode
        and math.Rand(0, 1) < SADIST_PSYCHO_RATE * timeValue then
        org.remPsychosisNext = now + 25
        hg.organism.PsychosisEpisode(owner)
    end
end)

-- САДИСТ: урон в бою от других поднимает настроение
local SADIST_LINES = {"Ха... ещё!", "Вот это я понимаю.", "Больно? Хорошо.", "Давай, давай!"}
hook.Add("HomigradDamage", "ZSCAV_DepSadist", function(ply, dmgInfo)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local org = ply.organism
    if not Active(org) or org.remDepType ~= "sadist" then return end
    local att = dmgInfo and dmgInfo:GetAttacker()
    if not IsValid(att) or att == ply or att:IsWorld() then return end
    if not (att:IsPlayer() or att:IsNPC() or att:IsNextBot()) then return end
    local dmg = dmgInfo:GetDamage() or 0
    if dmg <= 0 then return end
    if hg.organism.AddJoy then hg.organism.AddJoy(org, math.Clamp(dmg / 100, 0.02, 0.2)) end
    if (org.remSadistLine or 0) < CurTime() then
        org.remSadistLine = CurTime() + 15
        ply:Notify(SADIST_LINES[math.random(#SADIST_LINES)], 3, "zscav_sadist", 0)
    end
end)

concommand.Add("zscav_deptype", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local t = args[1]
    local target = caller
    if args[2] then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(args[2]), 1, true) then target = p break end
        end
    end
    if not IsValid(target) or not target.organism then return end
    if t == "random" or not TYPES[t or ""] then t = ORDER[math.random(#ORDER)] end
    target.organism.remDepType = t
    local m = target:Nick() .. ": тип депрессии - " .. TYPES[t].name
    if IsValid(caller) then caller:ChatPrint(m) else print(m) end
end)
