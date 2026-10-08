--[[
    Z-SCAV: грязь.
    org.remDirt 0..100.
      * лежишь/ползаешь рэгдоллом по траве, земле, песку, грязи, листве - пачкаешься
        (быстрее, если тело движется)
      * в воде отмываешься (по пояс и глубже - быстро, просто стоишь в воде - медленнее)
    Грязь повышает шанс инфекции ран (sv_rem_skin.lua) - до x3 при полной грязи,
    и немного портит настроение.
    Выключить: zscav_dirt 0
]]

local cv = CreateConVar("zscav_dirt", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: грязь", 0, 1)

hg.organism.dirtCfg = hg.organism.dirtCfg or {}
local CFG = hg.organism.dirtCfg
CFG.INTERVAL    = 0.25
CFG.GAIN_LIE    = 1.5    -- в секунду, если всё тело лежит на грязи (~1 минута до полной грязи)
CFG.GAIN_MOVE   = 6      -- в секунду, если ползёшь всем телом по грязи (~17 секунд)
CFG.MOVE_SPEED  = 40     -- юнитов/с - считается "ползёт"
CFG.WASH_DEEP   = 8      -- в секунду в воде по пояс и глубже
CFG.WASH_FEET   = 1.5    -- в секунду, если в воде только ноги
CFG.INFECT_MAX  = 3      -- множитель шанса инфекции при грязи 100
CFG.MOOD        = 0.0005 -- удар по настроению в секунду при грязи 100

local DIRTY = {}
for _, m in ipairs({MAT_GRASS, MAT_DIRT, MAT_SAND, MAT_FOLIAGE, MAT_SLOSH, MAT_SNOW}) do
    if m then DIRTY[m] = true end
end

local down = Vector(0, 0, -1)

local function InWater(pos)
    return bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0
end

local function Tick()
    if not cv:GetBool() then return end
    local dt = CFG.INTERVAL
    for _, ply in ipairs(player.GetAll()) do
        local org = ply.organism
        if not org or not org.alive or not ply:Alive() then continue end
        org.remDirt = org.remDirt or 0
        local before = org.remDirt

        local rag = ply.FakeRagdoll
        local wet = 0
        if IsValid(rag) then
            -- рэгдолл: каждая часть тела, лежащая на грязи, пачкается
            local add = 0
            for i = 0, rag:GetPhysicsObjectCount() - 1 do
                local phys = rag:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    local pos = phys:GetPos()
                    if InWater(pos) then
                        wet = wet + 1
                    else
                        local tr = util.TraceLine({start = pos, endpos = pos + down * 10, filter = {rag, ply}, mask = MASK_SOLID})
                        if tr.Hit and DIRTY[tr.MatType] then
                            local moving = phys:GetVelocity():Length() > CFG.MOVE_SPEED
                            add = add + (moving and CFG.GAIN_MOVE or CFG.GAIN_LIE)
                        end
                    end
                end
            end
            org.remDirt = org.remDirt + add / math.max(rag:GetPhysicsObjectCount(), 1) * dt
            if wet > 0 then
                local frac = wet / math.max(rag:GetPhysicsObjectCount(), 1)
                org.remDirt = org.remDirt - (frac > 0.4 and CFG.WASH_DEEP or CFG.WASH_FEET) * dt
            end
        else
            -- стоя: моемся, если стоим в воде
            local wl = ply:WaterLevel()
            if wl >= 2 then org.remDirt = org.remDirt - CFG.WASH_DEEP * dt
            elseif wl == 1 then org.remDirt = org.remDirt - CFG.WASH_FEET * dt end
        end
        org.remDirt = math.Clamp(org.remDirt, 0, 100)

        -- мысли на порогах
        if before < 50 and org.remDirt >= 50 then
            ply:Notify("I'm covered in dirt.. I should wash up.", 4, "zscav_dirt", 0)
        elseif before > 5 and org.remDirt <= 5 and before - org.remDirt > 0 then
            ply:Notify("Much better. I'm clean.", 3, "zscav_dirt_clean", 0)
        end

        -- грязь немного портит настроение
        if org.remDirt > 30 and org.happiness and not org.moodLockUntil then
            org.happiness = math.max(0, org.happiness - CFG.MOOD * (org.remDirt / 100) * dt)
        end
    end
end
timer.Create("ZSCAV_Dirt", CFG.INTERVAL, 0, Tick)

-- множитель шанса инфекции (читает модуль кожи)
function hg.organism.DirtInfectMul(org)
    local d = org and org.remDirt or 0
    return 1 + (CFG.INFECT_MAX - 1) * math.Clamp(d / 100, 0, 1)
end

hook.Add("Org Clear", "ZSCAV_Dirt", function(org) org.remDirt = 0 end)
