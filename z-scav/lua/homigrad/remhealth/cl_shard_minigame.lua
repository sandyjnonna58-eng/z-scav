--[[
    Z-SCAV: мини-игра извлечения осколка (клиент).

    Чёрная панель, внизу кожа. Из кожи торчит осколок (белый контур, окровавленная часть внутри).
    Держи ЛКМ (схватил осколок) и медленно тяни мышь ВВЕРХ.
      * тянешь медленно и ровно - осколок выходит чисто
      * дёргаешь (быстро) - копится "разрыв"; заполнился - мышца рвётся: сильное кровотечение
      * водишь вбок - больно, тоже рвёт
    ПКМ/ESC - бросить (осколок остаётся в теле).
]]

local MG = {
    active = false,
    SENS       = 0.5,
    SAFE_SPEED = 70,    -- пикс/сек вытягивания без вреда
    TEAR_RATE  = 0.012, -- разрыв за каждый пикс/сек сверх SAFE (в секунду)
    SIDE_TEAR  = 0.004, -- разрыв от бокового движения
    TEAR_HEAL  = 0.25,  -- разрыв "остывает", если тянуть спокойно
    TIMEOUT    = 30,
}
hg.RemShardMGClient = MG

local SHARD_W, SHARD_H = 125, 683
local matShard = Material("vgui/remhealth/shard.png", "smooth")

local C_WHITE = Color(235, 235, 235)
local C_DIM   = Color(150, 160, 180)
local C_GREEN = Color(80, 255, 150)
local C_YEL   = Color(255, 220, 80)
local C_RED   = Color(255, 70, 60)

