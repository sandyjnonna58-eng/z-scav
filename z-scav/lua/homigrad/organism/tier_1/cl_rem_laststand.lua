--[[
    Z-SCAV: эффект последнего рубежа на экране.
    Красные края пульсируют в такт бешеному сердцу, мир чуть обесцвечен и резче,
    в начале - надпись. К концу эффект плавно сходит на нет.
]]

local gradU = surface.GetTextureID("vgui/gradient-u")
local gradD = surface.GetTextureID("vgui/gradient-d")
local gradL = surface.GetTextureID("vgui/gradient-l")
local gradR = surface.GetTextureID("vgui/gradient-r")

surface.CreateFont("ZSCAV_LastStand", {font = "Courier New", size = math.floor(ScrH() / 22), weight = 900, antialias = true, extended = true})

local startT, lastEnd = nil, 0

-- заставка срабатывания: чёрный экран с надписью "Let's not give up just yet."
local matSplash = Material("zscav/last_stand.png", "smooth")
local SPLASH_IN, SPLASH_HOLD, SPLASH_OUT = 0.25, 2.8, 1.2

-- звук последнего рубежа: играет с момента срабатывания, к концу эффекта плавно затихает
local DRONE_PATH = "sound/remorse/laststand_drone.ogg"
local DRONE_VOL, DRONE_FADE = 0.9, 3
local drone, droneLoading, droneFor = nil, false, 0

local function StartDrone(forEnd)
    if droneFor == forEnd then return end
    droneFor = forEnd
    if IsValid(drone) then drone:Stop() drone = nil end
    if droneLoading or not file.Exists(DRONE_PATH, "GAME") then return end
    droneLoading = true
    sound.PlayFile(DRONE_PATH, "noplay", function(st)
        droneLoading = false
        if not IsValid(st) then return end
        drone = st
        st:SetVolume(DRONE_VOL)
        st:Play()
    end)
end

hook.Add("Think", "ZSCAV_LastStandDrone", function()
    local ply = LocalPlayer()
    local org = IsValid(ply) and ply.organism
    local e = org and tonumber(org.remLastStand) or 0
    local left = e - CurTime()
    hg.RemLastStandActive = IsValid(ply) and ply:Alive() and left > 0
    if not IsValid(drone) then return end
    if not ply:Alive() then drone:Stop() drone = nil return end
    -- дотягиваем до конца трека; если эффект закончился раньше - плавно гасим
    if left < DRONE_FADE then
        local v = DRONE_VOL * math.Clamp(left / DRONE_FADE, 0, 1)
        if left <= 0 then
            v = math.max(0, drone:GetVolume() - FrameTime() * DRONE_VOL / DRONE_FADE)
        end
        if v <= 0.01 then drone:Stop() drone = nil return end
        drone:SetVolume(v)
    end
end)

local function Active()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false, 0 end
    local org = ply.organism
    local e = org and tonumber(org.remLastStand) or 0
    return e > CurTime(), e
end

hook.Add("RenderScreenspaceEffects", "ZSCAV_LastStand", function()
    local on, e = Active()
    if not on then return end
    local left = e - CurTime()
    local fade = math.Clamp(left / 3, 0, 1) -- к концу выцветает
    DrawColorModify({
        ["$pp_colour_addr"] = 0.04 * fade, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -0.02, ["$pp_colour_contrast"] = 1 + 0.25 * fade,
        ["$pp_colour_colour"] = 1 - 0.45 * fade,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
    })
end)

hook.Add("HUDPaint", "ZSCAV_LastStand", function()
    local on, e = Active()
    if not on then startT = nil return end
    if not startT or e ~= lastEnd then
        startT, lastEnd = CurTime(), e
        surface.PlaySound("remorse/heart/beat_normal.ogg")
        StartDrone(e)
    end
    local w, h = ScrW(), ScrH()
    local t = CurTime()
    local left = e - t
    -- удары сердца ~150/мин
    local ph = (t * 2.5) % 1
    local beat = math.max(0, 1 - ph * 5)
    local endDark = math.Clamp(1 - left / 3, 0, 1)

    local a = 90 + 120 * beat
    local s = math.floor(h * (0.2 + 0.07 * beat) * (1 - endDark * 0.8))
    surface.SetDrawColor(150, 0, 0, a)
    surface.SetTexture(gradU) surface.DrawTexturedRect(0, h - s, w, s)
    surface.SetTexture(gradD) surface.DrawTexturedRect(0, 0, w, s)
    surface.SetTexture(gradR) surface.DrawTexturedRect(0, 0, s, h)
    surface.SetTexture(gradL) surface.DrawTexturedRect(w - s, 0, s, h)


    -- заставка: на весь экран (с сохранением пропорций), потом плавно уходит
    local since = t - startT
    local total = SPLASH_IN + SPLASH_HOLD + SPLASH_OUT
    if since < total then
        local a
        if since < SPLASH_IN then a = since / SPLASH_IN
        elseif since < SPLASH_IN + SPLASH_HOLD then a = 1
        else a = 1 - (since - SPLASH_IN - SPLASH_HOLD) / SPLASH_OUT end
        a = math.Clamp(a, 0, 1)
        surface.SetDrawColor(0, 0, 0, 255 * a)
        surface.DrawRect(0, 0, w, h)
        if matSplash and not matSplash:IsError() then
            local iw, ih = matSplash:Width(), matSplash:Height()
            local sc = math.max(w / iw, h / ih)
            local dw, dh = iw * sc, ih * sc
            -- лёгкое "дрожание" плёнки
            local jx, jy = math.Rand(-1, 1), math.Rand(-1, 1)
            surface.SetDrawColor(255, 255, 255, 255 * a)
            surface.SetMaterial(matSplash)
            surface.DrawTexturedRect((w - dw) * 0.5 + jx, (h - dh) * 0.5 + jy, dw, dh)
        else
            draw.SimpleText("Не будем сдаваться раньше времени.", "ZSCAV_LastStand", w * 0.5, h * 0.5, Color(230, 230, 230, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)
