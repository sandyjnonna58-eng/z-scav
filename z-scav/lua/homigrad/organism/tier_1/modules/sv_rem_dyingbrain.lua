--[[
    Z-SCAV: пока идёт таймер умирания, мозг без кислорода постепенно погибает.
    Повреждение мозга растёт от BRAIN_START до BRAIN_END к моменту смерти.
    Если персонажа спасли (дефибриллятор, СЛР, последний рубеж) - уже полученное
    повреждение остаётся (последний рубеж сам урезает его до 10-25%).
    Выключить: zscav_dying_brain 0
]]

local cv = CreateConVar("zscav_dying_brain", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: мозг гибнет во время таймера умирания", 0, 1)

local BRAIN_START = 0.05
local BRAIN_END   = 0.84  -- чуть ниже порога смерти мозга (85%), чтобы убивал именно таймер
local CURVE       = 1.6   -- >1: сначала медленно, к концу быстрее (умирание длится 1 минуту)

hook.Add("Org Think", "ZSCAV_DyingBrain", function(owner, org, timeValue)
    if not cv:GetBool() or not org.alive or not IsValid(owner) or not owner:IsPlayer() then return end
    local dEnd = org.deathStateEnd
    if not dEnd or dEnd <= 0 then
        org.remDyingTotal = nil
        return
    end
    local left = math.max(dEnd - CurTime(), 0)
    -- полное время эпизода (дефибриллятор может его продлить)
    if not org.remDyingTotal or left > org.remDyingTotal then org.remDyingTotal = math.max(left, 1) end
    local progress = 1 - left / org.remDyingTotal
    local target = BRAIN_START + (BRAIN_END - BRAIN_START) * progress ^ CURVE
    if (org.brain or 0) < target then org.brain = target end
end)

hook.Add("Org Clear", "ZSCAV_DyingBrain", function(org) org.remDyingTotal = nil end)
