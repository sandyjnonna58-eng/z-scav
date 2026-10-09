--[[
    Z-SCAV: музыка смерти.
    Когда игрок умер - один раз играет sound/remorse/death.ogg.
    Возродился - трек плавно затихает.
]]

local CFG = {
    path   = "sound/remorse/death.ogg",
    volume = 0.8,
    fade   = 1.5, -- сек затухания после возрождения
}
hg.RemDeathMusicCfg = CFG

local station, loading, wasAlive, fading = nil, false, true, false

local function StopNow()
    if IsValid(station) then station:Stop() end
    station, fading = nil, false
end

local function Play()
    StopNow()
    if loading or not file.Exists(CFG.path, "GAME") then return end
    loading = true
    sound.PlayFile(CFG.path, "noplay", function(st)
        loading = false
        if not IsValid(st) then return end
        local ply = LocalPlayer()
        if IsValid(ply) and ply:Alive() then st:Stop() return end -- уже возродился
        station = st
        st:SetVolume(CFG.volume)
        st:Play()
    end)
end

-- экран смерти пропущен - музыка быстро затихает
hook.Add("ZSCAV_DeathScreenSkipped", "ZSCAV_DeathMusic", function()
    if IsValid(station) then fading = true end
end)

hook.Add("Think", "ZSCAV_DeathMusic", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local alive = ply:Alive()

    if wasAlive and not alive then
        Play()
    elseif not wasAlive and alive and IsValid(station) then
        fading = true
    end
    wasAlive = alive

    if fading and IsValid(station) then
        local v = station:GetVolume() - FrameTime() * CFG.volume / CFG.fade
        if v <= 0.01 then StopNow() else station:SetVolume(v) end
    end
end)
