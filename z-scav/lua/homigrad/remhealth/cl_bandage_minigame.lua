--[[
    Z-SCAV: мини-игра перевязки (клиент) - "физический" бинт.

    Чёрная панель, белые контуры (как шприц). Посередине - часть тела (трубка), на ней рана.
    Берёшь бинт: держи ЛКМ и води мышью КРУГАМИ вокруг части тела - каждый полный оборот
    = один виток бинта. Витки ложатся там, где ты крутишь: двигай круги вдоль руки/ноги,
    чтобы закрыть всю рану.
      * крутишь слишком быстро - бинт перетягивает (боль)
      * отпустил ЛКМ посреди оборота - виток соскальзывает
      * витки мимо раны - бинт тратится зря
    Рана закрыта и витков хватает - перевязка заканчивается сама. ПКМ/ESC - отмена (бинт не тратится).
    Протокол с сервером тот же (sv_bandage_minigame.lua).
]]

local MG = {
    active = false,
    TIMEOUT   = 25,
    SENS      = 0.6,    -- курсор от мыши
    BAND_W    = 46,     -- ширина бинта (пиксели панели в базовом масштабе)
    TOO_FAST  = 2.6,    -- оборотов в секунду - уже перетягивает
    FOLLOW    = 2.2,    -- как быстро место намотки следует за кругами
}
hg.RemBandageMGClient = MG

local C_WHITE = Color(235, 235, 235)
local C_DIM   = Color(150, 160, 180)
local C_GREEN = Color(80, 255, 150)
local C_YEL   = Color(255, 220, 80)
local C_RED   = Color(255, 70, 60)

local function S(v) return math.floor(v * ScrH() / 1080 + 0.5) end
local function Fonts()
    surface.CreateFont("RemBMG_Title", {font = "Courier New", size = S(26), weight = 900, antialias = false, extended = true})
    surface.CreateFont("RemBMG_Text",  {font = "Courier New", size = S(18), weight = 900, antialias = false, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "RemBMG_Fonts", Fonts)

-- толщина "трубки" по части тела
local function Thickness(name)
    if string.find(name, "ГРУДЬ", 1, true) or string.find(name, "ЖИВОТ", 1, true) or string.find(name, "ТАЗ", 1, true) then return 170 end
    if string.find(name, "ГОЛОВА", 1, true) then return 140 end
    if string.find(name, "ШЕЯ", 1, true) then return 90 end
    if string.find(name, "БЕДРО", 1, true) or string.find(name, "НОГА", 1, true) then return 120 end
    if string.find(name, "КИСТЬ", 1, true) or string.find(name, "СТОПА", 1, true) then return 75 end
    return 95
end

local BINS = 40       -- деление трубки по длине для учёта покрытия
local LEN  = 700      -- длина видимой части трубки (базовый масштаб)

local function Finish(cancelled)
    local st = MG.st
    MG.active = false
    MG.st = nil
    MG.blockUntilRelease = true
    if not st then return end

    local quality = 0
    if not cancelled and st.wraps > 0 then
        local sum, n = 0, 0
        for i = st.w1, st.w2 do sum = sum + math.min(st.cov[i], 2) / 2 n = n + 1 end
        local coverage = n > 0 and sum / n or 0
        local waste = st.wasted / math.max(st.wraps, 1)
        quality = math.Clamp(coverage * (1 - waste * 0.5), 0, 1)
    end

    net.Start("rem_bandage_mg_done")
        net.WriteEntity(st.wep)
        net.WriteBool(cancelled)
        net.WriteFloat(quality)
        net.WriteUInt(math.min(st.miss, 15), 4)
    net.SendToServer()

    if not cancelled then
        surface.PlaySound("snd_jack_hmcd_bandage.wav")
        MG.result = {q = quality, t = RealTime()}
    end
end

net.Receive("rem_bandage_mg", function()
    local wep = net.ReadEntity()
    local name = net.ReadString()
    local needed = net.ReadUInt(4)
    local diff = net.ReadFloat()

    local thick = Thickness(name)
    -- рана посередине; чем больше витков нужно, тем она длиннее
    local woundLen = math.Clamp(80 + needed * 30, 110, 260)
    local cov = {}
    for i = 1, BINS do cov[i] = 0 end
    local function bin(x) return math.Clamp(math.floor((x + LEN / 2) / LEN * BINS) + 1, 1, BINS) end

    local ply = LocalPlayer()
    MG.st = {
        wep = wep, name = name, needed = math.max(needed, 1), diff = diff, thick = thick,
        start = RealTime(), cov = cov, w1 = bin(-woundLen / 2), w2 = bin(woundLen / 2), woundLen = woundLen,
        cx = -220, cy = -thick,          -- курсор (относительно центра трубки)
        sx = -220,                       -- где сейчас наматываем (вдоль трубки)
        lastAng = nil, acc = 0, wrapStart = RealTime(),
        wraps = 0, wasted = 0, miss = 0, bands = {},
        lmb = input.IsMouseDown(MOUSE_LEFT), rmb = input.IsMouseDown(MOUSE_RIGHT),
        lockAng = IsValid(ply) and ply:EyeAngles() or Angle(),
        msg = nil, msgT = 0, msgCol = C_WHITE,
    }
    MG.st.bin = bin
    MG.mdx, MG.mdy = 0, 0
    MG.active = true
    MG.result = nil
end)

-- мышь ведёт бинт, камера стоит, атаки заглушены
hook.Add("CreateMove", "RemBandageMG", function(cmd)
    if MG.blockUntilRelease and not MG.active then
        if input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT) then
            cmd:RemoveKey(IN_ATTACK) cmd:RemoveKey(IN_ATTACK2)
        else
            MG.blockUntilRelease = false
        end
        return
    end
    if not MG.active or not MG.st then return end
    MG.mdx = (MG.mdx or 0) + cmd:GetMouseX()
    MG.mdy = (MG.mdy or 0) + cmd:GetMouseY()
    cmd:SetViewAngles(MG.st.lockAng)
    cmd:RemoveKey(IN_ATTACK)
    cmd:RemoveKey(IN_ATTACK2)
end)

