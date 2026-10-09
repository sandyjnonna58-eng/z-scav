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
