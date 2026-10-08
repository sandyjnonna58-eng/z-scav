--[[
    REM: ссадины от скольжения.

    Когда тело (рэгдолл) быстро скользит по земле, кожа стирается:
    каждая кость, которая трётся о поверхность на скорости, копит "стирание".
    Набралось - на этой части появляется кровоточащая ссадина + боль.
    Чем быстрее скольжение, тем быстрее стирается и тем сильнее кровит.
]]

hg.organism.abrasionCfg = hg.organism.abrasionCfg or {}
local CFG = hg.organism.abrasionCfg

CFG.INTERVAL   = 0.15   -- как часто проверять (сек)
CFG.SPEED      = 400    -- с какой скорости скольжения (юнитов/сек) стирается кожа (~27 км/ч; было 260)
CFG.CONTACT    = 9      -- насколько близко к поверхности должна быть кость
CFG.RATE       = 1 / 700 -- "стирание" в секунду за каждый юнит/с сверх SPEED (было 1/300 - стиралось легче)
CFG.BLOOD      = 2      -- кровь ссадины (как dmgBlood у раны) при минимальной скорости
CFG.BLOOD_MAX  = 7
CFG.SKIN_MUL   = 0.35   -- ссадина бьёт по коже слабее обычной раны
CFG.PAIN       = 6      -- боль за ссадину
CFG.MAX_PER_BONE = 2    -- больше ссадин на одной кости не делаем (дальше только боль)

-- мягкие поверхности: трава, земля, песок, снег, листва, вода - кожу не стирают
local SOFT = {}
for _, m in ipairs({MAT_GRASS, MAT_DIRT, MAT_SAND, MAT_SNOW, MAT_FOLIAGE, MAT_SLOSH, MAT_FLESH, MAT_ALIENFLESH, MAT_ANTLION, MAT_BLOODYFLESH}) do
    if m then SOFT[m] = true end
end

local down = Vector(0, 0, -1)

-- в транспорте кожа не стирается: любой транспорт GMod, Glide, сиденья
local function InVehicle(ply)
    if ply:InVehicle() then return true end
    if ply.GlideGetVehicle and IsValid(ply:GlideGetVehicle()) then return true end
    if ply.IsUsingGlideVehicle then return true end
    local veh = ply:GetVehicle()
    if IsValid(veh) then return true end
    return false
end

-- это "транспорт" или что-то едущее вместе с телом (тогда трения нет)
local function IsVehicleEnt(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() or ent.IsGlideVehicle then return true end
    local par = ent:GetParent()
    if IsValid(par) and (par:IsVehicle() or par.IsGlideVehicle) then return true end
    local cls = ent:GetClass()
    return string.find(cls, "vehicle", 1, true) ~= nil or string.find(cls, "glide", 1, true) ~= nil
end

local function Tick()
    for _, ply in ipairs(player.GetAll()) do
        local rag = ply.FakeRagdoll
        local org = ply.organism
        if not IsValid(rag) or not org or not org.alive or org.superfighter then continue end
        if InVehicle(ply) then continue end
        -- тело прицеплено к машине (сидит/привязано) - не скользит
        local rpar = rag:GetParent()
        if IsValid(rpar) and IsVehicleEnt(rpar) then continue end

        org.remAbrasion = org.remAbrasion or {}
        org.remAbrasionCount = org.remAbrasionCount or {}

        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)
            if not IsValid(phys) then continue end

            local vel = phys:GetVelocity()
            if vel.x * vel.x + vel.y * vel.y < CFG.SPEED * CFG.SPEED then continue end

            local pos = phys:GetPos()
            local tr = util.TraceLine({start = pos, endpos = pos + down * CFG.CONTACT, filter = {rag, ply}, mask = MASK_SOLID})
            if not tr.Hit or tr.HitNormal.z < 0.5 then continue end -- трётся о пол/землю
            if SOFT[tr.MatType] then continue end -- трава/земля/песок/снег - кожа цела
            -- лежит на машине/движущемся объекте - считаем скорость ОТНОСИТЕЛЬНО него
            if IsVehicleEnt(tr.Entity) then continue end
            if IsValid(tr.Entity) and not tr.Entity:IsWorld() then
                local sv = tr.Entity:GetVelocity()
                local op = tr.Entity:GetPhysicsObject()
                if IsValid(op) then sv = op:GetVelocity() end
                vel = vel - sv
            end
            local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
            if speed < CFG.SPEED then continue end

            local bone = rag:GetBoneName(rag:TranslatePhysBoneToBone(i))
            if not bone then continue end

            local acc = (org.remAbrasion[bone] or 0) + (speed - CFG.SPEED) * CFG.RATE * CFG.INTERVAL
            if acc >= 1 then
                acc = 0
                org.painadd = (org.painadd or 0) + CFG.PAIN
                local n = org.remAbrasionCount[bone] or 0
                if n < CFG.MAX_PER_BONE and hg.organism.AddWoundManual then
                    org.remAbrasionCount[bone] = n + 1
                    local blood = math.Clamp(CFG.BLOOD * speed / CFG.SPEED, CFG.BLOOD, CFG.BLOOD_MAX)
                    org.remSkinNextMul = CFG.SKIN_MUL -- модуль кожи посчитает эту рану как ссадину
                    hg.organism.AddWoundManual(ply, blood, vector_origin, angle_zero, bone, CurTime())
                end
                rag:EmitSound("physics/flesh/flesh_scrape_rough_loop.wav", 60, math.random(95, 110), 0.5)
                timer.Simple(0.35, function() if IsValid(rag) then rag:StopSound("physics/flesh/flesh_scrape_rough_loop.wav") end end)
            end
            org.remAbrasion[bone] = acc
        end
    end
end

timer.Create("REM_Abrasion", CFG.INTERVAL, 0, Tick)

hook.Add("Org Clear", "REM_Abrasion", function(org)
    org.remAbrasion = {}
    org.remAbrasionCount = {}
end)
