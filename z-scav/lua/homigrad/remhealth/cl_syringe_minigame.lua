--[[
    REM: мини-игра укола шприцем (клиент).

    1) ПРИЦЕЛ. На кукле подсвечено место укола. Мышкой ведём иглу (рука дрожит),
       ЛКМ - уколоть. Мимо - больно.
    2) ВВОД. Игла в мышце. Держим ЛКМ - поршень идёт. Мышкой влево/вправо
       выравниваем угол иглы: в зелёной зоне лекарство вводится, в жёлтой - стоит и рвёт мышцу,
       в красной дольше мгновения - игла ломается.
    ПКМ - вытащить иглу/отменить.
]]

local MG = {
    active = false,
    TIMEOUT    = 30,
    AIM_SENS   = 0.4,   -- пикселей куклы на единицу движения мыши
    ANGLE_SENS = 0.12,  -- градусов на единицу движения мыши
    SAFE       = 14,    -- ± градусов от 90, где вводится
    BREAK      = 32,    -- ± градусов, где ломается
    BREAK_TIME = 0.35,  -- сколько можно продержаться в красной зоне
}
hg.RemSyringeMGClient = MG

-- "физический" шприц (как в Casualties: Unknown, но рука человеческая): морфин и фентанил
MG.PHYS_CLASSES = {weapon_morphine = true, weapon_fentanyl = true}
MG.PHYS = {
    SENS        = 0.55, -- движение руки от мыши
    SAFE        = 9,    -- град наклона, при котором вводится
    BEND        = 9,    -- 9..BREAK - игла гнётся, рвёт мышцу
    BREAK       = 22,   -- больше - игла ломается
    BREAK_TIME  = 0.22,
    INSERT_MAX  = 25,   -- под каким максимальным углом игла вообще входит в кожу
    MIN_DEPTH   = 25,   -- сколько иглы должно войти, чтобы вводить
    -- геометрия в пикселях картинки руки (1024x512, хват в центре)
    BARREL_TOP  = -200, BARREL_BOT = 150, BARREL_HW = 24,
    NEEDLE_LEN  = 100,  -- от низа цилиндра
}
local matHand = Material("vgui/remhealth/inject_hand.png", "smooth")

local DOLL_W, DOLL_H = 572, 889
local matDoll    = Material("vgui/remhealth/doll.png", "smooth")
local matOutline = Material("vgui/remhealth/outline.png", "smooth")

-- места укола: центр в пикселях куклы (совпадает с порядком MG.sites на сервере)
local SITES = {
    {id = "r_thigh",    name = "ПРАВОЕ БЕДРО", x = 251, y = 545},
    {id = "l_thigh",    name = "ЛЕВОЕ БЕДРО",  x = 322, y = 545},
    {id = "r_upperarm", name = "ПРАВОЕ ПЛЕЧО", x = 196, y = 300},
    {id = "l_upperarm", name = "ЛЕВОЕ ПЛЕЧО",  x = 377, y = 300},
}
for _, s in ipairs(SITES) do s.mat = Material("vgui/remhealth/part_" .. s.id .. ".png", "smooth") end

local C_BG    = Color(20, 36, 28, 235)
local C_GREEN = Color(80, 255, 150)
local C_DIM   = Color(40, 140, 85)
local C_DARK  = Color(25, 70, 45)
local C_YEL   = Color(255, 220, 80)
local C_RED   = Color(255, 70, 60)
local C_WHITE = Color(235, 235, 225)

local function S(v) return math.floor(v * ScrH() / 1080 + 0.5) end

local function Send(state, extra)
    net.Start("rem_syringe_mg_state")
        net.WriteUInt(state, 3)
        net.WriteUInt(math.Clamp(math.floor(extra or 0), 0, 15), 4)
    net.SendToServer()
end

local function Stop(resultText, resultCol, sendState)
    if sendState then Send(sendState, 0) end
    MG.active = false
    MG.st = nil
    MG.blockUntilRelease = true
    if resultText then MG.result = {text = resultText, col = resultCol, t = RealTime()} end
end

