--[[
    REM: мини-игра СЛР (клиент).

    Держишь ЛКМ на груди лежащего (как раньше) - открывается монитор СЛР.
      * ПРОБЕЛ - компрессия. Жми в такт метроному (~110/мин).
        Короткое нажатие - слабо, слишком долгое - слишком сильно (можно сломать рёбра).
      * После 30 компрессий - 2 вдоха: держи ПРОБЕЛ ~1 сек на каждый.
]]

local CPR = {
    active = false,
    BPM = 110,
    COMPRESSIONS = 30,
    BREATHS = 2,
    DEPTH_MIN = 0.08,   -- сек удержания: меньше - "слабо"
    DEPTH_MAX = 0.32,   -- больше - "слишком сильно"
    BREATH_MIN = 0.7,
    BREATH_MAX = 1.5,
}
hg.RemCPRClient = CPR

local C_BG    = Color(20, 36, 28, 235)
local C_GREEN = Color(80, 255, 150)
local C_DIM   = Color(40, 140, 85)
local C_DARK  = Color(25, 70, 45)
local C_YEL   = Color(255, 220, 80)
local C_RED   = Color(255, 70, 60)
local C_WHITE = Color(235, 235, 225)

local function S(v) return math.floor(v * ScrH() / 1080 + 0.5) end
local function Fonts()
    surface.CreateFont("RemCPR_Title", {font = "Courier New", size = S(26), weight = 900, antialias = false, extended = true})
    surface.CreateFont("RemCPR_Big",   {font = "Courier New", size = S(40), weight = 900, antialias = false, extended = true})
    surface.CreateFont("RemCPR_Text",  {font = "Courier New", size = S(18), weight = 900, antialias = false, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "RemCPR_Fonts", Fonts)

local function Send(kind, q, hard)
    net.Start("rem_cpr_press")
        net.WriteUInt(kind, 2)
        net.WriteFloat(q)
        net.WriteBool(hard and true or false)
    net.SendToServer()
end

net.Receive("rem_cpr_mg", function()
    local on = net.ReadBool()
    local target = net.ReadEntity()
    if not on then
        CPR.active = false
        CPR.st = nil
        return
    end
    CPR.active = true
    CPR.st = {
        target = target, start = RealTime(),
        phase = "comp", count = 0, breaths = 0,
        lastPress = nil, downAt = nil, msg = nil, msgT = 0, msgCol = C_GREEN,
        qSum = 0, qN = 0, heartstop = true, alive = true, o2 = 0,
        space = input.IsKeyDown(KEY_SPACE),
    }
end)

net.Receive("rem_cpr_fb", function()
    local alive = net.ReadBool()
    local heartstop = net.ReadBool()
    local o2 = net.ReadUInt(7)
    local st = CPR.st
    if not st then return end
    if st.heartstop and not heartstop and alive then
        st.restartT = RealTime()
        surface.PlaySound("buttons/blip1.wav")
    end
    st.alive, st.heartstop, st.o2 = alive, heartstop, o2
end)

local function Msg(st, text, col)
    st.msg, st.msgT, st.msgCol = text, RealTime(), col
end

hook.Add("CreateMove", "RemCPRMG", function(cmd)
    if CPR.active then cmd:RemoveKey(IN_JUMP) end
end)

hook.Add("Think", "RemCPRMG", function()
    local st = CPR.st
    if not CPR.active or not st then return end
    if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end

    local now = RealTime()
    local down = input.IsKeyDown(KEY_SPACE)
    local pressed, released = down and not st.space, (not down) and st.space
    st.space = down

    if pressed then st.downAt = now end

    if released and st.downAt then
        local held = now - st.downAt
        st.downAt = nil

        if st.phase == "comp" then
            local ideal = 60 / CPR.BPM
            local qT = 1
            if st.lastPress then
                local gap = now - st.lastPress
                qT = 1 - math.Clamp(math.abs(gap - ideal) / (ideal * 0.6), 0, 1)
                if gap > ideal * 1.6 then Msg(st, "МЕДЛЕННО", C_YEL)
                elseif gap < ideal * 0.6 then Msg(st, "БЫСТРО", C_YEL) end
            end
            st.lastPress = now

            local qD, hard = 1, false
            if held < CPR.DEPTH_MIN then
                qD = 0.4; Msg(st, "СЛАБО", C_YEL)
            elseif held > CPR.DEPTH_MAX then
                qD, hard = 0.7, true; Msg(st, "СЛИШКОМ СИЛЬНО", C_RED)
            end
            local q = math.Clamp(qT * qD, 0.05, 1)
            if q > 0.85 and not hard and held >= CPR.DEPTH_MIN then Msg(st, "ОТЛИЧНО", C_GREEN) end

            st.qSum, st.qN = st.qSum + q, st.qN + 1
            st.lastQ = q
            st.count = st.count + 1
            st.pushT = now
            Send(0, q, hard)

            if st.count >= CPR.COMPRESSIONS then
                st.phase, st.breaths = "breath", 0
                Msg(st, "2 ВДОХА!", C_WHITE)
            end
        else
            local q = 1
            if held < CPR.BREATH_MIN then q = math.Clamp(held / CPR.BREATH_MIN, 0.1, 1) * 0.6; Msg(st, "КОРОТКИЙ ВДОХ", C_YEL)
            elseif held > CPR.BREATH_MAX then q = 0.6; Msg(st, "ПЕРЕДУЛ", C_YEL)
            else Msg(st, "ВДОХ", C_GREEN) end
            Send(1, q, false)
            st.breaths = st.breaths + 1
            if st.breaths >= CPR.BREATHS then
                st.phase, st.count, st.lastPress = "comp", 0, nil
                Msg(st, "КОМПРЕССИИ", C_WHITE)
            end
        end
    end
end)

hook.Add("HUDPaint", "RemCPRMG", function()
    local st = CPR.st
    if not CPR.active or not st then return end
    local now = RealTime()

    local bw, bh = S(420), S(330)
    local bx, by = (ScrW() - bw) * 0.5, ScrH() - bh - S(120)
    surface.SetDrawColor(C_BG) surface.DrawRect(bx, by, bw, bh)
    surface.SetDrawColor(C_DIM) surface.DrawOutlinedRect(bx, by, bw, bh, 2)
    local cx = ScrW() * 0.5

    draw.SimpleText("СЛР", "RemCPR_Title", cx, by + S(8), C_GREEN, TEXT_ALIGN_CENTER)

    -- состояние пациента
    local stateTxt, stateCol
    if not st.alive then stateTxt, stateCol = "ПАЦИЕНТ МЁРТВ", C_RED
    elseif st.restartT and now - st.restartT < 3 then stateTxt, stateCol = "ПУЛЬС ПОЯВИЛСЯ!", C_GREEN
    elseif st.heartstop then stateTxt, stateCol = "СЕРДЦЕ НЕ БЬЁТСЯ", (math.sin(now * 8) > 0) and C_RED or C_YEL
    else stateTxt, stateCol = "ПУЛЬС ЕСТЬ", C_GREEN end
    draw.SimpleText(stateTxt, "RemCPR_Text", cx, by + S(38), stateCol, TEXT_ALIGN_CENTER)
    draw.SimpleText(("O2 %d%%"):format(st.o2 or 0), "RemCPR_Text", bx + bw - S(12), by + S(10), (st.o2 or 0) < 40 and C_RED or C_DIM, TEXT_ALIGN_RIGHT)

    -- метроном
    local ideal = 60 / CPR.BPM
    local ph = ((now - st.start) % ideal) / ideal
    local beat = math.max(0, 1 - ph * 4)
    local mR = S(40) + beat * S(14)
    local my = by + S(130)
    if st.phase == "comp" then
        surface.DrawCircle(cx, my, mR, 80, 255, 150, 80 + 175 * beat)
        surface.DrawCircle(cx, my, mR - 2, 80, 255, 150, 60 + 120 * beat)
        -- "грудь" прогибается при нажатии
        local push = st.downAt and 1 or math.max(0, 1 - (now - (st.pushT or 0)) / 0.15)
        local hw = S(60)
        surface.SetDrawColor(C_WHITE)
        surface.DrawRect(cx - hw, my - S(6) + push * S(14), hw * 2, S(12))
        draw.SimpleText(("%d / %d"):format(st.count, CPR.COMPRESSIONS), "RemCPR_Big", cx, my + S(58), C_GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        local held = st.downAt and (now - st.downAt) or 0
        local frac = math.Clamp(held / CPR.BREATH_MAX, 0, 1)
        local barW, barH = S(300), S(26)
        local barX, barY = cx - barW * 0.5, my - barH * 0.5
        surface.SetDrawColor(C_DARK) surface.DrawRect(barX, barY, barW, barH)
        local g1 = barX + barW * (CPR.BREATH_MIN / CPR.BREATH_MAX)
        surface.SetDrawColor(25, 110, 60) surface.DrawRect(g1, barY, barX + barW - g1, barH)
        surface.SetDrawColor(C_WHITE) surface.DrawRect(barX, barY + S(6), barW * frac, barH - S(12))
        surface.SetDrawColor(C_GREEN) surface.DrawOutlinedRect(barX, barY, barW, barH, 2)
        draw.SimpleText(("ВДОХ %d / %d"):format(st.breaths, CPR.BREATHS), "RemCPR_Big", cx, my + S(58), C_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- подсказка-оценка
    if st.msg and now - st.msgT < 0.8 then
        local a = 255 * math.Clamp(1 - (now - st.msgT) / 0.8, 0, 1)
        draw.SimpleText(st.msg, "RemCPR_Text", cx, by + S(64), Color(st.msgCol.r, st.msgCol.g, st.msgCol.b, a), TEXT_ALIGN_CENTER)
    end

    -- средняя точность
    local avg = st.qN > 0 and st.qSum / st.qN or 0
    draw.SimpleText(("ТОЧНОСТЬ %d%%"):format(avg * 100), "RemCPR_Text", bx + S(12), by + bh - S(30), avg > 0.7 and C_GREEN or (avg > 0.4 and C_YEL or C_RED))
    draw.SimpleText(("%d/мин"):format(CPR.BPM), "RemCPR_Text", bx + bw - S(12), by + bh - S(30), C_DIM, TEXT_ALIGN_RIGHT)

    local hint = st.phase == "comp" and "ПРОБЕЛ в такт - компрессия   (ЛКМ держать на груди)" or "держи ПРОБЕЛ ~1 сек - вдох"
    draw.SimpleText(hint, "RemCPR_Text", cx, by + bh + S(8), Color(200, 200, 200, 180), TEXT_ALIGN_CENTER)
end)