local function Msg(st, text, col) st.msg, st.msgT, st.msgCol = text, RealTime(), col end

local function WoundCovered(st)
    for i = st.w1, st.w2 do if st.cov[i] < 1 then return false end end
    return true
end

hook.Add("Think", "RemBandageMG", function()
    local st = MG.st
    if not MG.active or not st then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or not IsValid(st.wep) or ply:GetActiveWeapon() ~= st.wep then Finish(true) return end
    local t, dt = RealTime(), RealFrameTime()
    if t - st.start > MG.TIMEOUT then Finish(st.wraps == 0) return end

    local mdx, mdy = MG.mdx or 0, MG.mdy or 0
    MG.mdx, MG.mdy = 0, 0
    local lmb, rmb = input.IsMouseDown(MOUSE_LEFT), input.IsMouseDown(MOUSE_RIGHT)
    local rPressed = rmb and not st.rmb
    local lReleased = (not lmb) and st.lmb
    st.lmb, st.rmb = lmb, rmb
    if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end
    if rPressed then Finish(true) return end

    -- курсор (рука с бинтом), дрожит от боли
    local shake = st.diff * 6
    st.cx = math.Clamp(st.cx + mdx * MG.SENS + math.sin(t * 8) * shake * 0.3, -LEN / 2 - 40, LEN / 2 + 40)
    st.cy = math.Clamp(st.cy + mdy * MG.SENS + math.cos(t * 7) * shake * 0.3, -260, 260)

    -- место намотки плавно следует за центром кругов
    st.sx = Lerp(math.min(dt * MG.FOLLOW, 1), st.sx, st.cx)

    local dx, dy = st.cx - st.sx, st.cy
    local r = math.sqrt(dx * dx + dy * dy)
    local ang = math.atan2(dy, dx)

    if lReleased and math.abs(st.acc) > 0.6 then
        Msg(st, "БИНТ СОСКОЛЬЗНУЛ", C_YEL)
        st.acc = 0
    end

    if lmb then
        if r < st.thick * 0.55 then
            -- водишь по самой ране, а не вокруг
            st.lastAng = nil
            if t - st.msgT > 1 then Msg(st, "ОБВОДИ ВОКРУГ", C_YEL) end
        else
            if st.lastAng then
                local d = ang - st.lastAng
                if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
                -- считаем только одно направление (какое начал)
                if st.acc == 0 then st.dir = d >= 0 and 1 or -1 end
                if d * (st.dir or 1) > 0 then st.acc = st.acc + math.abs(d) end
            else
                st.wrapStart = t
            end
            st.lastAng = ang
            if st.acc >= 2 * math.pi then
                -- полный виток
                local took = t - st.wrapStart
                st.acc, st.wrapStart = 0, t
                st.wraps = st.wraps + 1
                local tight = took < 1 / MG.TOO_FAST
                if tight then
                    st.miss = st.miss + 1
                    Msg(st, "СЛИШКОМ ТУГО!", C_RED)
                    surface.PlaySound("physics/flesh/flesh_impact_bullet" .. math.random(1, 3) .. ".wav")
                else
                    surface.PlaySound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav")
                end
                -- покрытие
                local b1, b2 = st.bin(st.sx - MG.BAND_W / 2), st.bin(st.sx + MG.BAND_W / 2)
                local onWound = false
                for i = b1, b2 do
                    st.cov[i] = st.cov[i] + 1
                    if i >= st.w1 and i <= st.w2 then onWound = true end
                end
                if not onWound then st.wasted = st.wasted + 1 if not tight then Msg(st, "МИМО РАНЫ", C_YEL) end
                elseif not tight then Msg(st, "ВИТОК", C_GREEN) end
                st.bands[#st.bands + 1] = {x = st.sx, slant = math.Rand(-12, 12), tight = tight}

                if WoundCovered(st) and st.wraps >= st.needed then Finish(false) return end
            end
        end
    else
        st.lastAng = nil
    end
end)

hook.Add("OnShowZCityPause", "RemBandageMG_Esc", function()
    if MG.active then Finish(true) return false end
end)

-- ---------------------------------------------------------------------------
-- рисование
-- ---------------------------------------------------------------------------
local function Quad(x1, y1, x2, y2, x3, y3, x4, y4, col)
    surface.SetDrawColor(col)
    draw.NoTexture()
    surface.DrawPoly({{x = x1, y = y1}, {x = x2, y = y2}, {x = x3, y = y3}, {x = x4, y = y4}})
end

hook.Add("HUDPaint", "RemBandageMG", function()
    if MG.result and RealTime() - MG.result.t < 2 then
        local q = MG.result.q
        local txt = q > 0.85 and "ОТЛИЧНАЯ ПЕРЕВЯЗКА" or (q > 0.55 and "ХОРОШАЯ ПЕРЕВЯЗКА" or (q > 0.25 and "КРИВАЯ ПЕРЕВЯЗКА" or "РАНА ПОЧТИ ОТКРЫТА"))
        local a = 255 * math.Clamp(2 - (RealTime() - MG.result.t), 0, 1)
        local col = q > 0.55 and C_GREEN or (q > 0.25 and C_YEL or C_RED)
        draw.SimpleTextOutlined(txt .. ("  %d%%"):format(q * 100), "RemBMG_Title", ScrW() * 0.5, ScrH() * 0.62,
            Color(col.r, col.g, col.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a))
    end

    local st = MG.st
    if not MG.active or not st then return end
    local now = RealTime()

    local pw, ph = S(900), S(560)
    local bx, by = (ScrW() - pw) * 0.5, (ScrH() - ph) * 0.5
    surface.SetDrawColor(0, 0, 0, 245) surface.DrawRect(bx, by, pw, ph)
    draw.SimpleText("Держи ЛКМ и обматывай бинт кругами вокруг. Закрой всю рану.", "RemBMG_Text", bx + S(16), by + S(12), C_WHITE)
    draw.SimpleText("ПЕРЕВЯЗКА: " .. st.name, "RemBMG_Text", bx + S(16), by + S(36), C_DIM)

    local k = S(100) / 100
    local ox, oy = bx + pw * 0.5, by + ph * 0.55
    local function P(x, y) return ox + x * k, oy + y * k end
    local half = st.thick / 2

    render.SetScissorRect(bx, by, bx + pw, by + ph, true)

    -- часть тела: трубка
    local x1, yT = P(-LEN / 2 - 60, -half)
    local x2, yB = P(LEN / 2 + 60, half)
    surface.SetDrawColor(C_WHITE)
    surface.DrawRect(x1, yT, x2 - x1, math.max(2, S(3)))
    surface.DrawRect(x1, yB, x2 - x1, math.max(2, S(3)))

    -- рана: красные штрихи, бледнеют под бинтом
    for i = st.w1, st.w2 do
        local cx0 = -LEN / 2 + (i - 0.5) * LEN / BINS
        local c = st.cov[i]
        local a = c >= 2 and 30 or (c >= 1 and 90 or 220)
        local px, py = P(cx0, 0)
        local pulse = c == 0 and (0.75 + 0.25 * math.sin(now * 6 + i)) or 1
        surface.SetDrawColor(200, 25, 25, a * pulse)
        surface.DrawRect(px - S(6), py - half * k * 0.55, S(12), half * k * 1.1)
    end

    -- уложенные витки: диагональные полосы
    local bw = MG.BAND_W
    for _, b in ipairs(st.bands) do
        local xa, ya = P(b.x - bw / 2 + b.slant, -half)
        local xb, yb2 = P(b.x + bw / 2 + b.slant, -half)
        local xc, yc = P(b.x + bw / 2 - b.slant, half)
        local xd, yd = P(b.x - bw / 2 - b.slant, half)
        Quad(xa, ya, xb, yb2, xc, yc, xd, yd, b.tight and Color(220, 190, 190, 235) or Color(225, 225, 215, 235))
        surface.SetDrawColor(120, 120, 110, 255)
        surface.DrawLine(xa, ya, xd, yd) surface.DrawLine(xb, yb2, xc, yc)
    end

    -- текущий оборот: бинт тянется от места намотки к руке
    local sx, sy = P(st.sx, 0)
    local hx, hy = P(st.cx, st.cy)
    local behind = st.cy < 0 and st.lmb -- над трубкой - уходит "за" руку
    if st.lmb then
        local ex, ey = P(st.sx, st.cy < 0 and -half or half)
        surface.SetDrawColor(225, 225, 215, behind and 120 or 255)
        for i = -2, 2 do surface.DrawLine(ex + i, ey, hx + i, hy) end
    end
    -- метка места намотки
    surface.SetDrawColor(C_GREEN.r, C_GREEN.g, C_GREEN.b, 120)
    surface.DrawRect(sx - S(1), sy - half * k - S(10), S(2), S(8))

    -- рулон бинта в руке
    local rr = S(22)
    surface.DrawCircle(hx, hy, rr, 235, 235, 225, 255)
    surface.DrawCircle(hx, hy, rr * 0.45, 235, 235, 225, 255)
    -- прогресс оборота
    if st.acc > 0 then
        local frac = math.Clamp(st.acc / (2 * math.pi), 0, 1)
        draw.SimpleText(("%d%%"):format(frac * 100), "RemBMG_Text", hx + rr + S(6), hy - S(10), C_GREEN)
    end

    render.SetScissorRect(0, 0, 0, 0, false)

    -- статус
    local covered = 0
    for i = st.w1, st.w2 do if st.cov[i] >= 1 then covered = covered + 1 end end
    local covFrac = covered / (st.w2 - st.w1 + 1)
    draw.SimpleText(("РАНА ЗАКРЫТА %d%%"):format(covFrac * 100), "RemBMG_Text", bx + pw - S(16), by + S(12), covFrac >= 1 and C_GREEN or C_WHITE, TEXT_ALIGN_RIGHT)
    draw.SimpleText(("ВИТКИ %d / %d"):format(st.wraps, st.needed), "RemBMG_Text", bx + pw - S(16), by + S(36), st.wraps >= st.needed and C_GREEN or C_DIM, TEXT_ALIGN_RIGHT)
    local left = math.max(0, MG.TIMEOUT - (now - st.start))
    draw.SimpleText(("%.1f с"):format(left), "RemBMG_Text", bx + S(16), by + ph - S(30), left < 5 and C_RED or C_DIM)
    if st.msg and now - st.msgT < 0.9 then
        local a = 255 * math.Clamp(1 - (now - st.msgT) / 0.9, 0, 1)
        draw.SimpleText(st.msg, "RemBMG_Title", bx + pw * 0.5, by + ph - S(46), Color(st.msgCol.r, st.msgCol.g, st.msgCol.b, a), TEXT_ALIGN_CENTER)
    end
    draw.SimpleText("ЛКМ (держать) + круги мышью - обматывать   ПКМ/ESC - отмена", "RemBMG_Text", bx + pw * 0.5, by + ph + S(8), Color(200, 200, 200, 160), TEXT_ALIGN_CENTER)
end)
