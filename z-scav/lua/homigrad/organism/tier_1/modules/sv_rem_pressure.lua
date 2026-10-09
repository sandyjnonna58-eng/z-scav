--[[
    REM: давление влияет на тело.

    Низкое давление (гипотония, < ~60):
      * слабость - медленнее ходишь (movement/sh_inertia.lua, общий код)
      * при беге кружится голова; если не остановиться - на секунду темнеет в глазах (оглушение)
      * мысли "голова кружится"
    Высокое давление (гипертония, > ~115):
      * головная боль (боль медленно растёт)
      * очень высокое - иногда кровь из носа, звон в ушах
      * на экране пульсирует красная виньетка (cl_rem_pressure.lua)
]]

local Clamp, Remap, max = math.Clamp, math.Remap, math.max
hg.organism.pressureCfg = hg.organism.pressureCfg or {}
local CFG = hg.organism.pressureCfg

CFG.DIZZY_BP       = 58   -- ниже - при беге кружится голова
CFG.DIZZY_FAINT    = 1    -- накопленное головокружение, при котором темнеет в глазах
CFG.FAINT_TIME     = 2    -- сек оглушения
CFG.HEADACHE_FROM  = 0.35 -- org.hypertension, с которого болит голова
CFG.HEADACHE_PAIN  = 0.6  -- боли в секунду при hypertension = 1
CFG.NOSEBLEED_FROM = 0.8
CFG.THOUGHT_CD     = 45

local function Think(owner, org, timeValue)
    if not org.alive or org.otrub or not IsValid(owner) or not owner:IsPlayer() then return end
    local bp = org.bloodPressure or 90
    local now = CurTime()

    -- ГИПОТОНИЯ: голова кружится при беге
    local running = owner:KeyDown(IN_SPEED) and owner:GetVelocity():Length2DSqr() > 150 * 150
    if bp < CFG.DIZZY_BP and running then
        org.remDizzy = (org.remDizzy or 0) + timeValue * Clamp(Remap(bp, CFG.DIZZY_BP, 30, 0.25, 1), 0.25, 1)
    else
        org.remDizzy = max(0, (org.remDizzy or 0) - timeValue * 0.3)
    end
    if (org.remDizzy or 0) >= CFG.DIZZY_FAINT then
        org.remDizzy = 0
        if hg.LightStunPlayer then hg.LightStunPlayer(owner, CFG.FAINT_TIME) end
        owner:Notify("На секунду всё потемнело...", 5, "rem_bp_faint", 0)
    end
    if bp < CFG.DIZZY_BP + 5 and now >= (org.remBPThought or 0) then
        org.remBPThought = now + CFG.THOUGHT_CD + math.Rand(0, 30)
        local t = {"Голова лёгкая, кружится..", "Ноги слабеют.", "Мир немного кружится.."}
        owner:Notify(t[math.random(#t)], 5, "rem_bp_low", 0)
    end

    -- ГИПЕРТОНИЯ: головная боль, кровь из носа
    local hyp = org.hypertension or 0
    if hyp > CFG.HEADACHE_FROM then
        org.painadd = (org.painadd or 0) + timeValue * CFG.HEADACHE_PAIN * hyp
        if now >= (org.remBPThought or 0) then
            org.remBPThought = now + CFG.THOUGHT_CD + math.Rand(0, 30)
            local t = {"Голова раскалывается..", "Я слышу стук сердца в ушах.", "Давит за глазами."}
            owner:Notify(t[math.random(#t)], 5, "rem_bp_high", 0)
        end
    end
    if hyp > CFG.NOSEBLEED_FROM and now >= (org.remNosebleed or 0) then
        org.remNosebleed = now + math.Rand(60, 120)
        if hg.organism.AddWoundManual then
            hg.organism.AddWoundManual(owner, 2, vector_origin, angle_zero, "ValveBiped.Bip01_Head1", now)
        end
        owner:Notify("У меня кровь из носа.", 5, "rem_bp_nose", 0)
    end
end

hook.Add("Org Think", "REM_Pressure", Think)
hook.Add("Org Clear", "REM_Pressure", function(org)
    org.remDizzy, org.remBPThought, org.remNosebleed = 0, 0, 0
end)
