--[[
    Z-SCAV: болезни на экране.
    Проказа - зрение ухудшается, всё размывается (сильнее с развитием болезни).
    Бешенство - жар: лёгкое красноватое марево.
]]

local blur = Material("pp/blurscreen")

hook.Add("HUDPaintBackground", "ZSCAV_DiseaseFX", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local org = ply.organism
    -- Z-SCAV: высокое внутричерепное давление - всё плывёт
    local icp = org and tonumber(org.remICP) or 10
    if icp > 25 then
        local k = math.Clamp((icp - 25) / 20, 0, 1)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(blur)
        for i = 1, 2 do
            blur:SetFloat("$blur", (0.6 + k * 2.5) * i * (0.8 + 0.2 * math.sin(CurTime() * 1.3)))
            blur:Recompute()
            render.UpdateScreenEffectTexture()
            surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
        end
    end

    local dis = org and org.remDis
    if not istable(dis) then return end

    local lep = tonumber(dis.leprosy)
    if lep and lep > 0 then
        local k = math.Clamp((lep - 0.12) / 0.88, 0, 1) * 0.85 + 0.15
        local w, h = ScrW(), ScrH()
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(blur)
        for i = 1, 3 do
            blur:SetFloat("$blur", k * i * 1.6)
            blur:Recompute()
            render.UpdateScreenEffectTexture()
            surface.DrawTexturedRect(0, 0, w, h)
        end
    end

    local rab = tonumber(dis.rabies)
    if rab and rab > 0 then
        local a = 20 + 40 * math.Clamp(rab, 0, 1) * (0.7 + 0.3 * math.sin(CurTime() * 2))
        surface.SetDrawColor(120, 20, 0, a)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end
end)

-- ---------------------------------------------------------------------------
-- Докторская болезнь: очень редко экран темнеет и появляется белый контур трости (5 с).
-- Вручную: zscav_cane
-- ---------------------------------------------------------------------------
local caneStart = -100
local CANE_TIME = 5

local function ShowCane()
    caneStart = RealTime()
    surface.PlaySound("ambient/atmosphere/thunder1.wav")
end
net.Receive("zscav_cane", ShowCane)
concommand.Add("zscav_cane", ShowCane)

-- точки средней линии трости: прямой стержень и загнутая ручка сверху
local function CanePath(cx, cy, h)
    local pts = {}
    local r = h * 0.11                  -- радиус крюка
    local top = cy - h * 0.5 + r
    local bottom = cy + h * 0.5
    local sx = cx + r * 0.5             -- стержень
    for i = 0, 40 do pts[#pts + 1] = {sx, bottom - (bottom - top) * i / 40} end
    -- крюк: полукруг от верха стержня влево и чуть вниз
    local hx = sx - r
    for i = 1, 30 do
        local a = math.pi * i / 30      -- 0..pi
        pts[#pts + 1] = {hx + math.cos(a) * r, top - math.sin(a) * r}
    end
    for i = 1, 6 do pts[#pts + 1] = {hx - r, top + r * 0.12 * i} end -- кончик ручки
    return pts
end

local circ = {}
local function Disc(x, y, rad)
    local n = 12
    for i = 1, n do
        local a = (i - 1) / n * math.pi * 2
        circ[i] = circ[i] or {}
        circ[i].x, circ[i].y = x + math.cos(a) * rad, y + math.sin(a) * rad
    end
    surface.DrawPoly(circ)
end

hook.Add("HUDPaint", "ZSCAV_Cane", function()
    local t = RealTime() - caneStart
    if t < 0 or t > CANE_TIME then return end
    local a = math.min(t / 0.4, 1) * math.min((CANE_TIME - t) / 0.8, 1)
    local w, h = ScrW(), ScrH()
    surface.SetDrawColor(0, 0, 0, 250 * a)
    surface.DrawRect(0, 0, w, h)

    draw.NoTexture()
    local pts = CanePath(w * 0.5, h * 0.5, h * 0.62)
    local thick = math.max(6, h * 0.014)
    local line = math.max(2, math.floor(h / 360))
    -- контур: белая "толстая" линия, внутри - чёрная
    surface.SetDrawColor(255, 255, 255, 255 * a)
    for _, p in ipairs(pts) do Disc(p[1], p[2], thick + line) end
    surface.SetDrawColor(0, 0, 0, 255 * a)
    for _, p in ipairs(pts) do Disc(p[1], p[2], thick) end
end)
