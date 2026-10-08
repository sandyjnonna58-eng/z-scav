--[[
    Z-SCAV: основной звук сердцебиения.

    Своё сердце слышно ТОЛЬКО пока открыто меню здоровья (SCAV-HEALTH).
    Играет петля sound/remorse/heart/heartbeat_main.ogg (записана примерно на BASE_BPM ударов/мин),
    в критическом состоянии или без сознания плавно сменяется на heartbeat_critical.ogg,
    скорость петли подстраивается под настоящий пульс (org.heartbeat):
      * спокойный пульс - медленнее и тише
      * высокий пульс / критическое состояние - быстрее и громче
      * аритмия - ритм "плавает"
      * остановка сердца - тишина
    Отдельные удары beat_normal.ogg остаются только для проверки пульса у других игроков.
]]

local CFG = {
    loop      = "sound/remorse/heart/heartbeat_main.ogg",     -- обычное сердце
    loop_crit = "sound/remorse/heart/heartbeat_critical.ogg", -- критическое состояние / без сознания
    BASE_BPM  = 109,   -- темп обеих записей (одинаковый, поэтому переход бесшовный)
    rate_min  = 0.6,
    rate_max  = 1.8,
    vol_normal   = 0.45,
    vol_critical = 0.85,
    fade_in   = 0.4,
    fade_out  = 0.3,
    crossfade = 1.2,   -- сек на переход обычное <-> критическое
    -- когда состояние считается критическим
    blood      = 3500,
    arrhythmia = 0.5,
    pressure   = 45,
}
hg.RemHeartSoundCfg = CFG

local function N(v, d) return isnumber(v) and v or d end

local function IsCritical(org)
    if org.otrub then return true end -- без сознания - "приглушённое" критическое сердце
    if N(org.blood, 5000) < CFG.blood then return true end
    if org.fibrillation == true then return true end
    if N(org.arrhythmia, 0) >= CFG.arrhythmia then return true end
    if N(org.bloodPressure, 90) < CFG.pressure then return true end
    return false
end

-- две петли играют одновременно и синхронно, между ними - перекрёстное затухание
local chans = {
    main = {path = CFG.loop},
    crit = {path = CFG.loop_crit},
}
local vol, mix, rate = 0, 0, 1 -- mix: 0 = обычное, 1 = критическое

local function Ensure(ch)
    if IsValid(ch.st) or ch.loading or not file.Exists(ch.path, "GAME") then return end
    ch.loading = true
    sound.PlayFile(ch.path, "noplay", function(st)
        ch.loading = false
        if not IsValid(st) then return end
        ch.st = st
        st:EnableLooping(true)
        st:SetVolume(0)
        -- синхронизируемся с уже играющей петлёй
        local other = (ch == chans.main) and chans.crit.st or chans.main.st
        if IsValid(other) then st:SetTime(other:GetTime()) end
        st:Play()
    end)
end

local function StopAll()
    for _, ch in pairs(chans) do
        if IsValid(ch.st) then ch.st:Stop() end
        ch.st = nil
    end
end

hook.Add("Think", "REM_HeartCritical", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism

    local beating = ply:Alive() and org and org.alive ~= false
        and not org.heartstop and N(org.pulse, 70) >= 10
    local audible = beating and IsValid(hg.RemHealthPanel)
    -- пока петля звучит, отдельные удары своего сердца в cl_main.lua не играют
    hg.RemHeartCriticalActive = audible

    local crit = audible and IsCritical(org)
    mix = math.Approach(mix, crit and 1 or 0, FrameTime() / CFG.crossfade)

    local hbCvar = GetConVar("hg_heartbeat_volume")
    local base = Lerp(mix, CFG.vol_normal, CFG.vol_critical)
    local target = audible and base * (hbCvar and hbCvar:GetFloat() or 1) or 0
    local speed = FrameTime() / (audible and CFG.fade_in or CFG.fade_out)
    vol = math.Approach(vol, target, speed * math.max(target, CFG.vol_normal))

    if vol <= 0.001 then StopAll() return end

    Ensure(chans.main)
    Ensure(chans.crit)

    -- темп под пульс (+ "плавание" при аритмии)
    local bpm = N(org and org.heartbeat, 70)
    local target_rate = math.Clamp(bpm / CFG.BASE_BPM, CFG.rate_min, CFG.rate_max)
    local arr = N(org and org.arrhythmia, 0)
    if arr > 0.1 then
        target_rate = target_rate * (1 + math.sin(RealTime() * 2.7) * math.sin(RealTime() * 1.3) * 0.35 * arr)
    end
    rate = Lerp(math.min(FrameTime() * 3, 1), rate, target_rate)

    local volMain = vol * math.cos(mix * math.pi * 0.5)   -- равномощный кроссфейд
    local volCrit = vol * math.sin(mix * math.pi * 0.5)
    for key, ch in pairs(chans) do
        local st = ch.st
        if IsValid(st) then
            if st:GetState() ~= GMOD_CHANNEL_PLAYING then st:Play() end
            st:SetPlaybackRate(rate)
            st:SetVolume(key == "main" and volMain or volCrit)
        end
    end
end)
