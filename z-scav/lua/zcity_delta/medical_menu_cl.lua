if SERVER then return end

local function GetMedicalTarget()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end

    local tr = hg and hg.eyeTrace and hg.eyeTrace(ply) or nil
    local ent = tr and tr.Entity or nil

    if IsValid(ent) then
        if ent:IsRagdoll() and hg and hg.RagdollOwner then
            ent = hg.RagdollOwner(ent) or ent
        end

        if IsValid(ent) and ent:IsPlayer() and ent.organism and ply:GetPos():DistToSqr(ent:GetPos()) <= 10000 then
            return ent
        end
    end

    return ply
end

local function GetDisplayName(ent)
    if not IsValid(ent) then return "UNKNOWN" end
    if isfunction(ent.GetPlayerName) then return ent:GetPlayerName() end
    if isfunction(ent.Nick) then return ent:Nick() end
    return tostring(ent)
end

local function RequestMedicalAmputation(ent, limb)
    if not IsValid(ent) then return end
    net.Start("hg_medical_minigame_request_amputation")
        net.WriteEntity(ent)
        net.WriteString(limb)
    net.SendToServer()
end

-- Z-SCAV: пункты аддона в Q-меню убраны (всё это есть в меню здоровья на N)
local _ZSCAV_offRadialMedical = (function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or not ply.organism or ply.organism.otrub then return end
    if not hg or not hg.radialOptions then return end

    local target = GetMedicalTarget() or ply
    local tname = GetDisplayName(target)
    local suffix = (target ~= ply) and (": " .. tname) or ""
    local options = {
        {
            [1] = function()
                RequestMedicalAmputation(target, "larm")
            end,
            [2] = (target ~= ply) and ("Amputate " .. tname .. ": Левая рука") or "Ампутировать левую руку"
        },
        {
            [1] = function()
                RequestMedicalAmputation(target, "rarm")
            end,
            [2] = (target ~= ply) and ("Amputate " .. tname .. ": Правая рука") or "Ампутировать правую руку"
        },
        {
            [1] = function()
                RequestMedicalAmputation(target, "lleg")
            end,
            [2] = (target ~= ply) and ("Amputate " .. tname .. ": Левая нога") or "Ампутировать левую ногу"
        },
        {
            [1] = function()
                RequestMedicalAmputation(target, "rleg")
            end,
            [2] = (target ~= ply) and ("Amputate " .. tname .. ": Правая нога") or "Ампутировать правую ногу"
        }
    }

    hg.radialOptions[#hg.radialOptions + 1] = {
        [1] = function()
            RunConsoleCommand("hg_unitmenu", tostring(target:EntIndex()))
            return -1
        end,
        [2] = "Меню юнита" .. suffix
    }

    hg.radialOptions[#hg.radialOptions + 1] = {
        [1] = function()
            if hg and hg.CreateRadialMenu then
                hg.CreateRadialMenu(options)
                return -1
            end
        end,
        [2] = "Medical" .. suffix
    }
end)