net.Receive("rem_syringe_mg", function()
    local wep = net.ReadEntity()
    local drug = net.ReadString()
    local site = net.ReadUInt(3)
    local diff = net.ReadFloat()
    local ply = LocalPlayer()
    MG.st = {
        wep = wep, drug = drug, site = SITES[site] or SITES[1], diff = diff,
        phase = "aim", start = RealTime(), misses = 0,
        cx = DOLL_W * 0.5, cy = 420,   -- игла начинает у живота
        angle = 90, angVel = 0, bend = 0, redTime = 0, sent = 2,
        lmb = input.IsMouseDown(MOUSE_LEFT), rmb = input.IsMouseDown(MOUSE_RIGHT),
        lockAng = IsValid(ply) and ply:EyeAngles() or Angle(),
    }
    if IsValid(wep) and MG.PHYS_CLASSES[wep:GetClass()] then
        local st = MG.st
        st.phase = "phys"
        st.hx, st.hy = 0, -330          -- точка хвата относительно места укола (игла над кожей)
        st.th, st.om, st.vx = 0, 0, 0   -- наклон (рад), угловая скорость, скорость руки
        st.inserted = false
        st.red = 0
    end
    MG.mdx, MG.mdy = 0, 0
    MG.active = true
    MG.result = nil
end)

-- ---------------------------------------------------------------------------
-- физический шприц
-- ---------------------------------------------------------------------------
local function PhysTip(st)
    local P = MG.PHYS
    local L = P.BARREL_BOT + P.NEEDLE_LEN
    return st.hx + math.sin(st.th) * L, st.hy + math.cos(st.th) * L
end

local function PhysThink(st, t, dt, mdx, mdy, lmb)
    local P = MG.PHYS
    local L = P.BARREL_BOT + P.NEEDLE_LEN
    local shake = 0.6 + st.diff * 2.5

    if st.phase == "phys_broken" then
        if t - st.brokenT > 1.6 then Stop(nil) end
        return
    end

    local px = st.hx
    st.hx = math.Clamp(st.hx + mdx * P.SENS + math.sin(t * 7.3) * shake * 0.4, -380, 380)
    st.hy = math.Clamp(st.hy + mdy * P.SENS + math.cos(t * 6.1) * shake * 0.3, -520, 0)
    local vx = (st.hx - px) / math.max(dt, 0.001)
    local ax = (vx - st.vx) / math.max(dt, 0.001)
    st.vx = vx

    if not st.inserted then
        -- шприц в руке как маятник: резкое движение - качнётся
        st.om = st.om + (-60 * st.th - 9 * st.om - ax * 0.00045 + math.Rand(-1, 1) * shake * 0.6) * dt
        st.th = math.Clamp(st.th + st.om * dt, -0.8, 0.8)

        local tx, ty = PhysTip(st)
        if ty >= 0 then
            if math.abs(math.deg(st.th)) <= P.INSERT_MAX then
                st.inserted = true
                st.pivot = tx
                Send(0, 0)
                surface.PlaySound("snd_jack_hmcd_needleprick.wav")
            else
                -- слишком наискосок - царапнул кожу, рука отскочила
                st.hy = st.hy - 40
                st.misses = st.misses + 1
                Send(2, 2)
                surface.PlaySound("physics/flesh/flesh_impact_bullet" .. math.random(1, 3) .. ".wav")
            end
        end
        return
    end

    -- игла в коже: шприц вращается вокруг точки входа, наклон задаёт рука
    local dx, dy = st.pivot - st.hx, -st.hy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > L + 4 then
        -- вытащил иглу
        st.inserted = false
        st.th = math.atan2(dx, dy)
        if st.sent ~= 2 then st.sent = 2 Send(2, 0) end
        return
    end
    -- глубже, чем вся игла, не пускает цилиндр
    local minDist = P.BARREL_BOT + 4
    if dist < minDist then
        local k = minDist / math.max(dist, 1)
        st.hx = st.pivot - dx * k
        st.hy = -dy * k
        dx, dy, dist = st.pivot - st.hx, -st.hy, minDist
    end
    st.th = math.atan2(dx, dy)
    st.depth = L - dist

    local deg = math.abs(math.deg(st.th))
    if deg >= P.BREAK then
        st.red = st.red + dt
        if st.red >= P.BREAK_TIME then
            Send(3, 0)
            st.phase, st.brokenT = "phys_broken", t
            MG.blockUntilRelease = true
            MG.result = {text = "ИГЛА СЛОМАЛАСЬ! КРОВОТЕЧЕНИЕ", col = C_RED, t = t}
            surface.PlaySound("physics/glass/glass_bottle_break" .. math.random(1, 2) .. ".wav")
            return
        end
    else
        st.red = math.max(0, st.red - dt * 2)
    end

    local ok = deg <= P.SAFE and (st.depth or 0) >= P.MIN_DEPTH
    if lmb and not ok and deg > P.BEND then st.bend = st.bend + dt end
    local state = (lmb and ok) and 1 or 2
    if state ~= st.sent then
        st.sent = state
        Send(state, state == 2 and st.bend * 3 or 0)
        if state == 2 then st.bend = 0 end
    end
