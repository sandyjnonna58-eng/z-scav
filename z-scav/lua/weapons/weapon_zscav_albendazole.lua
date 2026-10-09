--[[
    Z-SCAV: Альбендазол. Противопаразитарное. Курс из 2 приёмов (не чаще раза в 30 с) лечит нейроцистицеркоз.
    ЛКМ - принять таблетку. Применений: 2.
]]

SWEP.PrintName    = "Альбендазол"
SWEP.Author       = "Z-SCAV"
SWEP.Instructions = "Противопаразитарное. Курс из 2 приёмов (не чаще раза в 30 с) лечит нейроцистицеркоз."
SWEP.Category     = "Z-SCAV"
SWEP.Spawnable    = true
SWEP.Slot         = 4
SWEP.SlotPos      = 7
SWEP.DrawAmmo     = false
SWEP.DrawCrosshair = false
SWEP.ViewModel    = "models/weapons/c_arms.mdl"
SWEP.UseHands     = true
SWEP.WorldModel   = "models/props_lab/jar01b.mdl"
SWEP.HoldType     = "slam"

SWEP.Primary.ClipSize, SWEP.Primary.DefaultClip, SWEP.Primary.Automatic, SWEP.Primary.Ammo = -1, -1, false, "none"
SWEP.Secondary.ClipSize, SWEP.Secondary.DefaultClip, SWEP.Secondary.Automatic, SWEP.Secondary.Ammo = -1, -1, false, "none"

local USES = 2

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self.Uses = USES
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 2)
    if CLIENT then return end
    local ply = self:GetOwner()
    local org = IsValid(ply) and ply.organism
    if not org or not org.alive then return end
    ply:EmitSound("snd_jack_hmcd_pillsuse.wav", 60, math.random(95, 105))
    if not (hg.organism.DiseaseMedicine and hg.organism.DiseaseMedicine(ply, org, "albendazole")) then ply:Notify("Ничего не изменилось.", 3, "zscav_med", 0) end
    self.Uses = (self.Uses or USES) - 1
    if self.Uses <= 0 then
        ply:SelectWeapon("weapon_hands_sh")
        self:Remove()
    end
end

function SWEP:SecondaryAttack() end

if CLIENT then
    function SWEP:DrawHUD()
        draw.SimpleTextOutlined("ЛКМ - принять таблетку (Альбендазол)", "DermaDefault", ScrW() * 0.5, ScrH() * 0.8, Color(220, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end
