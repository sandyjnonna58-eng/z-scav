--[[
    Z-SCAV: открытые переломы (визуал взят из Medic's Gore Mod - только сломанные кости).

    Когда Homigrad ломает кость (рука, нога, рёбра), с шансом перелом становится открытым:
    обломок кости торчит из тела - видно на игроке, его рэгдолле и трупе.
      * больнее (+15 боли), кожа на этой части сильно повреждена - выше риск инфекции
      * когда перелом вылечен (кость снова целая) - кость пропадает
    zscav_open_fracture 0          - выключить
    zscav_open_fracture_chance 30  - шанс для руки/ноги, % (от тупых ударов и падений - в 0.6 раза меньше)
    zscav_open_fracture_ribs 15    - шанс для ребра, %
]]
local cv      = CreateConVar("zscav_open_fracture", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: открытые переломы", 0, 1)
local cvLimb  = CreateConVar("zscav_open_fracture_chance", "30", FCVAR_ARCHIVE, "Z-SCAV: шанс открытого перелома руки/ноги, %", 0, 100)
local cvRibs  = CreateConVar("zscav_open_fracture_ribs", "15", FCVAR_ARCHIVE, "Z-SCAV: шанс, что ребро проткнёт кожу, %", 0, 100)

local NW = "zscav_ofrac"
local SKIN_PART = {larm = "l_forearm", rarm = "r_forearm", lleg = "l_shin", rleg = "r_shin", rib1 = "chest", rib2 = "chest", rib3 = "chest"}
local THOUGHTS = {"Кость... торчит наружу!", "Я вижу собственную кость!", "Она прорвала кожу..."}

local function Encode(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

local function Sync(org)
    local owner = org.owner
    if not IsValid(owner) then return end
    local s = Encode(org.remOpenFrac)
    owner:SetNW2String(NW, s)
    if owner:IsPlayer() and IsValid(owner.FakeRagdoll) then owner.FakeRagdoll:SetNW2String(NW, s) end
end

function hg.ZSCAVOpenFracture(org, key, dmgInfo)
    if not cv:GetBool() or not istable(org) or not IsValid(org.owner) then return end
    org.remOpenFrac = org.remOpenFrac or {}
    local chance
    if key == "ribs" then
        chance = cvRibs:GetFloat()
        local slot
        for i = 1, 3 do if not org.remOpenFrac["rib" .. i] then slot = "rib" .. i break end end
        if not slot then return end
        key = slot
    else
        if org.remOpenFrac[key] or org[key .. "amputated"] then return end
        chance = cvLimb:GetFloat()
        if dmgInfo and dmgInfo.IsDamageType and dmgInfo:IsDamageType(DMG_CLUB + DMG_CRUSH + DMG_FALL) then chance = chance * 0.6 end
    end
    if math.Rand(0, 100) >= chance then return end

    org.remOpenFrac[key] = true
    org.painadd = (org.painadd or 0) + 15
    if hg.organism.DamageSkin and SKIN_PART[key] then hg.organism.DamageSkin(org, SKIN_PART[key], 45) end
    if org.isPly and IsValid(org.owner) and org.owner.Notify then
        org.owner:Notify(THOUGHTS[math.random(#THOUGHTS)], 4, "zscav_openfrac", 0)
    end
    Sync(org)
end

-- кость вылечили - обломок пропадает
hook.Add("Org Think", "ZSCAV_OpenFracture", function(owner, org)
    local of = org.remOpenFrac
    if not of or not next(of) then return end
    local now = CurTime()
    if (org.remOpenFracCheck or 0) > now then return end
    org.remOpenFracCheck = now + 1
    local changed = false
    for k in pairs(of) do
        if k:sub(1, 3) == "rib" then
            if (org.brokenribs or 0) < tonumber(k:sub(4)) and (org.chest or 0) < 0.3 then of[k] = nil changed = true end
        elseif (org[k] or 0) < 1 and not org[k .. "amputated"] then
            of[k] = nil changed = true
        end
    end
    if changed then Sync(org) end
end)

-- труп оставляет кости себе
hook.Add("PlayerDeath", "ZSCAV_OpenFracture", function(ply)
    local s = ply:GetNW2String(NW, "")
    if s == "" then return end
    timer.Simple(0.2, function()
        if not IsValid(ply) then return end
        local rag = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply:GetRagdollEntity()
        if IsValid(rag) then rag:SetNW2String(NW, s) end
    end)
end)

hook.Add("Org Clear", "ZSCAV_OpenFracture", function(org)
    org.remOpenFrac = {}
    if IsValid(org.owner) then org.owner:SetNW2String(NW, "") end
end)
