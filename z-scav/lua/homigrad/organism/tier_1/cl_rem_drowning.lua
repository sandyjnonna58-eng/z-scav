--[[
    Z-SCAV: музыка удушья.
    Играет (по кругу), пока кислорода у игрока меньше 60%.
    Выключается, когда кислород поднимется выше 65%.
    Чем меньше кислорода, тем громче. Пока играет, музыка отчаяния (Despair) приглушается.
    Не играет во время таймера умирания и после смерти.
]]

local CFG = {
    path      = "sound/remorse/drowning.ogg",
    on_below  = 0.60,  -- доля кислорода (o2[1] / o2.range)
    off_above = 0.65,
    vol_min   = 0.35,  -- громкость на пороге
    vol_max   = 0.8,   -- громкость при нуле кислорода
    fade_in   = 1.5,
    fade_out  = 2,
}
hg.RemDrowningCfg = CFG

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

hook.Add("Think", "ZSCAV_Drowning", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism

    local o2 = 1
    if org and istable(org.o2) and isnumber(org.o2[1]) then
        o2 = org.o2[1] / math.max(isnumber(org.o2.range) and org.o2.range or 30, 1)
    end

    local blocked = not ply:Alive() or (org and org.deathStateEnd and org.deathStateEnd > 0)
    if blocked then
        active = false
    elseif not active and o2 < CFG.on_below then
        active = true
    elseif active and o2 > CFG.off_above then
        active = false
    end
    hg.RemDrowningActive = active

    local depth = math.Clamp(1 - o2 / CFG.on_below, 0, 1)
    local target = active and Lerp(depth, CFG.vol_min, CFG.vol_max) * (hg.RemEndActive and 0.4 or 1) * (hg.RemLastStandActive and 0.15 or 1) or 0
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
