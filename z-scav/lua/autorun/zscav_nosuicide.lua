--[[
    Z-SCAV: у оружия нет режима "на себя" (топор, лом, томагавк, ножи, пистолеты и т.д.).
    Из-за него оружие вставало в странную позу и удары работали не как обычно.
    Флаг CanSuicide снимается со всего оружия, состояние сбрасывается у всех игроков.
]]
AddCSLuaFile()

local function StripAll()
    for _, w in ipairs(weapons.GetList()) do
        local st = w.ClassName and weapons.GetStored(w.ClassName)
        if st and st.CanSuicide then st.CanSuicide = false end
    end
end
hook.Add("InitPostEntity", "ZSCAV_NoSuicideMode", StripAll)
timer.Simple(0, StripAll)

hook.Add("OnEntityCreated", "ZSCAV_NoSuicideMode", function(ent)
    if ent:IsWeapon() then
        timer.Simple(0, function() if IsValid(ent) and ent.CanSuicide then ent.CanSuicide = false end end)
    end
end)

if SERVER then
    timer.Create("ZSCAV_NoSuicideMode", 0.5, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            if ply.suiciding then ply.suiciding = false end
            if ply:GetNWBool("suiciding", false) then ply:SetNWBool("suiciding", false) end
            if ply:GetNWFloat("willsuicide", 0) ~= 0 then ply:SetNWFloat("willsuicide", 0) end
        end
    end)
else
    hook.Add("Think", "ZSCAV_NoSuicideMode", function()
        local ply = LocalPlayer()
        if IsValid(ply) and ply.suiciding then ply.suiciding = false end
    end)
end
