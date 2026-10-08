--[[
    Z-SCAV: звук усталости.
    Играет (по кругу), пока выносливости меньше 50%.
    Выключается, когда выносливость поднимется выше 60%.
    Чем меньше выносливости, тем громче. Если идёт удушье (Drowning) - приглушается.
    Не играет во время таймера умирания и после смерти.
]]

local CFG = {
    path      = "sound/remorse/exhausted_loop.ogg",
    on_below  = 0.50,  -- доля выносливости (stamina[1] / stamina.max)
    off_above = 0.60,
    vol_min   = 0.25,
    vol_max   = 0.7,
    fade_in   = 1.0,
    fade_out  = 2.5,
}
hg.RemExhaustedCfg = CFG

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

hook.Add("Think", "ZSCAV_Exhausted", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism

    local frac = 1
    local st = org and org.stamina
    if istable(st) and isnumber(st[1]) then
        local mx = (isnumber(st.max) and st.max > 0) and st.max or (isnumber(st.range) and st.range or 180)
        frac = st[1] / math.max(mx, 1)
    end

    local blocked = not ply:Alive() or (org and org.deathStateEnd and org.deathStateEnd > 0)
    if blocked then
        active = false
    elseif not active and frac < CFG.on_below then
        active = true
    elseif active and frac > CFG.off_above then
        active = false
    end
    hg.RemExhaustedActive = active

    local depth = math.Clamp(1 - frac / CFG.on_below, 0, 1)
    local target = active and Lerp(depth, CFG.vol_min, CFG.vol_max) * ((hg.RemDrowningActive or hg.RemEndActive) and 0.3 or 1) * (hg.RemLastStandActive and 0.15 or 1) or 0
    local speed = FrameTime() * CFG.vol_max / (active and CFG.fade_in or CFG.fade_out)
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
