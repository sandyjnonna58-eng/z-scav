--[[
    REM: мини-игра сердечно-лёгочной реанимации (сервер).

    Как и раньше, СЛР начинается, когда руками (ЛКМ) давишь на грудь лежащего.
    Но компрессии больше не идут сами: их делает игрок ПРОБЕЛОМ в ритм ~110 в минуту,
    а после 30 компрессий - 2 вдоха (держать ПРОБЕЛ ~1 сек).
    Чем точнее ритм и глубина, тем сильнее эффект; слишком сильно - можно сломать рёбра.

    Выключить (вернуть автоматическую СЛР): hg_cpr_minigame 0
]]

hg.RemCPR = hg.RemCPR or {}
local CPR = hg.RemCPR

local cv = CreateConVar("hg_cpr_minigame", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "REM: мини-игра СЛР", 0, 1)

CPR.MIN_COMPRESS_GAP = 0.25   -- защита от спама
CPR.MIN_BREATH_GAP   = 0.6
CPR.RIB_CHANCE_HARD  = 12     -- 1 из N за "слишком сильную" компрессию
CPR.RIB_CHANCE_OK    = 80

util.AddNetworkString("rem_cpr_mg")       -- s->c: старт/стоп
util.AddNetworkString("rem_cpr_press")    -- c->s: компрессия/вдох
util.AddNetworkString("rem_cpr_fb")       -- s->c: состояние пациента

local function SendStart(ply, target, on)
    net.Start("rem_cpr_mg")
        net.WriteBool(on)
        net.WriteEntity(target or NULL)
    net.Send(ply)
end

local function SendFeedback(ply, org)
    net.Start("rem_cpr_fb")
        net.WriteBool(org.alive and true or false)
        net.WriteBool(org.heartstop and true or false)
        net.WriteUInt(math.Clamp(math.Round(org.o2 and org.o2[1] / math.max(org.o2.range or 30, 1) * 100 or 0), 0, 100), 7)
    net.Send(ply)
end

-- вызывается каждый тик из рук, пока игрок давит на грудь. true = автоматическую СЛР не делать
function CPR.Handle(wep, ply, target, org, phys)
    if not cv:GetBool() then return false end
    if not IsValid(ply) or not IsValid(target) or not org then return false end
    if target.noHead then return true end

    local st = ply.remCPR
    if not st or st.target ~= target then
        st = {target = target, org = org, start = CurTime(), lastC = 0, lastB = 0}
        ply.remCPR = st
        SendStart(ply, target, true)
        SendFeedback(ply, org)
    end
    st.seen = CurTime()
    st.phys = phys
    st.org = org
    return true
end

hook.Add("Think", "REM_CPR", function()
    for _, ply in ipairs(player.GetAll()) do
        local st = ply.remCPR
        if st and (CurTime() - (st.seen or 0) > 0.4 or not IsValid(st.target) or not ply:Alive()) then
            ply.remCPR = nil
            SendStart(ply, NULL, false)
        end
    end
end)

net.Receive("rem_cpr_press", function(_, ply)
    local kind = net.ReadUInt(2)      -- 0 компрессия, 1 вдох
    local q = math.Clamp(net.ReadFloat(), 0, 1)
    local hard = net.ReadBool()

    local st = ply.remCPR
    if not st or CurTime() - (st.seen or 0) > 0.4 then return end
    local org = st.org
    if not org or not org.alive then SendFeedback(ply, org or {}) return end

    local cprMul = ply.Profession == "doctor" and 2 or 1
    local now = CurTime()

    if kind == 0 then
        if now - st.lastC < CPR.MIN_COMPRESS_GAP then return end
        st.lastC = now

        local k = cprMul * q
        org.pulse = math.min((org.pulse or 0) + 7 * k, 75)
        org.bloodPressure = math.min((org.bloodPressure or 0) + 6 * k, 70)
        org.cardiacOutput = math.min((org.cardiacOutput or 0) + 0.08 * k, 0.6)
        org.myocardialOxygen = math.min((org.myocardialOxygen or 0) + 0.04 * k, 0.6)
        if org.CO then org.CO = math.Approach(org.CO, 0, cprMul * q) end
        if org.COregen then org.COregen = math.Approach(org.COregen, 0, cprMul * q) end

        -- рёбра
        local chance = hard and CPR.RIB_CHANCE_HARD or CPR.RIB_CHANCE_OK
        if ply.Profession ~= "doctor" and math.random(chance) == 1 and hg.organism.input_list and hg.organism.input_list.chest then
            local dmginfo = DamageInfo()
            dmginfo:SetDamageType(DMG_CRUSH)
            dmginfo:SetInflictor(IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon() or ply)
            hg.organism.input_list.chest(org, 1, 5, dmginfo)
            st.target:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav", 60, math.random(110, 125))
        end

        if hg.organism.TryRestartHeartWithCPR then
            hg.organism.TryRestartHeartWithCPR(org, math.max(cprMul * q, 0.25))
        elseif org.pulse > 15 then
            org.heartstop = false
        end

        if IsValid(st.phys) then st.phys:ApplyForceCenter(-vector_up * (4000 + 4000 * q)) end
        st.target:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 55, math.random(90, 110))
    elseif kind == 1 then
        if now - st.lastB < CPR.MIN_BREATH_GAP then return end
        st.lastB = now
        if org.o2 and hg.organism.OxygenateBlood then
            org.o2[1] = math.min(org.o2[1] + hg.organism.OxygenateBlood(org) * 2 * cprMul * q, org.o2.range)
        end
        if math.Rand(0, 1) < q * 0.6 then org.lungsfunction = true end
        st.target:EmitSound("player/breathe1.wav", 50, math.random(90, 105), 0.6)
    end

    SendFeedback(ply, org)
end)

hook.Add("PlayerDeath", "REM_CPR", function(ply) ply.remCPR = nil end)