local function S(v) return math.floor(v * ScrH() / 1080 + 0.5) end
local function Fonts()
    surface.CreateFont("RemShard_Title", {font = "Courier New", size = S(26), weight = 900, antialias = false, extended = true})
    surface.CreateFont("RemShard_Text",  {font = "Courier New", size = S(18), weight = 900, antialias = false, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "RemShard_Fonts", Fonts)

local function Finish(result) -- 0 отмена, 1 чисто, 2 разорвал
    local st = MG.st
    MG.active, MG.st = false, nil
    MG.blockUntilRelease = true
    if not st then return end
    net.Start("rem_shard_mg_done")
        net.WriteUInt(st.id, 16)
        net.WriteUInt(result, 2)
    net.SendToServer()
    if result == 1 then
        MG.result = {text = "ОСКОЛОК ИЗВЛЕЧЁН", col = C_GREEN, t = RealTime()}
        surface.PlaySound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav")
    elseif result == 2 then
        MG.result = {text = "ВЫРВАЛ С МЯСОМ! КРОВОТЕЧЕНИЕ", col = C_RED, t = RealTime()}
        surface.PlaySound("physics/flesh/flesh_bloody_break.wav")
    end
end

net.Receive("rem_shard_mg", function()
    local id = net.ReadUInt(16)
    local name = net.ReadString()
    local depth = net.ReadFloat()  -- доля длины осколка под кожей
    local diff = net.ReadFloat()
    local ply = LocalPlayer()
    MG.st = {
        id = id, name = name, diff = diff, start = RealTime(),
        under = SHARD_H * depth,   -- сколько ещё внутри (пиксели картинки)
        total = SHARD_H * depth,
        xoff = 0, tear = 0, drops = {},
        lmb = input.IsMouseDown(MOUSE_LEFT), rmb = input.IsMouseDown(MOUSE_RIGHT),
        lockAng = IsValid(ply) and ply:EyeAngles() or Angle(),
    }
    MG.mdx, MG.mdy = 0, 0
    MG.active = true
    MG.result = nil
    if IsValid(hg.RemHealthPanel) then hg.RemHealthPanel:Close() end
end)

hook.Add("CreateMove", "RemShardMG", function(cmd)
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
    cmd:RemoveKey(IN_ATTACK) cmd:RemoveKey(IN_ATTACK2)
end)

hook.Add("Think", "RemShardMG", function()
    local st = MG.st
    if not MG.active or not st then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then Finish(0) return end
    local t, dt = RealTime(), math.max(RealFrameTime(), 0.001)
    if t - st.start > MG.TIMEOUT then Finish(0) return end

    local mdx, mdy = MG.mdx or 0, MG.mdy or 0
    MG.mdx, MG.mdy = 0, 0
    local lmb, rmb = input.IsMouseDown(MOUSE_LEFT), input.IsMouseDown(MOUSE_RIGHT)
    local rPressed = rmb and not st.rmb
    st.lmb, st.rmb = lmb, rmb
    if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end
    if rPressed then Finish(0) return end

    st.speed = 0
    if lmb then
        -- тянем вверх (мышь вверх = отрицательный Y)
        local pull = math.max(0, -mdy * MG.SENS)
        local side = math.abs(mdx * MG.SENS)
        -- дрожь руки
        st.xoff = math.Clamp(st.xoff + mdx * MG.SENS * 0.3 + math.sin(t * 9) * st.diff * 0.6, -25, 25)
        local speed = pull / dt
        st.speed = speed
        st.under = math.max(0, st.under - pull)

        if speed > MG.SAFE_SPEED then
            st.tear = st.tear + (speed - MG.SAFE_SPEED) * MG.TEAR_RATE * dt
        else
            st.tear = math.max(0, st.tear - MG.TEAR_HEAL * dt)
        end
        st.tear = st.tear + side * MG.SIDE_TEAR
        -- брызги крови при рывке
        if speed > MG.SAFE_SPEED * 1.3 and math.random() < 0.5 then
            st.drops[#st.drops + 1] = {x = math.Rand(-30, 30), y = 0, vy = math.Rand(-60, -20), vx = math.Rand(-40, 40), t = t}
        end

        if st.tear >= 1 then Finish(2) return end
        if st.under <= 0 then Finish(1) return end
    else
        st.xoff = st.xoff * (1 - math.min(dt * 4, 1))
    end

    for i = #st.drops, 1, -1 do
        local d = st.drops[i]
        d.vy = d.vy + 300 * dt
        d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
        if t - d.t > 1.2 then table.remove(st.drops, i) end
    end
end)

hook.Add("OnShowZCityPause", "RemShardMG_Esc", function()
    if MG.active then Finish(0) return false end
end)

hook.Add("HUDPaint", "RemShardMG", function()
    if MG.result and RealTime() - MG.result.t < 2 then
        local a = 255 * math.Clamp(2 - (RealTime() - MG.result.t), 0, 1)
        local c = MG.result.col
        draw.SimpleTextOutlined(MG.result.text, "RemShard_Title", ScrW() * 0.5, ScrH() * 0.62, Color(c.r, c.g, c.b, a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a))
    end
    local st = MG.st
    if not MG.active or not st then return end

    local pw, ph = S(700), S(640)
    local bx, by = (ScrW() - pw) * 0.5, (ScrH() - ph) * 0.5
    surface.SetDrawColor(0, 0, 0, 245) surface.DrawRect(bx, by, pw, ph)
    draw.SimpleText("Держи ЛКМ и МЕДЛЕННО тяни осколок вверх.", "RemShard_Text", bx + S(16), by + S(12), C_WHITE)
    draw.SimpleText("ОСКОЛОК: " .. st.name, "RemShard_Text", bx + S(16), by + S(36), C_DIM)

    local k = S(100) / 100 * 0.75
    local skinY = by + ph * 0.62
    local cx = bx + pw * 0.5 + st.xoff * k
    local sw, sh = SHARD_W * k, SHARD_H * k
    -- верх картинки: кожа на высоте (SHARD_H - under) от верха осколка
    local topY = skinY - (SHARD_H - st.under) * k

    render.SetScissorRect(bx, by, bx + pw, by + ph, true)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(matShard)
    surface.DrawTexturedRect(cx - sw * 0.5, topY, sw, sh)
    -- под кожей: плоть закрывает осколок (едва виден)
    surface.SetDrawColor(0, 0, 0, 215)
    surface.DrawRect(bx, skinY, pw, by + ph - skinY)
    -- кожа с "проколом"
    surface.SetDrawColor(C_WHITE)
    surface.DrawRect(bx, skinY, cx - sw * 0.6 - bx, math.max(2, S(3)))
    surface.DrawRect(cx + sw * 0.6, skinY, bx + pw - cx - sw * 0.6, math.max(2, S(3)))
    -- кровь у раны
    surface.SetDrawColor(200, 20, 20, 255)
    surface.DrawRect(cx - sw * 0.6, skinY, sw * 1.2, S(4) + st.tear * S(10))
    for _, d in ipairs(st.drops) do
        surface.DrawRect(cx + d.x * k - S(2), skinY + d.y * k - S(2), S(5), S(5))
    end
    render.SetScissorRect(0, 0, 0, 0, false)

    -- шкалы
    local out = 1 - st.under / math.max(st.total, 1)
    local barX, barW = bx + S(16), pw - S(32)
    local y1 = by + ph - S(84)
    surface.SetDrawColor(C_DIM) surface.DrawOutlinedRect(barX, y1, barW, S(16), 1)
    surface.SetDrawColor(C_GREEN) surface.DrawRect(barX + 2, y1 + 2, (barW - 4) * out, S(12))
    draw.SimpleText(("ИЗВЛЕЧЕНО %d%%"):format(out * 100), "RemShard_Text", barX, y1 - S(22), C_WHITE)
    local y2 = by + ph - S(46)
    surface.SetDrawColor(C_DIM) surface.DrawOutlinedRect(barX, y2, barW, S(16), 1)
    local tc = st.tear > 0.66 and C_RED or (st.tear > 0.33 and C_YEL or C_GREEN)
    surface.SetDrawColor(tc) surface.DrawRect(barX + 2, y2 + 2, (barW - 4) * math.Clamp(st.tear, 0, 1), S(12))
    local status = (st.speed or 0) > MG.SAFE_SPEED and "МЕДЛЕННЕЕ!" or (st.lmb and "ТЯНИ..." or "ДЕРЖИ ЛКМ")
    draw.SimpleText("РАЗРЫВ ТКАНЕЙ   " .. status, "RemShard_Text", barX, y2 - S(22), (st.speed or 0) > MG.SAFE_SPEED and C_RED or C_DIM)

    draw.SimpleText("ЛКМ (держать) + мышь вверх - тянуть   ПКМ/ESC - бросить", "RemShard_Text", bx + pw * 0.5, by + ph + S(8), Color(200, 200, 200, 160), TEXT_ALIGN_CENTER)
end)
