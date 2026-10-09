--[[
    Z-SCAV: душ. Е - включить/выключить (сам выключается через 40 секунд).
    Под струёй:
      * быстро смывается грязь (sv_rem_dirt.lua) - меньше шанс инфекции
      * немного поднимается настроение (чистым быть приятно)
    Спавнится в Q-меню: Entities -> Z-SCAV -> Душ.
]]
AddCSLuaFile()

ENT.Type      = "anim"
ENT.Base      = "base_anim"
ENT.PrintName = "Душ"
ENT.Author    = "Z-SCAV"
ENT.Category  = "Z-SCAV"
ENT.Spawnable = true
ENT.AdminOnly = false

local MODELS = {"models/props_wasteland/shower_system001a.mdl", "models/props_c17/gaspipes006a.mdl", "models/props_junk/PopCan01a.mdl"}
local RUN_TIME  = 40     -- сек работы после включения
local RADIUS    = 56     -- ширина струи (по горизонтали)
local HEIGHT    = 170    -- на сколько ниже лейки достаёт вода
local WASH      = 18     -- грязи в секунду под душем
local MOOD      = 0.08   -- постоянного настроения в секунду (до +MOOD_MAX за раз)
local MOOD_MAX  = 6

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "On")
    self:NetworkVar("Float", 0, "OffAt")
end

-- точка, откуда льётся вода: верх модели
function ENT:HeadPos()
    local mins, maxs = self:OBBMins(), self:OBBMaxs()
    return self:LocalToWorld(Vector((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, maxs.z - 4))
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, cls)
        if not tr.Hit then return end
        local ent = ents.Create(cls)
        ent:SetPos(tr.HitPos + tr.HitNormal * 2)
        local ang = ply:EyeAngles()
        ent:SetAngles(Angle(0, ang.y + 180, 0))
        ent:Spawn()
        ent:Activate()
        return ent
    end

    function ENT:Initialize()
        local mdl = MODELS[#MODELS]
        for _, m in ipairs(MODELS) do
            if util.IsValidModel(m) then mdl = m break end
        end
        self:SetModel(mdl)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end -- душ стоит на месте (физганом можно двигать)
        self:SetOn(false)
    end

    function ENT:TurnOn()
        self:SetOn(true)
        self:SetOffAt(CurTime() + RUN_TIME)
        if not self.Snd then self.Snd = CreateSound(self, "ambient/water/water_flow_loop1.wav") end
        self.Snd:PlayEx(0.6, 100)
        self:EmitSound("buttons/lever7.wav", 60)
        self.MoodGiven = {}
    end

    function ENT:TurnOff()
        self:SetOn(false)
        if self.Snd then self.Snd:FadeOut(0.6) end
        self:EmitSound("buttons/lever8.wav", 60)
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        if (self.NextToggle or 0) > CurTime() then return end
        self.NextToggle = CurTime() + 0.6
        if self:GetOn() then self:TurnOff() else self:TurnOn() end
    end

    local function UnderShower(head, pos)
        local d = pos - head
        if d.z > 10 or d.z < -HEIGHT then return false end
        return (d.x * d.x + d.y * d.y) <= RADIUS * RADIUS
    end

    function ENT:Think()
        if self:GetOn() then
            if CurTime() >= self:GetOffAt() then
                self:TurnOff()
            else
                local head = self:HeadPos()
                local dt = 0.25
                for _, ply in ipairs(player.GetAll()) do
                    if not ply:Alive() then continue end
                    local org = ply.organism
                    if not org then continue end
                    local body = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll:WorldSpaceCenter() or ply:WorldSpaceCenter()
                    if not UnderShower(head, body) then continue end
                    org.remDirt = math.max(0, (org.remDirt or 0) - WASH * dt)
                    local given = self.MoodGiven[ply] or 0
                    if given < MOOD_MAX and hg.organism.AddMoodPermanent then
                        hg.organism.AddMoodPermanent(org, MOOD * dt * 4)
                        self.MoodGiven[ply] = given + MOOD * dt * 4
                    end
                    if (ply.zscavShowerMsg or 0) < CurTime() then
                        ply.zscavShowerMsg = CurTime() + 60
                        ply:Notify("Тёплая вода.. как же хорошо.", 4, "zscav_shower", 0)
                    end
                end
            end
        end
        self:NextThink(CurTime() + 0.25)
        return true
    end

    function ENT:OnRemove()
        if self.Snd then self.Snd:Stop() end
    end
else
    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:Think()
        if not self:GetOn() then return end
        if (self.NextDrop or 0) > CurTime() then return end
        self.NextDrop = CurTime() + 0.03
        if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 1500 * 1500 then return end
        self.Emitter = self.Emitter or ParticleEmitter(self:GetPos())
        if not self.Emitter then return end
        local head = self:HeadPos()
        for _ = 1, 4 do
            local p = self.Emitter:Add("effects/splash2", head + VectorRand(-6, 6) * Vector(1, 1, 0))
            if p then
                p:SetVelocity(Vector(math.Rand(-25, 25), math.Rand(-25, 25), -math.Rand(220, 320)))
                p:SetGravity(Vector(0, 0, -400))
                p:SetDieTime(0.6)
                p:SetStartAlpha(140)
                p:SetEndAlpha(0)
                p:SetStartSize(1.5)
                p:SetEndSize(3)
                p:SetColor(200, 220, 255)
                p:SetCollide(true)
                p:SetBounce(0.1)
            end
        end
    end

    function ENT:OnRemove()
        if self.Emitter then self.Emitter:Finish() self.Emitter = nil end
    end
end
