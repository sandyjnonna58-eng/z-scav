--[[
    Z-SCAV: "Is this the end".
    Играет, пока игрок в крайне тяжёлом физическом состоянии:
      * обескровливание (мало крови, или сильно кровит при уже заметной потере)
      * сильный голод
      * фибрилляция / сильная аритмия
      * переохлаждение или перегрев
      * сильное отравление угарным газом
      * тяжёлая травма мозга
      * пневмоторакс вместе с нехваткой кислорода
    Выключается через несколько секунд после того, как все условия ушли.
    Это самый "главный" трек состояния: Drowning, Despair и усталость под ним приглушаются.
    Не играет во время таймера умирания и после смерти (там Dying / Death).
]]

local CFG = {
    path   = "sound/remorse/is_this_the_end.ogg",
    volume = 0.7,
    fade_in  = 5,
    fade_out = 4,
    hold     = 6,     -- сек после того, как состояние улучшилось

    blood        = 3000, -- мл крови меньше
    bleed_blood  = 3800, -- и при этом сильное кровотечение
    bleed        = 3,    -- org.bleed
    hungry       = 80,
    arrhythmia   = 0.7,
    temp_low     = 33.5,
    temp_high    = 40,
    co           = 0.5,
    brain        = 0.45,
    pneumo_o2    = 0.5,
}
hg.RemEndCfg = CFG

local function N(v, d) return isnumber(v) and v or d end

-- возвращает true + причину, если состояние критическое
local function Critical(org)
    local blood = N(org.blood, 5000)
    if blood < CFG.blood then return true, "blood" end
    if blood < CFG.bleed_blood and N(org.bleed, 0) >= CFG.bleed then return true, "bleed" end
    if N(org.hungry, 0) >= CFG.hungry then return true, "hunger" end
    if N(org.thirst, 0) >= 90 then return true, "thirst" end
    if N(org.remSepsis, 0) >= 0.6 then return true, "sepsis" end
    if org.fibrillation == true then return true, "fibrillation" end
    if N(org.arrhythmia, 0) >= CFG.arrhythmia then return true, "arrhythmia" end
    local t = N(org.temperature, 36.7)
    if t <= CFG.temp_low or t >= CFG.temp_high then return true, "temperature" end
    if N(org.CO, 0) >= CFG.co then return true, "co" end
    if N(org.brain, 0) >= CFG.brain then return true, "brain" end
    if N(org.pneumothorax, 0) > 0 and istable(org.o2) and N(org.o2[1], 30) / math.max(N(org.o2.range, 30), 1) < CFG.pneumo_o2 then
        return true, "pneumothorax"
    end
    return false
end
hg.RemIsCriticalState = Critical

local station, loading, vol, lastCrit = nil, false, 0, -999

local function Ensure()
    if IsValid(station) or loading or not file.Exists(CFG.path, "GAME") then return end
    loading = true
    sound.PlayFile(CFG.path, "noplay", function(st)
        loading = false
        if not IsValid(st) then return end
        station = st
        st:EnableLooping(true)
        st:SetVolume(0)
        st:Play()
    end)
end

hook.Add("Think", "ZSCAV_IsThisTheEnd", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism
    local now = RealTime()

    local blocked = not ply:Alive() or not org or (org.deathStateEnd and org.deathStateEnd > 0)
    if not blocked and Critical(org) then lastCrit = now end
    local active = not blocked and (now - lastCrit) < CFG.hold
    hg.RemEndActive = active

    local target = active and CFG.volume * (hg.RemLastStandActive and 0.15 or 1) or 0 -- под последним рубежом тише
    local speed = FrameTime() * CFG.volume / (active and CFG.fade_in or CFG.fade_out)
    if blocked then speed = speed * 4 end
    vol = math.Approach(vol, target, speed)

    if vol > 0.001 then
        Ensure()
        if IsValid(station) then station:SetVolume(vol) end
    elseif IsValid(station) then
        station:Stop()
        station = nil
    end
end)
