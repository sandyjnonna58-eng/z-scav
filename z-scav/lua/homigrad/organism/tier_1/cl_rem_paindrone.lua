--[[
    Z-SCAV: музыка боли.
    Гул боли играет по кругу и становится громче вместе с болью:
      боль ниже PAIN_MIN - тишина, от PAIN_MIN до PAIN_MAX - громкость растёт.
    Обезболивающие уменьшают боль - гул сам стихает.
    Под "Is this the end" и Drowning приглушается, при умирании и смерти - затихает.
]]

local CFG = {
    path     = "sound/remorse/pain_drone.ogg",
    PAIN_MIN = 15,    -- с какой боли слышно
    PAIN_MAX = 110,   -- при какой боли громче всего
    vol_min  = 0.08,
    vol_max  = 0.75,
    curve    = 1.3,   -- >1: тихо при лёгкой боли, резко громче при сильной
    smooth   = 1.5,   -- сек: как плавно громкость следует за болью
}
hg.RemPainDroneCfg = CFG

local station, loading, vol = nil, false, 0

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

hook.Add("Think", "ZSCAV_PainDrone", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism
    local pain = org and isnumber(org.pain) and org.pain or 0

    local blocked = not ply:Alive() or not org or (org.deathStateEnd and org.deathStateEnd > 0)

    local target = 0
    if not blocked and pain >= CFG.PAIN_MIN then
        local f = math.Clamp((pain - CFG.PAIN_MIN) / (CFG.PAIN_MAX - CFG.PAIN_MIN), 0, 1) ^ CFG.curve
        target = Lerp(f, CFG.vol_min, CFG.vol_max)
        if hg.RemEndActive or hg.RemDrowningActive then target = target * 0.5 end
        if hg.RemLastStandActive then target = target * 0.15 end
    end

    local speed = FrameTime() * CFG.vol_max / (blocked and 0.4 or CFG.smooth)
    vol = math.Approach(vol, target, speed)

    if vol > 0.001 then
        Ensure()
        if IsValid(station) then station:SetVolume(vol) end
    elseif IsValid(station) then
        station:Stop()
        station = nil
    end
end)
