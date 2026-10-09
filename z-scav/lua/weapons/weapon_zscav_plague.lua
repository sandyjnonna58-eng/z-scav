--[[
    Z-SCAV: способности Чумного доктора (выдаётся командой zscav_plague_doctor).
    ЛКМ - заразить того, кто перед тобой (вплотную), выбранной болезнью.
    R   - выбрать болезнь (по кругу, "случайная" - любая).
    ПКМ - оторвать конечность, в которую целишься (или любую оставшуюся).
    Быстрый бег - пока способность выдана (sh_inertia.lua).
]]
if SERVER then AddCSLuaFile() end

SWEP.PrintName    = "Чумной доктор"
SWEP.Author       = "Z-SCAV"
SWEP.Instructions = "ЛКМ - заразить, R - выбрать болезнь, ПКМ - оторвать конечность."
SWEP.Category     = "Z-SCAV"
SWEP.Spawnable    = false
SWEP.AdminOnly    = true
SWEP.Slot         = 0
SWEP.SlotPos      = 9
SWEP.DrawAmmo     = false
SWEP.DrawCrosshair = true
SWEP.ViewModel    = "models/weapons/c_arms.mdl"
SWEP.UseHands     = true
SWEP.WorldModel   = ""
SWEP.HoldType     = "fist"

SWEP.Primary.ClipSize, SWEP.Primary.DefaultClip, SWEP.Primary.Automatic, SWEP.Primary.Ammo = -1, -1, false, "none"
SWEP.Secondary.ClipSize, SWEP.Secondary.DefaultClip, SWEP.Secondary.Automatic, SWEP.Secondary.Ammo = -1, -1, false, "none"

local REACH = 90
local INFECT_CD, RIP_CD = 3, 5

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then self:SetNWString("zscav_dis", "random") end
end

function SWEP:DrawWorldModel() end

local function Choices()
    local t = {"random"}
    for _, id in ipairs(ZSCAV_DISEASE_ORDER or {}) do t[#t + 1] = id end
    return t
end

-- кто перед нами: игрок (или владелец рэгдолла), часть тела
local function TraceTarget(ply)
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * REACH,
        filter = {ply, ply.FakeRagdoll},
        mask = MASK_SHOT,
    })
    local ent = tr.Entity
    if not IsValid(ent) then return end
    local target = ent
    if not ent:IsPlayer() then
        target = (hg.RagdollOwner and hg.RagdollOwner(ent)) or ent:GetNWEntity("ply")
    end
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or not target.organism then return end

    -- какая конечность
    local limb
    local hg_ = tr.HitGroup
    if hg_ == HITGROUP_LEFTARM then limb = "larm"
    elseif hg_ == HITGROUP_RIGHTARM then limb = "rarm"
    elseif hg_ == HITGROUP_LEFTLEG then limb = "lleg"
    elseif hg_ == HITGROUP_RIGHTLEG then limb = "rleg" end
    if not limb and tr.PhysicsBone and ent:IsRagdoll() then
        local bone = ent:TranslatePhysBoneToBone(tr.PhysicsBone)
        local name = bone and ent:GetBoneName(bone) or ""
        local side = string.find(name, "_L_", 1, true) and "l" or (string.find(name, "_R_", 1, true) and "r")
        if side then
            if string.find(name, "Arm", 1, true) or string.find(name, "Hand", 1, true) or string.find(name, "Clavicle", 1, true) then limb = side .. "arm"
            elseif string.find(name, "Thigh", 1, true) or string.find(name, "Calf", 1, true) or string.find(name, "Foot", 1, true) or string.find(name, "Toe", 1, true) then limb = side .. "leg" end
        end
    end
    return target, limb, tr
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:GetNWBool("zscav_plague") then return end
    if (self.nextInfect or 0) > CurTime() then return end
    local target = TraceTarget(ply)
    if not target or target == ply then return end
    self.nextInfect = CurTime() + INFECT_CD

    local org = target.organism
    local id = self:GetNWString("zscav_dis", "random")
    if id == "random" or not (ZSCAV_DISEASES or {})[id] then
        local pool = {}
        for _, d in ipairs(ZSCAV_DISEASE_ORDER or {}) do
            if not (org.remDis and org.remDis[d]) then pool[#pool + 1] = d end
        end
        id = pool[math.random(math.max(#pool, 1))]
    end
    if not id or not hg.organism.GiveDisease then return end
    if org.remDis and org.remDis[id] then
        ply:Notify("Уже болен этим.", 2, "zscav_plague", 0)
        return
    end
    hg.organism.GiveDisease(org, id)
    target:EmitSound("ambient/voices/cough" .. math.random(1, 4) .. ".wav", 60, math.random(90, 110))
    ply:Notify(("Заражён: %s - %s"):format(target:Nick(), ZSCAV_DISEASES[id].name), 4, "zscav_plague", 0)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:GetNWBool("zscav_plague") then return end
    if (self.nextRip or 0) > CurTime() then return end
    local target, limb, tr = TraceTarget(ply)
    if not target or target == ply then return end
    local org = target.organism
    if not hg.organism.AmputateLimb then return end

    if not limb or org[limb .. "amputated"] then
        local left = {}
        for _, l in ipairs({"larm", "rarm", "lleg", "rleg"}) do
            if org[l .. "amputated"] == false then left[#left + 1] = l end
        end
        limb = left[math.random(math.max(#left, 1))]
    end
    if not limb or org[limb .. "amputated"] ~= false then
        ply:Notify("Отрывать больше нечего.", 2, "zscav_plague", 0)
        return
    end
    self.nextRip = CurTime() + RIP_CD
    hg.organism.AmputateLimb(org, limb)
    org.painadd = (org.painadd or 0) + 60
    org.shock = (org.shock or 0) + 20
    local ent = hg.GetCurrentCharacter and hg.GetCurrentCharacter(target) or target
    if IsValid(ent) then ent:EmitSound("physics/flesh/flesh_bloody_break.wav", 75, math.random(85, 105)) end
    if tr and tr.HitPos then
        local ed = EffectData() ed:SetOrigin(tr.HitPos) util.Effect("BloodImpact", ed)
    end
end

function SWEP:Reload()
    if CLIENT then return end
    if (self.nextCycle or 0) > CurTime() then return end
    self.nextCycle = CurTime() + 0.3
    local list = Choices()
    local cur = self:GetNWString("zscav_dis", "random")
    local idx = 1
    for i, v in ipairs(list) do if v == cur then idx = i end end
    local nxt = list[idx % #list + 1]
    self:SetNWString("zscav_dis", nxt)
    local ply = self:GetOwner()
    if IsValid(ply) then
        ply:Notify("Болезнь: " .. (nxt == "random" and "случайная" or ZSCAV_DISEASES[nxt].name), 2, "zscav_plague", 0)
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local id = self:GetNWString("zscav_dis", "random")
        local name = id == "random" and "случайная" or ((ZSCAV_DISEASES or {})[id] or {}).name or id
        draw.SimpleTextOutlined("ЧУМНОЙ ДОКТОР   болезнь: " .. name, "DermaDefaultBold", ScrW() * 0.5, ScrH() * 0.8, Color(170, 230, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined("ЛКМ - заразить   R - сменить болезнь   ПКМ - оторвать конечность", "DermaDefault", ScrW() * 0.5, ScrH() * 0.8 + 18, Color(220, 230, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end
