--[[
    Z-SCAV: отрисовка открытых переломов (модели костей из Medic's Gore Mod).
    Сервер: modules/sv_rem_openfracture.lua. zscav_open_fracture_draw 0 - не рисовать.
]]
local cvDraw = CreateClientConVar("zscav_open_fracture_draw", "1", true, false)
local NW = "zscav_ofrac"
local MAXD = 1500 * 1500

-- смещения подобраны автором Medic's Gore Mod
local PIECES = {
    larm = {bone = "ValveBiped.Bip01_L_Forearm", mdl = "models/bbuster/l_arm_lower/l_arm_lower.mdl", pos = Vector(-30, -2, -41), ang = Angle(0, -90, -20)},
    lleg = {bone = "ValveBiped.Bip01_L_Calf", mdl = "models/bbuster/l_leg_lower/l_leg_lower.mdl", pos = Vector(-3, -2, 1.5), ang = Angle(90, 5, 20)},
    rarm = {bone = "ValveBiped.Bip01_R_Forearm", mdl = "models/bbuster/r_arm_lower/r_arm_lower.mdl", pos = Vector(18, -2, -52), ang = Angle(0, -90, -10)},
    rleg = {bone = "ValveBiped.Bip01_R_Calf", mdl = "models/bbuster/r_leg_lower/r_leg_lower.mdl", pos = Vector(-2, 2, 2), ang = Angle(40, 80, 75)},
    rib1 = {bone = "ValveBiped.Bip01_Spine4", mdl = "models/Gibs/HGIBS_rib.mdl", pos = Vector(-4, 7, -2), ang = Angle(120, 10, 5), scale = 0.5},
    rib2 = {bone = "ValveBiped.Bip01_Spine4", mdl = "models/Gibs/HGIBS_rib.mdl", pos = Vector(-6, 7.2, -1), ang = Angle(100, 20, 10), scale = 0.5},
    rib3 = {bone = "ValveBiped.Bip01_Spine4", mdl = "models/Gibs/HGIBS_rib.mdl", pos = Vector(-4, 6, 3), ang = Angle(-140, 95, 95), scale = 0.5},
}

local cache = setmetatable({}, {__mode = "k"})   -- ent -> {str, list}
local models = {}                                  -- общий клиентский проп на тип кости

local function GetModel(path)
    local m = models[path]
    if IsValid(m) then return m end
    m = ClientsideModel(path, RENDERGROUP_OPAQUE)
    if IsValid(m) then m:SetNoDraw(true) end
    models[path] = m
    return m
end

local function Parse(ent, str)
    local c = cache[ent]
    if c and c.str == str then return c.list end
    local list = {}
    for k in string.gmatch(str, "[^,]+") do if PIECES[k] then list[#list + 1] = PIECES[k] end end
    cache[ent] = {str = str, list = list}
    return list
end

local function DrawOn(ent, str)
    if str == "" then return end
    for _, piece in ipairs(Parse(ent, str)) do
        local b = ent:LookupBone(piece.bone)
        if b then
            local p, a = ent:GetBonePosition(b)
            local m = p and GetModel(piece.mdl)
            if IsValid(m) then
                local wpos, wang = LocalToWorld(piece.pos, piece.ang, p, a)
                m:SetPos(wpos)
                m:SetAngles(wang)
                m:SetModelScale(piece.scale or 1)
                m:SetupBones()
                m:DrawModel()
            end
        end
    end
end

hook.Add("PostDrawOpaqueRenderables", "ZSCAV_OpenFracture", function(depth, sky)
    if sky or not cvDraw:GetBool() then return end
    local eye = EyePos()
    local lp = LocalPlayer()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and not ply:IsDormant() and not IsValid(ply.FakeRagdoll) and ply:GetPos():DistToSqr(eye) < MAXD then
            local s = ply:GetNW2String(NW, "")
            if s ~= "" and not (ply == lp and not ply:ShouldDrawLocalPlayer()) then DrawOn(ply, s) end
        end
    end
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not rag:IsDormant() and rag:GetPos():DistToSqr(eye) < MAXD then
            local s = rag:GetNW2String(NW, "")
            if s == "" then
                local owner = rag:GetNWEntity("ply")
                if IsValid(owner) and owner:Alive() and owner.FakeRagdoll == rag then s = owner:GetNW2String(NW, "") end
            end
            DrawOn(rag, s)
        end
    end
end)
