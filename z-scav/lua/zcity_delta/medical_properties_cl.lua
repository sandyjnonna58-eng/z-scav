if SERVER then return end
if not properties then return end

local function ResolveEntity(ent)
    if not IsValid(ent) then return nil end
    if ent:IsRagdoll() and hg and hg.RagdollOwner then
        ent = hg.RagdollOwner(ent) or ent
    end
    return ent
end

local function CanOpen(ent, ply)
    if not IsValid(ply) or not ply:Alive() then return false end
    ent = ResolveEntity(ent)
    if not IsValid(ent) then return false end
    if not ent:IsPlayer() then return false end
    if not ent.organism then return false end
    if ent ~= ply and ply:GetPos():DistToSqr(ent:GetPos()) > 10000 then return false end
    return true
end

local function SendRequest(ent, limb)
    ent = ResolveEntity(ent)
    if not IsValid(ent) then return end
    net.Start("hg_medical_minigame_request_amputation")
        net.WriteEntity(ent)
        net.WriteString(limb)
    net.SendToServer()
end

properties.Add("zcity_delta_medical", {
    MenuLabel = "Medical",
    Order = 14.5,
    MenuIcon = "icon16/heart.png",

    Filter = function(self, ent, ply)
        return CanOpen(ent, ply)
    end,

    MenuOpen = function(self, option, ent)
        local submenu = option:AddSubMenu()

        submenu:AddOption("Amputate Left Arm", function()
            SendRequest(ent, "larm")
        end)

        submenu:AddOption("Amputate Right Arm", function()
            SendRequest(ent, "rarm")
        end)

        submenu:AddOption("Amputate Left Leg", function()
            SendRequest(ent, "lleg")
        end)

        submenu:AddOption("Amputate Right Leg", function()
            SendRequest(ent, "rleg")
        end)
    end
})
