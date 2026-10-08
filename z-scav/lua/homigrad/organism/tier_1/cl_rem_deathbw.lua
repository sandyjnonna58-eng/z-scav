--[[
    Z-SCAV: чёрно-белый экран смерти.
    После смерти мир становится полностью чёрным, а тело игрока - чисто белым силуэтом
    (через стенсил: тело рисуется только в маску, потом маска заливается белым, остальное - чёрным).
    Выключить: zscav_death_bw 0
]]

local cv = CreateClientConVar("zscav_death_bw", "1", true, false, "Z-SCAV: чёрно-белый экран смерти", 0, 1)

local CFG = {
    fade_in  = 0.8,  -- сек до полного эффекта
    fade_out = 0.4,
}

local amount, deadSince = 0, nil

local function FindCorpse(ply)
    local candidates = {
        ply:GetNWEntity("RagdollDeath"),
        ply:GetNWEntity("FakeRagdoll"),
        ply.FakeRagdoll,
        ply:GetRagdollEntity(),
    }
    for _, e in ipairs(candidates) do
        if IsValid(e) then return e end
    end
end

local function DrawBody(ent)
    ent:DrawModel()
    -- одежда/аксессуары, прикреплённые к телу
    for _, ch in ipairs(ent:GetChildren()) do
        if IsValid(ch) and ch.DrawModel and not ch:GetNoDraw() then ch:DrawModel() end
    end
end

hook.Add("RenderScreenspaceEffects", "ZSCAV_DeathBW", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local dead = not ply:Alive() and cv:GetBool()
    if dead then deadSince = deadSince or RealTime() else deadSince = nil end
    amount = math.Approach(amount, dead and 1 or 0, FrameTime() / (dead and CFG.fade_in or CFG.fade_out))
    if amount <= 0.001 then return end

    local corpse = FindCorpse(ply)
    local a = 255 * amount

    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)

    -- 1) тело - только в маску (цвет не пишем)
    if IsValid(corpse) then
        cam.Start3D()
            render.OverrideColorWriteEnable(true, false)
            DrawBody(corpse)
            render.OverrideColorWriteEnable(false)
        cam.End3D()
    end

    -- 2) всё вне маски - чёрное, внутри - белое
    cam.Start2D()
        render.SetStencilPassOperation(STENCIL_KEEP)
        render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
        surface.SetDrawColor(0, 0, 0, a)
        surface.DrawRect(0, 0, ScrW(), ScrH())

        render.SetStencilCompareFunction(STENCIL_EQUAL)
        surface.SetDrawColor(255, 255, 255, a)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    cam.End2D()

    render.SetStencilEnable(false)
end)
