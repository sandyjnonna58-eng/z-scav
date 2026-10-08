--[[
    Z-SCAV: сон и усталость на экране (сервер: modules/sv_rem_energy.lua).
    Во сне: тёмный экран, шкала энергии, качество сна. ПРОБЕЛ - проснуться.
    При усталости (энергия <= 25%) веки время от времени тяжелеют.
    zscav_sleep_hud 0 - убрать оверлей.
]]
local cvHud = CreateClientConVar("zscav_sleep_hud", "1", true, false)
local QUALITY = {"ПЛОХОЙ", "СРЕДНИЙ", "НОРМАЛЬНЫЙ", "ХОРОШИЙ"}
local QCOL = {Color(255, 90, 80), Color(255, 190, 80), Color(150, 220, 255), Color(120, 255, 170)}

surface.CreateFont("ZSCAV_SleepBig", {font = "Courier New", size = math.max(24, ScrH() / 14), weight = 900, extended = true})
surface.CreateFont("ZSCAV_SleepSmall", {font = "Courier New", size = math.max(14, ScrH() / 50), weight = 900, extended = true})

local alpha, lid = 0, 0
local nextWake = 0

local function Org()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    return ply.organism
end

hook.Add("Think", "ZSCAV_SleepWake", function()
    local org = Org()
    if not org or not org.remSleep then return end
    if vgui.CursorVisible() or gui.IsGameUIVisible() then return end
    if input.IsKeyDown(KEY_SPACE) and nextWake < RealTime() then
        nextWake = RealTime() + 1.2
        net.Start("zscav_sleep") net.WriteBool(false) net.SendToServer()
    end
end)

hook.Add("HUDPaint", "ZSCAV_SleepOverlay", function()
    local org = Org()
    local sleeping = org and org.remSleep == true
    local ft = FrameTime()
    alpha = math.Approach(alpha, sleeping and 1 or 0, ft * (sleeping and 0.8 or 1.6))

    -- тяжёлые веки при усталости
    local e = org and tonumber(org.remEnergy) or 100
    local want = 0
    if org and not sleeping and e <= 25 then
        local power = e <= 7 and 0.75 or (e <= 15 and 0.5 or 0.28)
        local period = e <= 7 and 6 or (e <= 15 and 10 or 16)
        local ph = (CurTime() % period) / period
        if ph > 0.88 then want = math.sin((ph - 0.88) / 0.12 * math.pi) * power end
    end
    lid = math.Approach(lid, want, ft * 2)

    local w, h = ScrW(), ScrH()
    if lid > 0.01 then
        local lh = h * 0.5 * lid
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, w, lh)
        surface.DrawRect(0, h - lh, w, lh + 1)
    end

    if alpha <= 0.01 or not cvHud:GetBool() then return end
    surface.SetDrawColor(2, 4, 12, 250 * alpha)
    surface.DrawRect(0, 0, w, h)
    if not org then return end

    local a = 255 * alpha
    local t = CurTime()
    -- плывущие "z"
    for i = 0, 2 do
        local ph = ((t * 0.35) + i / 3) % 1
        draw.SimpleText(i == 2 and "Z" or "z", "ZSCAV_SleepBig", w * 0.5 + ph * w * 0.05 + i * 8, h * 0.4 - ph * h * 0.12,
            Color(120, 160, 255, a * math.sin(ph * math.pi)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    draw.SimpleText("СОН", "ZSCAV_SleepBig", w * 0.5, h * 0.5, Color(170, 200, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local bw, bh = w * 0.26, math.max(10, h * 0.014)
    local bx, by = w * 0.5 - bw * 0.5, h * 0.58
    surface.SetDrawColor(30, 45, 80, a)
    surface.DrawRect(bx, by, bw, bh)
    surface.SetDrawColor(120, 170, 255, a)
    surface.DrawRect(bx, by, bw * math.Clamp(e / 100, 0, 1), bh)
    surface.DrawOutlinedRect(bx - 2, by - 2, bw + 4, bh + 4, 1)
    draw.SimpleText(("ЭНЕРГИЯ %d%%"):format(e), "ZSCAV_SleepSmall", w * 0.5, by + bh + 8, Color(170, 200, 255, a), TEXT_ALIGN_CENTER)

    local q = math.Clamp(math.floor(tonumber(org.remSleepQuality) or 1), 1, 4)
    local qc = QCOL[q]
    draw.SimpleText("СОН: " .. QUALITY[q], "ZSCAV_SleepSmall", w * 0.5, by + bh + 8 + h * 0.03, Color(qc.r, qc.g, qc.b, a), TEXT_ALIGN_CENTER)
    if q <= 2 then
        draw.SimpleText("на жёстком и на земле не выспаться - найди кровать или диван", "ZSCAV_SleepSmall", w * 0.5, by + bh + 8 + h * 0.06, Color(120, 140, 180, a * 0.8), TEXT_ALIGN_CENTER)
    end
    if e >= 10 then
        draw.SimpleText("ПРОБЕЛ - проснуться", "ZSCAV_SleepSmall", w * 0.5, h * 0.9, Color(120, 140, 180, a * (0.6 + 0.4 * math.sin(t * 2))), TEXT_ALIGN_CENTER)
    end
end)
