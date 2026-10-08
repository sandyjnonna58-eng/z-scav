--[[
    REM: экранный эффект высокого давления - красная виньетка пульсирует в такт сердцу.
    (Низкое давление уже затемняет экран через CardioLerp в cl_screeneffects.lua.)
]]

local gradU = surface.GetTextureID("vgui/gradient-u")
local gradD = surface.GetTextureID("vgui/gradient-d")
local gradL = surface.GetTextureID("vgui/gradient-l")
local gradR = surface.GetTextureID("vgui/gradient-r")

local lerp, phase = 0, 0

hook.Add("HUDPaint", "REM_PressureVignette", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then lerp = 0 return end
    local org = ply.organism
    if not org then return end

    local target = math.Clamp(((org.hypertension or 0) - 0.3) / 0.7, 0, 1)
    lerp = Lerp(FrameTime() * 2, lerp, target)
    if lerp < 0.01 then return end

    local bpm = math.Clamp(org.heartbeat or 70, 30, 220)
    phase = (phase + FrameTime() * bpm / 60) % 1
    local beat = math.max(0, 1 - phase * 5) -- короткий толчок на каждый удар

    local a = (60 + 120 * beat) * lerp
    local w, h = ScrW(), ScrH()
    local s = math.floor(h * (0.18 + 0.06 * beat) * (0.5 + lerp * 0.5))
    surface.SetDrawColor(160, 0, 0, a)
    surface.SetTexture(gradU) surface.DrawTexturedRect(0, h - s, w, s)
    surface.SetTexture(gradD) surface.DrawTexturedRect(0, 0, w, s)
    surface.SetTexture(gradR) surface.DrawTexturedRect(0, 0, s, h)
    surface.SetTexture(gradL) surface.DrawTexturedRect(w - s, 0, s, h)
end)
