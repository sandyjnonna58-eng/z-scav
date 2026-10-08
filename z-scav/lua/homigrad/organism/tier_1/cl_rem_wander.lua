--[[
    Z-SCAV: "ушёл в себя" - ноги идут сами, взгляд уплывает. Сопротивляться можно:
    назад/в стороны ослабляют ходьбу, но не отменяют её полностью.
]]

local st = nil

net.Receive("zscav_wander", function()
    local dur = net.ReadFloat()
    local drift = net.ReadFloat()
    st = {start = CurTime(), dur = dur, drift = drift, seed = math.Rand(0, 100)}
end)

hook.Add("CreateMove", "ZSCAV_Wander", function(cmd)
    if not st then return end
    local ply = LocalPlayer()
    local now = CurTime()
    if not IsValid(ply) or not ply:Alive() or now - st.start > st.dur then st = nil return end

    local t = (now - st.start) / st.dur
    local fade = math.min(t * 4, 1, (1 - t) * 4) -- плавно в начале и в конце
    local speed = ply:GetWalkSpeed() * 0.9 * fade

    -- ноги идут сами; игрок может только ослабить
    local fwd = cmd:GetForwardMove()
    if fwd < 0 then speed = speed * 0.45 end              -- тянет назад - слабее
    cmd:SetForwardMove(math.max(fwd, 0) * 0.3 + speed)
    cmd:SetSideMove(cmd:GetSideMove() * 0.5 + math.sin(now * 0.9 + st.seed) * 40 * fade)
    cmd:RemoveKey(IN_SPEED) -- не бежит, а бредёт
    cmd:RemoveKey(IN_JUMP)

    -- взгляд уплывает
    local ang = cmd:GetViewAngles()
    ang.y = ang.y + (st.drift * 18 + math.sin(now * 0.7 + st.seed) * 10) * FrameTime() * fade
    ang.p = math.Approach(ang.p, 12, 6 * FrameTime() * fade) -- взгляд в пол
    cmd:SetViewAngles(ang)
end)

hook.Add("HUDPaint", "ZSCAV_Wander", function()
    if not st then return end
    local t = math.Clamp((CurTime() - st.start) / st.dur, 0, 1)
    local fade = math.min(t * 4, 1, (1 - t) * 4)
    local w, h = ScrW(), ScrH()
    surface.SetDrawColor(10, 12, 20, 110 * fade)
    surface.DrawRect(0, 0, w, h)
end)
