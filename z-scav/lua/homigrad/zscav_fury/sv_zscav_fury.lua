--[[
    Z-SCAV: музыка босса для Fury-13 (сервер).
    Пока у игрока действует Fury-13 (берсерк), он помечен сетевым флагом - клиенты играют
    RUN_FOR_YOUR_LIFE "от него" (громкость по расстоянию).
    Кто убил игрока под Fury-13 - слышит ThornbackDefeat.

    В гейммоде смерть часто наступает не от последнего удара, а позже (кровопотеря, остановка
    сердца, таймер умирания), и "убийцей" в PlayerDeath оказывается мир или сам игрок.
    Поэтому запоминаем, кто последним ранил игрока под Fury-13, и что Fury-13 был недавно.
]]

util.AddNetworkString("zscav_fury_defeat")

local FURY_GRACE    = 30   -- сек: смерть в течение этого времени после конца Fury-13 тоже считается
local ATTACKER_TIME = 60   -- сек: последний ранивший считается убийцей это время

local function IsFury(ply)
    local org = ply.organism
    if not org or not ply:Alive() then return false end
    return (org.berserkActive2 or (org.berserk or 0) > 0.05) and true or false
end

-- игрок, стоящий за сущностью (оружие, снаряд, рэгдолл, машина)
local function OwnerPlayer(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    if IsValid(ent.ply) and ent.ply:IsPlayer() then return ent.ply end
    local o = ent.GetOwner and ent:GetOwner()
    if IsValid(o) and o:IsPlayer() then return o end
    if ent.LastAttacker and IsValid(ent.LastAttacker) and ent.LastAttacker:IsPlayer() then return ent.LastAttacker end
    if hg.RagdollOwner then
        local r = hg.RagdollOwner(ent)
        if IsValid(r) and r:IsPlayer() then return r end
    end
    if ent.GetDriver then
        local d = ent:GetDriver()
        if IsValid(d) and d:IsPlayer() then return d end
    end
end

timer.Create("ZSCAV_FuryFlag", 0.25, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local f = IsFury(ply)
        if f then ply.zscavFuryUntil = CurTime() + FURY_GRACE end
        if ply:GetNWBool("zscav_fury", false) ~= f then ply:SetNWBool("zscav_fury", f) end
    end
end)

-- кто ранил игрока под Fury-13
local function Remember(victim, dmg)
    if not IsValid(victim) or not victim:IsPlayer() then return end
    if (victim.zscavFuryUntil or 0) < CurTime() then return end
    local att = OwnerPlayer(dmg:GetAttacker()) or OwnerPlayer(dmg:GetInflictor())
    if IsValid(att) and att ~= victim then
        victim.zscavFuryAttacker = att
        victim.zscavFuryAttackerT = CurTime()
    end
end
-- урон гейммод обрабатывает своим хуком (EntityTakeDamage у него часто "съедается" раньше нас)
hook.Add("HomigradDamage", "ZSCAV_FuryAttacker", function(ply, dmg)
    Remember(ply, dmg)
end)
hook.Add("EntityTakeDamage", "ZSCAV_FuryAttacker", function(target, dmg)
    Remember(target:IsPlayer() and target or OwnerPlayer(target), dmg)
end)

-- кто нанёс больше всего вреда (система вины гейммода)
local function BiggestHarm(victim)
    local t = zb and zb.HarmDone and zb.HarmDone[victim]
    if not istable(t) then return end
    local best, bestHarm
    for att, harm in pairs(t) do
        if IsValid(att) and att:IsPlayer() and att ~= victim and (not bestHarm or harm > bestHarm) then
            best, bestHarm = att, harm
        end
    end
    return best
end

hook.Add("PlayerDeath", "ZSCAV_FuryDefeat", function(victim, inflictor, attacker)
    victim:SetNWBool("zscav_fury", false)
    local wasFury = (victim.zscavFuryUntil or 0) >= CurTime()
    victim.zscavFuryUntil = 0
    if not wasFury then return end

    local killer = OwnerPlayer(attacker) or OwnerPlayer(inflictor)
    if not IsValid(killer) or killer == victim then
        if IsValid(victim.zscavFuryAttacker) and CurTime() - (victim.zscavFuryAttackerT or 0) <= ATTACKER_TIME then
            killer = victim.zscavFuryAttacker
        end
    end
    victim.zscavFuryAttacker = nil
    if not IsValid(killer) or not killer:IsPlayer() or killer == victim then
        killer = BiggestHarm(victim)
    end
    if not IsValid(killer) or not killer:IsPlayer() or killer == victim then
        if GetConVar("developer"):GetInt() > 0 then print("[Z-SCAV fury] killer not found for", victim) end
        return
    end
    if GetConVar("developer"):GetInt() > 0 then print("[Z-SCAV fury] defeat music ->", killer) end

    net.Start("zscav_fury_defeat")
        net.WriteEntity(victim)
    net.Send(killer)
end)
