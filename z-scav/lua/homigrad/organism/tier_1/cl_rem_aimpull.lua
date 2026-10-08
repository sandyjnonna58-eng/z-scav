--[[
    Z-SCAV: отчаяние - ствол сам тянется к случайному игроку.
    Прицел медленно (и всё сильнее) поворачивает к цели. Мышью нужно отводить его в сторону.
    Если к концу времени ствол всё ещё смотрит на человека (или держится на нём полсекунды) -
    палец жмёт на спуск. Отвёл дальше RESIST градусов к концу - отпустило.
]]

local CFG = {
    PULL_START = 25,   -- градусов/сек тяги в начале
    PULL_END   = 70,   -- к концу
    FIRE_ANGLE = 6,    -- ствол на цели (градусов)
    FIRE_HOLD  = 0.5,  -- сколько продержаться на цели до выстрела
    RESIST     = 25,   -- отвёл дальше - отпустило
}

local st = nil -- {target, start, dur, onT, fireUntil}

net.Receive("zscav_aimpull", function()
    local target = net.ReadEntity()
    local dur = net.ReadFloat()
    if not IsValid(target) then return end
    st = {target = target, start = CurTime(), dur = dur}
end)

local function AngleTo(ply, target)
    local dir = (target:WorldSpaceCenter() + Vector(0, 0, 12) - ply:EyePos()):GetNormalized()
    return dir:Angle()
end

hook.Add("CreateMove", "ZSCAV_AimPull", function(cmd)
    if not st then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or not IsValid(st.target) or not st.target:Alive() then st = nil return end

    local now = CurTime()
    if st.fireUntil then
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
        if now >= st.fireUntil then st = nil end
        return
    end

    local t = math.Clamp((now - st.start) / st.dur, 0, 1)
    local ang = cmd:GetViewAngles()
    local want = AngleTo(ply, st.target)
    local dp = math.NormalizeAngle(want.p - ang.p)
    local dy = math.NormalizeAngle(want.y - ang.y)
    local off = math.sqrt(dp * dp + dy * dy)

    -- тяга к цели (мышь игрока работает против неё)
    local step = Lerp(t, CFG.PULL_START, CFG.PULL_END) * FrameTime()
    if off > 0.01 then
        local k = math.min(step / off, 1)
        ang.p = ang.p + dp * k
        ang.y = ang.y + dy * k
        cmd:SetViewAngles(ang)
    end

    -- держится на цели - выстрел
    if off <= CFG.FIRE_ANGLE then
        st.onT = st.onT or now
        if now - st.onT >= CFG.FIRE_HOLD then st.fireUntil = now + 0.15 return end
    else
        st.onT = nil
    end

    if t >= 1 then
        if off <= CFG.RESIST then
            st.fireUntil = now + 0.15
        else
            st = nil -- отвёл, отпустило
            chat.AddText(Color(150, 170, 200), "...отпустило.")
        end
    end
end)

hook.Add("HUDPaint", "ZSCAV_AimPull", function()
    if not st or st.fireUntil then return end
    local w, h = ScrW(), ScrH()
    local t = math.Clamp((CurTime() - st.start) / st.dur, 0, 1)
    local pulse = 0.5 + 0.5 * math.sin(CurTime() * 8)
    surface.SetDrawColor(120, 0, 0, (60 + 80 * t) * (0.7 + 0.3 * pulse))
    local s = math.floor(h * 0.25)
    surface.SetTexture(surface.GetTextureID("vgui/gradient-u")) surface.DrawTexturedRect(0, h - s, w, s)
    surface.SetTexture(surface.GetTextureID("vgui/gradient-d")) surface.DrawTexturedRect(0, 0, w, s)
    draw.SimpleTextOutlined("ОТВЕДИ ПРИЦЕЛ!", "DermaLarge", w * 0.5, h * 0.72, Color(255, 80, 70, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 230))
    surface.SetDrawColor(255, 80, 70, 200)
    surface.DrawRect(w * 0.5 - 150, h * 0.72 + 26, 300 * (1 - t), 6)
end)
