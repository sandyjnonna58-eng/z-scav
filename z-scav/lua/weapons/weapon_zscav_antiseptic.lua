--[[
    Z-SCAV: антисептик. Убирает инфекцию с части тела и обеззараживает её.
    Применяется через меню здоровья (N): выбрать "АНТИСЕПТИК" и нажать на часть тела.
      * инфекция на части -60%
      * часть обеззаражена на 3 минуты (инфекция там почти не растёт, sv_rem_immunity.lua)
      * щиплет: немного боли
    Во флаконе 5 применений. Если медицина через меню выключена (hg_med_menu_only 0) -
    ЛКМ обрабатывает самую заражённую часть.
]]

SWEP.PrintName    = "Антисептик"
SWEP.Author       = "Z-SCAV"
SWEP.Category     = "Z-SCAV"
SWEP.Spawnable    = true
SWEP.Slot         = 4
SWEP.SlotPos      = 7
SWEP.DrawAmmo     = false
SWEP.DrawCrosshair = false
SWEP.ViewModel    = "models/weapons/c_arms.mdl"
SWEP.UseHands     = true
SWEP.WorldModel   = "models/props_junk/garbage_plasticbottle003a.mdl"
SWEP.HoldType     = "slam"

SWEP.Primary.ClipSize, SWEP.Primary.DefaultClip, SWEP.Primary.Automatic, SWEP.Primary.Ammo = -1, -1, false, "none"
SWEP.Secondary.ClipSize, SWEP.Secondary.DefaultClip, SWEP.Secondary.Automatic, SWEP.Secondary.Ammo = -1, -1, false, "none"

local USES, CLEAN, DISINFECT_TIME, STING = 5, 60, 180, 5

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self.Uses = USES
end

if SERVER then
    -- обработать часть тела part (id из hg.RemParts) у игрока ply
    function hg.ZSCAVAntiseptic(ply, part, wep)
        local org = IsValid(ply) and ply.organism
        if not org or not org.alive or not part then return false end
        if org.remInfect and org.remInfect[part] then
            org.remInfect[part] = math.max(0, org.remInfect[part] - CLEAN)
        end
        org.remDisinfect = org.remDisinfect or {}
        org.remDisinfect[part] = math.max(org.remDisinfect[part] or 0, CurTime() + DISINFECT_TIME)
        org.painadd = (org.painadd or 0) + STING
        ply:EmitSound("ambient/water/water_spray1.wav", 55, math.random(120, 135), 0.5)
        local name = hg.RemParts and hg.RemParts[part] and hg.RemParts[part].name or part
        ply:Notify("Антисептик: " .. name .. ". Щиплет...", 3, "zscav_antiseptic", 0)
        if IsValid(wep) then
            wep.Uses = (wep.Uses or USES) - 1
            if wep.Uses <= 0 then
                ply:SelectWeapon("weapon_hands_sh")
                wep:Remove()
            end
        end
        return true
    end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    local menuOnly = GetConVar("hg_med_menu_only")
    if menuOnly and menuOnly:GetBool() then
        ply:Notify("Антисептик применяй через меню здоровья (N).", 4, "rem_med_hint", 0)
        return
    end
    -- без меню: самая заражённая часть
    local org = ply.organism
    local best, bestV = "chest", -1
    for p, v in pairs(org and org.remInfect or {}) do
        if v > bestV then best, bestV = p, v end
    end
    hg.ZSCAVAntiseptic(ply, best, self)
end

function SWEP:SecondaryAttack() end

if CLIENT then
    function SWEP:DrawHUD()
        draw.SimpleTextOutlined("Меню здоровья (N) -> АНТИСЕПТИК -> часть тела", "DermaDefault", ScrW() * 0.5, ScrH() * 0.8, Color(220, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end
