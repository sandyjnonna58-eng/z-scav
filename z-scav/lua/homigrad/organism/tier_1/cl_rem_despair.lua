--[[
    Z-SCAV: музыка отчаяния.
    Играет (по кругу, с плавным появлением), пока настроение игрока ниже -60.
    Чтобы не дёргалась на границе, выключается только когда настроение поднимется выше -56.
    Не играет во время таймера умирания и после смерти (там свои треки).
]]

local CFG = {
    path      = "sound/remorse/despair.ogg",
    on_below  = -0.60,  -- org.mood: -1..1  (=-60)
    off_above = -0.56,
    volume    = 0.6,
    fade_in   = 4,      -- сек
    fade_out  = 3,
}
hg.RemDespairCfg = CFG

local station, loading, active, vol = nil, false, false, 0

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

hook.Add("Think", "ZSCAV_Despair", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism
    local mood = org and org.mood or 0

    local blocked = not ply:Alive() or (org and org.deathStateEnd and org.deathStateEnd > 0)
    if blocked then
        active = false
    elseif not active and mood <= CFG.on_below then
        active = true
    elseif active and mood > CFG.off_above then
        active = false
    end

    local target = active and CFG.volume * ((hg.RemDrowningActive or hg.RemEndActive) and 0.25 or 1) * (hg.RemLastStandActive and 0.15 or 1) or 0 -- удушье и "конец" важнее
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