end

-- мышь управляет иглой, камера стоит; атаки глушим
hook.Add("CreateMove", "RemSyringeMG", function(cmd)
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

hook.Add("Think", "RemSyringeMG", function()
    local st = MG.st
    if not MG.active or not st then return end
    local ply = LocalPlayer()
    local t, dt = RealTime(), RealFrameTime()

    -- после поломки иглы шприц уже удалён сервером - просто доигрываем анимацию крови
    if st.phase == "phys_broken" then
        if t - st.brokenT > 1.6 then Stop(nil) end
        return
    end

    if not IsValid(ply) or not ply:Alive() or not IsValid(st.wep) or ply:GetActiveWeapon() ~= st.wep then
        -- шприц кончился и пропал - значит ввели
        if (st.phase == "inject" or (st.phase == "phys" and st.inserted)) and IsValid(ply) and ply:Alive() then
            Stop("ВВЕДЕНО: " .. st.drug, C_GREEN, 4)
        else
            Stop(nil, nil, 4)
        end
        return
    end
    if t - st.start > MG.TIMEOUT then Stop("ВРЕМЯ ВЫШЛО", C_YEL, 4) return end

    local mdx, mdy = MG.mdx or 0, MG.mdy or 0
    MG.mdx, MG.mdy = 0, 0

    local lmb, rmb = input.IsMouseDown(MOUSE_LEFT), input.IsMouseDown(MOUSE_RIGHT)
    local lPressed, rPressed = lmb and not st.lmb, rmb and not st.rmb
    st.lmb, st.rmb = lmb, rmb
    if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end

    if rPressed then
        if st.phase == "phys_broken" then return end
        Stop((st.phase == "inject" or st.inserted) and "ИГЛА ВЫНУТА" or "ОТМЕНА", C_DIM, 4)
        return
    end

    if st.phase == "phys" or st.phase == "phys_broken" then
        if st.phase == "phys" and st.inserted and st.wep.modeValues and (st.wep.modeValues[1] or 0) <= 0 then
            Stop("ВВЕДЕНО: " .. st.drug, C_GREEN, 4)
            return
        end
        PhysThink(st, t, dt, mdx, mdy, lmb)
        return
    end

    if st.phase == "aim" then
        st.cx = math.Clamp(st.cx + mdx * MG.AIM_SENS, 0, DOLL_W)
        st.cy = math.Clamp(st.cy + mdy * MG.AIM_SENS, 0, DOLL_H)
        -- дрожь руки
        local amp = 4 + st.diff * 22
        st.sx = math.sin(t * 2.3) * amp + math.sin(t * 5.1 + 1) * amp * 0.4
        st.sy = math.cos(t * 1.9) * amp + math.sin(t * 4.3 + 2) * amp * 0.4

        if lPressed then
            local px, py = st.cx + st.sx, st.cy + st.sy
            local r = 26 - st.diff * 10
            if (px - st.site.x) ^ 2 + (py - st.site.y) ^ 2 <= r * r then
                st.phase = "inject"
                st.angle = 90 + math.Rand(-6, 6)
                Send(0, st.misses)
                surface.PlaySound("snd_jack_hmcd_needleprick.wav")
            else
                st.misses = st.misses + 1
                st.flash = t
                surface.PlaySound("physics/flesh/flesh_impact_bullet" .. math.random(1, 3) .. ".wav")
                if st.misses >= 4 then
                    Send(0, st.misses) -- боль за промахи
                    Stop("НЕ ПОПАЛ", C_RED, 4)
                end
            end
        end
        return
    end

    -- лекарство кончилось - готово
    if st.wep.modeValues and (st.wep.modeValues[1] or 0) <= 0 then
        Stop("ВВЕДЕНО: " .. st.drug, C_GREEN, 4)
        return
    end

    -- ВВОД: угол сам "гуляет", мышь выравнивает
    local push = (math.sin(t * 1.3) * 7 + math.sin(t * 3.7 + 0.5) * 4) * (0.6 + st.diff * 1.2)
    st.angVel = st.angVel + (push + math.Rand(-1, 1) * 30 * (0.5 + st.diff)) * dt
    st.angVel = st.angVel * math.exp(-1.5 * dt)
    st.angle = st.angle + st.angVel * dt * 4 + mdx * MG.ANGLE_SENS
    st.angle = math.Clamp(st.angle, 40, 140)

    local safe = MG.SAFE - st.diff * 5
    local off = math.abs(st.angle - 90)

    if off >= MG.BREAK then
        st.redTime = st.redTime + dt
        if st.redTime >= MG.BREAK_TIME then
            Send(3, 0)
            Stop("ИГЛА СЛОМАЛАСЬ!", C_RED)
            surface.PlaySound("physics/glass/glass_bottle_break" .. math.random(1, 2) .. ".wav")
            return
        end
    else
        st.redTime = math.max(0, st.redTime - dt * 2)
    end

    local wantInject = lmb and off <= safe
    if lmb and off > safe then st.bend = st.bend + dt end

    local state = wantInject and 1 or 2
    if state ~= st.sent then
        st.sent = state
        Send(state, state == 2 and st.bend * 3 or 0)
        if state == 2 then st.bend = 0 end
    end
end)

-- ---------------------------------------------------------------------------
-- рисование
-- ---------------------------------------------------------------------------
local function Fonts()
    surface.CreateFont("RemSMG_Title", {font = "Courier New", size = S(26), weight = 900, antialias = false, extended = true})
    surface.CreateFont("RemSMG_Text",  {font = "Courier New", size = S(18), weight = 900, antialias = false, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "RemSMG_Fonts", Fonts)

local function Box(x, y, w, h)
    surface.SetDrawColor(C_BG) surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(C_DIM) surface.DrawOutlinedRect(x, y, w, h, 2)
end

local function ThickLine(x1, y1, x2, y2, th, col)
    surface.SetDrawColor(col)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local nx, ny = -dy / len, dx / len
    for i = -math.floor(th / 2), math.floor(th / 2) do
        surface.DrawLine(x1 + nx * i, y1 + ny * i, x2 + nx * i, y2 + ny * i)
    end
end

local function DrawAim(st)
    local h = S(520)
    local w = h * DOLL_W / DOLL_H
    local bw, bh = w + S(80), h + S(110)
    local bx, by = (ScrW() - bw) * 0.5, (ScrH() - bh) * 0.5
    Box(bx, by, bw, bh)
    draw.SimpleText("УКОЛ: " .. st.drug, "RemSMG_Title", ScrW() * 0.5, by + S(8), C_GREEN, TEXT_ALIGN_CENTER)
    draw.SimpleText("ЦЕЛЬ: " .. st.site.name, "RemSMG_Text", ScrW() * 0.5, by + S(38), C_WHITE, TEXT_ALIGN_CENTER)

    local dx, dy = (ScrW() - w) * 0.5, by + S(70)
    local k = w / DOLL_W
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(matOutline) surface.DrawTexturedRect(dx, dy, w, h)
    surface.SetMaterial(matDoll)    surface.DrawTexturedRect(dx, dy, w, h)
    local pulse = 0.5 + 0.5 * math.sin(RealTime() * 5)
    surface.SetDrawColor(80, 255, 150, 60 + 80 * pulse)
    surface.SetMaterial(st.site.mat) surface.DrawTexturedRect(dx, dy, w, h)

    -- точка укола
    local r = (26 - st.diff * 10) * k
    local tx, ty = dx + st.site.x * k, dy + st.site.y * k
    surface.DrawCircle(tx, ty, r, 80, 255, 150, 255)
    surface.DrawCircle(tx, ty, math.max(2, r * 0.25), 235, 235, 225, 255)

    -- игла (с дрожью)
    local nx, ny = dx + (st.cx + (st.sx or 0)) * k, dy + (st.cy + (st.sy or 0)) * k
    local flash = st.flash and math.Clamp(1 - (RealTime() - st.flash) / 0.25, 0, 1) or 0
    local col = flash > 0 and C_RED or C_WHITE
    ThickLine(nx, ny, nx + S(26), ny - S(26), S(3), col)
    ThickLine(nx + S(26), ny - S(26), nx + S(60), ny - S(60), S(9), Color(200, 220, 255))
    surface.DrawCircle(nx, ny, S(3), col.r, col.g, col.b, 255)

    draw.SimpleText(("ПРОМАХИ %d/4"):format(st.misses), "RemSMG_Text", bx + bw - S(12), by + bh - S(30), st.misses > 0 and C_RED or C_DIM, TEXT_ALIGN_RIGHT)
    draw.SimpleText("МЫШЬ - вести иглу   ЛКМ - уколоть   ПКМ - отмена", "RemSMG_Text", ScrW() * 0.5, by + bh + S(8), Color(200, 200, 200, 180), TEXT_ALIGN_CENTER)
end

local function DrawInject(st)
    local bw, bh = S(460), S(420)
    local bx, by = (ScrW() - bw) * 0.5, (ScrH() - bh) * 0.5
    Box(bx, by, bw, bh)
    draw.SimpleText("ВВОД: " .. st.drug, "RemSMG_Title", ScrW() * 0.5, by + S(8), C_GREEN, TEXT_ALIGN_CENTER)
    draw.SimpleText(st.site.name, "RemSMG_Text", ScrW() * 0.5, by + S(38), C_WHITE, TEXT_ALIGN_CENTER)

    -- разрез кожи: точка входа иглы
    local px, py = ScrW() * 0.5, by + S(270)
    surface.SetDrawColor(120, 60, 60, 255) surface.DrawRect(bx + S(10), py, bw - S(20), S(60))   -- мышца
    surface.SetDrawColor(200, 160, 130, 255) surface.DrawRect(bx + S(10), py - S(8), bw - S(20), S(8)) -- кожа

    -- зоны угла (дуга над точкой входа)
    local R = S(150)
    local safe = MG.SAFE - st.diff * 5
    local function arc(a1, a2, col)
        surface.SetDrawColor(col)
        for a = a1, a2 - 2, 2 do
            local r1, r2 = math.rad(a), math.rad(a + 2)
            for tt = 0, S(8) do
                local rr = R + tt
                surface.DrawLine(px - math.cos(r1) * rr, py - math.sin(r1) * rr, px - math.cos(r2) * rr, py - math.sin(r2) * rr)
            end
        end
    end
    arc(90 - 50, 90 - MG.BREAK, C_RED) arc(90 + MG.BREAK, 90 + 50, C_RED)
    arc(90 - MG.BREAK, 90 - safe, C_YEL) arc(90 + safe, 90 + MG.BREAK, C_YEL)
    arc(90 - safe, 90 + safe, C_GREEN)

    -- шприц
    local a = math.rad(st.angle)
    local ux, uy = -math.cos(a), -math.sin(a)
    local tipX, tipY = px - ux * S(30), py - uy * S(30)          -- кончик в мышце
    local hubX, hubY = px + ux * S(60), py + uy * S(60)
    local endX, endY = px + ux * S(140), py + uy * S(140)
    local off = math.abs(st.angle - 90)
    local needleCol = off >= MG.BREAK and C_RED or (off > safe and C_YEL or C_WHITE)
    ThickLine(tipX, tipY, hubX, hubY, S(3), needleCol)
    ThickLine(hubX, hubY, endX, endY, S(16), Color(200, 220, 255, 230))
    -- поршень по остатку лекарства
    local frac = 1
    if IsValid(st.wep) and st.wep.modeValues and st.wep.modeValuesdef and st.wep.modeValuesdef[1] then
        frac = math.Clamp((st.wep.modeValues[1] or 0) / (st.wep.modeValuesdef[1][1] or 1), 0, 1)
    end
    local plX, plY = hubX + (endX - hubX) * (1 - frac), hubY + (endY - hubY) * (1 - frac)
    ThickLine(plX, plY, endX + ux * S(20), endY + uy * S(20), S(6), C_DIM)

    -- прогресс
    local barX, barY, barW, barH = bx + S(20), by + bh - S(70), bw - S(40), S(20)
    surface.SetDrawColor(C_GREEN) surface.DrawOutlinedRect(barX, barY, barW, barH, 2)
    surface.SetDrawColor(C_DARK) surface.DrawRect(barX + 3, barY + 3, barW - 6, barH - 6)
    surface.SetDrawColor(C_GREEN) surface.DrawRect(barX + 3, barY + 3, (barW - 6) * (1 - frac), barH - 6)
    local status = (st.redTime or 0) > 0 and "ИГЛА ГНЁТСЯ!" or (st.lmb and (off <= safe and "ВВОД..." or "ВЫРОВНЯЙ УГОЛ") or "ДЕРЖИ ЛКМ")
    local scol = (st.redTime or 0) > 0 and C_RED or (st.lmb and off <= safe and C_GREEN or C_YEL)
    draw.SimpleText(status, "RemSMG_Text", ScrW() * 0.5, barY - S(26), scol, TEXT_ALIGN_CENTER)

    draw.SimpleText("ЛКМ (держать) - ввод   МЫШЬ ←→ - угол   ПКМ - вынуть", "RemSMG_Text", ScrW() * 0.5, by + bh + S(8), Color(200, 200, 200, 180), TEXT_ALIGN_CENTER)
end

local function DrawPhys(st)
    local P = MG.PHYS
    local pw, ph = S(900), S(640)
    local bx, by = (ScrW() - pw) * 0.5, (ScrH() - ph) * 0.5
    -- чёрная панель с мягкими краями
    surface.SetDrawColor(0, 0, 0, 245) surface.DrawRect(bx, by, pw, ph)
    draw.SimpleText("Опусти шприц, чтобы ввести иглу. Держи ЛКМ - ввод. Следи за дозой.", "RemSMG_Text", bx + S(16), by + S(12), C_WHITE)
    draw.SimpleText("УКОЛ: " .. st.drug, "RemSMG_Text", bx + S(16), by + S(36), Color(160, 170, 190))

    local k = S(100) / 100 * 0.62          -- пиксели картинки -> экран
    local ox, oy = bx + pw * 0.42, by + ph * 0.82 -- место укола (линия кожи)
    local gx, gy = ox + st.hx * k, oy + st.hy * k
    local th = st.th
    local c, sn = math.cos(th), math.sin(th)
    local function R(lx, ly) return gx + (lx * c + ly * sn) * k, gy + (-lx * sn + ly * c) * k end

    render.SetScissorRect(bx, by, bx + pw, by + ph, true)

    -- кожа
    surface.SetDrawColor(235, 235, 235, 255)
    surface.DrawRect(bx, oy, pw, math.max(2, S(3)))

    -- рука (картинка 1024x512, хват в центре), вращается вместе со шприцем
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(matHand)
    surface.DrawTexturedRectRotated(gx, gy, 1024 * k, 512 * k, math.deg(th))

    -- шприц
    local deg = math.abs(math.deg(th))
    local needleCol = deg >= P.BREAK and C_RED or (deg > P.SAFE and st.inserted and C_YEL or Color(235, 235, 235))
    local hw = P.BARREL_HW
    local function L2(x1, y1, x2, y2, col, th2)
        local ax, ay = R(x1, y1) local bx2, by2 = R(x2, y2)
        surface.SetDrawColor(col)
        for i = 0, (th2 or 1) - 1 do surface.DrawLine(ax + i, ay, bx2 + i, by2) end
    end
    -- предплечье продолжается за край картинки до края панели
    L2(510, -70, 1500, -60, Color(255, 255, 255), 2)
    L2(510, 118, 1500, 126, Color(255, 255, 255), 2)

    local frac = 1
    if IsValid(st.wep) and st.wep.modeValues and st.wep.modeValuesdef and st.wep.modeValuesdef[1] then
        frac = math.Clamp((st.wep.modeValues[1] or 0) / (st.wep.modeValuesdef[1][1] or 1), 0, 1)
    end
    local top, bot = P.BARREL_TOP, P.BARREL_BOT
    -- лекарство в цилиндре (доза)
    local liqTop = bot - (bot - top - 30) * frac
    for y = liqTop, bot - 4, 6 do L2(-hw + 5, y, hw - 5, y, Color(140, 170, 220, 110), 1) end
    -- цилиндр
    local barrelCol = Color(190, 190, 190)
    L2(-hw, top, -hw, bot, barrelCol, 2) L2(hw, top, hw, bot, barrelCol, 2)
    L2(-hw, bot, hw, bot, barrelCol, 2)
    L2(-hw - 10, top, hw + 10, top, barrelCol, 2) -- упор для пальцев
    -- деления дозы
    for i = 0, 8 do
        local y = bot - 20 - i * ((bot - top - 40) / 8)
        L2(-hw, y, -hw + (i % 2 == 0 and 16 or 9), y, barrelCol, 1)
    end
    -- поршень: опускается по мере ввода
    local plY = liqTop - 4
    L2(-hw + 4, plY, hw - 4, plY, Color(230, 230, 230), 2)
    L2(0, plY, 0, top - 60, Color(220, 220, 220), 2)
    L2(-hw, top - 60, hw, top - 60, Color(220, 220, 220), 2)
    -- канюля и игла
    L2(-8, bot, -8, bot + 14, barrelCol, 1) L2(8, bot, 8, bot + 14, barrelCol, 1) L2(-8, bot + 14, 8, bot + 14, barrelCol, 1)
    if st.phase == "phys_broken" then
        -- обломок иглы торчит из кожи, кровь
        L2(0, bot + 14, 0, bot + 40, needleCol, 1)
        local age = RealTime() - st.brokenT
        surface.SetDrawColor(200, 20, 20, 255)
        for i = 1, 6 do
            local r = S(3) + math.min(age * S(10), S(14)) * (i / 6)
            surface.DrawRect(ox + (st.pivot or 0) * k - r + (i - 3) * S(5), oy - S(2), r * 2, S(3) + age * S(4) * (i % 3))
        end
    else
        L2(0, bot + 14, 0, bot + P.NEEDLE_LEN, needleCol, 1)
    end

    render.SetScissorRect(0, 0, 0, 0, false)

    -- подсказки
    local status, scol
    if st.phase == "phys_broken" then status, scol = "", C_RED
    elseif not st.inserted then status, scol = "ОПУСКАЙ ШПРИЦ РОВНО", C_WHITE
    elseif deg >= P.BREAK then status, scol = "ИГЛА ГНЁТСЯ!", C_RED
    elseif deg > P.SAFE then status, scol = "ВЫРОВНЯЙ ШПРИЦ", C_YEL
    elseif (st.depth or 0) < P.MIN_DEPTH then status, scol = "ГЛУБЖЕ", C_YEL
    else status, scol = st.lmb and "ВВОД..." or "ДЕРЖИ ЛКМ", C_GREEN end
    draw.SimpleText(status, "RemSMG_Title", bx + pw * 0.5, by + ph - S(46), scol, TEXT_ALIGN_CENTER)
    draw.SimpleText(("ДОЗА %d%%"):format(frac * 100), "RemSMG_Text", bx + pw - S(16), by + S(12), C_WHITE, TEXT_ALIGN_RIGHT)
    draw.SimpleText("ПКМ/ESC - выход", "RemSMG_Text", bx + pw * 0.5, by + ph + S(8), Color(200, 200, 200, 160), TEXT_ALIGN_CENTER)
end

hook.Add("OnShowZCityPause", "RemSyringeMG_Esc", function()
    local st = MG.st
    if MG.active and st then
        if st.phase ~= "phys_broken" then Stop((st.inserted or st.phase == "inject") and "ИГЛА ВЫНУТА" or "ОТМЕНА", C_DIM, 4) end
        return false
    end
end)

hook.Add("HUDPaint", "RemSyringeMG", function()
    if MG.result and RealTime() - MG.result.t < 2 then
        local a = 255 * math.Clamp(2 - (RealTime() - MG.result.t), 0, 1)
        local c = MG.result.col or C_GREEN
        draw.SimpleTextOutlined(MG.result.text, "RemSMG_Title", ScrW() * 0.5, ScrH() * 0.62, Color(c.r, c.g, c.b, a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a))
    end
    local st = MG.st
    if not MG.active or not st then return end
    if st.phase == "phys" or st.phase == "phys_broken" then DrawPhys(st)
    elseif st.phase == "aim" then DrawAim(st) else DrawInject(st) end
end)
