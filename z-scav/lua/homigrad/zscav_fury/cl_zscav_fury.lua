--[[
    Z-SCAV: музыка босса для Fury-13 (клиент).
    RUN_FOR_YOUR_LIFE звучит "от" игрока под Fury-13: рядом - громко, чем дальше - тем тише,
    дальше FAR - тишина. Если таких игроков несколько - слышно ближайшего.
    Убил игрока под Fury-13 - играет ThornbackDefeat.
]]

local CFG = {
    music    = "sound/remorse/fury/run_for_your_life.ogg",
    defeat   = "sound/remorse/fury/thornback_defeat.ogg",
    volume   = 0.85,
    NEAR     = 250,   -- до этого расстояния - полная громкость
    FAR      = 2600,  -- дальше - тишина
    curve    = 1.6,   -- как быстро стихает с расстоянием
    smooth   = 4,     -- плавность изменения громкости
}
hg.ZSCAVFuryCfg = CFG

local station, loading, vol = nil, false, 0

local function Ensure()
    if IsValid(station) or loading or not file.Exists(CFG.music, "GAME") then return end
    loading = true
    sound.PlayFile(CFG.music, "noplay", function(st)
        loading = false
        if not IsValid(st) then return end
        station = st
        st:EnableLooping(true)
        st:SetVolume(0)
        st:Play()
    end)
end

hook.Add("Think", "ZSCAV_FuryMusic", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local myPos = lp:EyePos()

    -- ближайший игрок под Fury-13 (включая себя)
    local best = math.huge
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNWBool("zscav_fury", false) and ply:Alive() then
            local ent = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
            local d = (ply == lp) and 0 or ent:WorldSpaceCenter():Distance(myPos)
            if d < best then best = d end
        end
    end

    local target = 0
    if best < CFG.FAR then
        local f = 1 - math.Clamp((best - CFG.NEAR) / (CFG.FAR - CFG.NEAR), 0, 1)
        target = CFG.volume * f ^ CFG.curve
    end
    if hg.RemDyingSilence then target = 0 end -- при умирании - только музыка умирания
    vol = Lerp(math.min(FrameTime() * CFG.smooth, 1), vol, target)
    hg.ZSCAVFuryMusicVol = vol

    if vol > 0.005 then
        Ensure()
        if IsValid(station) then station:SetVolume(vol) end
    elseif IsValid(station) and target == 0 then
        station:Stop()
        station = nil
    end
end)

net.Receive("zscav_fury_defeat", function()
    if not file.Exists(CFG.defeat, "GAME") then
        print("[Z-SCAV fury] нет файла " .. CFG.defeat)
        surface.PlaySound("remorse/fury/thornback_defeat.ogg")
        return
    end
    sound.PlayFile(CFG.defeat, "noplay", function(st)
        if IsValid(st) then st:SetVolume(0.9) st:Play() end
    end)
end)
