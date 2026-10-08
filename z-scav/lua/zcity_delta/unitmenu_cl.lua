if SERVER then return end

if _G.__zcity_delta_unitmenu_loaded then
    hook.Remove("Think", "zcity_delta_unitmenu_input")
    hook.Remove("HUDPaint", "zcity_delta_unitmenu_draw")
    gui.EnableScreenClicker(false)
end
_G.__zcity_delta_unitmenu_loaded = true

local opened = false
local lastLeftDown = false
local lastRightDown = false
local lastHoveredLimb = nil
local selectedTarget = nil
local forcedTarget = nil
local circleMat = Material("vgui/circle")
local statusIconPaths = {
    bleed = {
        "zcity_delta/unitmenu/status/bleeding.png"
    },
    fracture = {
        "zcity_delta/unitmenu/status/fracture.png"
    },
    dislocation = {
        "zcity_delta/unitmenu/status/dislocation.png"
    }
}
local statusIconMats = {}
local statusIconAttempted = {}
local statusIconDims = {}
local armorSlotMats = nil
local limbShakeSeedCache = {}
local NoiseHash

local SPRITE_CANVAS_W = 1500
local SPRITE_CANVAS_H = 1500
local SPRITE_ANCHOR_X = 749
local SPRITE_ANCHOR_Y = 711
local SPRITE_PELVIS_BBOX_W = 247

local limbSprites = {
    {id = "head", limb = "head", orgKey = "skull", matPath = "zcity_delta/unitmenu/limbs/head.png", bbox = {608, 118, 892, 400}},
    {id = "chest", limb = "chest", orgKey = "chest", matPath = "zcity_delta/unitmenu/limbs/chest.png", bbox = {622, 386, 878, 618}},
    {id = "pelvis", limb = "pelvis", orgKey = "pelvis", matPath = "zcity_delta/unitmenu/limbs/pelvis.png", bbox = {626, 600, 872, 822}},

    {id = "l_upperarm", limb = "larm", orgKey = "larm", matPath = "zcity_delta/unitmenu/limbs/l_upperarm.png", bbox = {420, 410, 682, 538}},
    {id = "l_forearm", limb = "larm", orgKey = "larm", matPath = "zcity_delta/unitmenu/limbs/l_forearm.png", bbox = {198, 436, 442, 538}},
    {id = "l_hand", limb = "larm", orgKey = "larm", matPath = "zcity_delta/unitmenu/limbs/l_hand.png", bbox = {20, 404, 218, 572}},

    {id = "r_upperarm", limb = "rarm", orgKey = "rarm", matPath = "zcity_delta/unitmenu/limbs/r_upperarm.png", bbox = {816, 410, 1078, 538}},
    {id = "r_forearm", limb = "rarm", orgKey = "rarm", matPath = "zcity_delta/unitmenu/limbs/r_forearm.png", bbox = {1058, 436, 1300, 538}},
    {id = "r_hand", limb = "rarm", orgKey = "rarm", matPath = "zcity_delta/unitmenu/limbs/r_hand.png", bbox = {1280, 404, 1480, 572}},

    {id = "l_thigh", limb = "lleg", orgKey = "lleg", matPath = "zcity_delta/unitmenu/limbs/l_thigh.png", bbox = {554, 774, 752, 1060}},
    {id = "l_calf", limb = "lleg", orgKey = "lleg", matPath = "zcity_delta/unitmenu/limbs/l_calf.png", bbox = {570, 1044, 716, 1204}},
    {id = "l_foot", limb = "lleg", orgKey = "lleg", matPath = "zcity_delta/unitmenu/limbs/l_foot.png", bbox = {570, 1182, 722, 1380}},

    {id = "r_thigh", limb = "rleg", orgKey = "rleg", matPath = "zcity_delta/unitmenu/limbs/r_thigh.png", bbox = {746, 774, 944, 1060}},
    {id = "r_calf", limb = "rleg", orgKey = "rleg", matPath = "zcity_delta/unitmenu/limbs/r_calf.png", bbox = {782, 1044, 928, 1204}},
    {id = "r_foot", limb = "rleg", orgKey = "rleg", matPath = "zcity_delta/unitmenu/limbs/r_foot.png", bbox = {776, 1182, 930, 1380}}
}

local function EnsureLimbSpriteMaterials()
    for _, s in ipairs(limbSprites) do
        if not s.mat or s.mat:IsError() then
            s.mat = Material(s.matPath, "smooth")
        end
    end
end

local function HasLimbSpriteMaterials()
    EnsureLimbSpriteMaterials()
    for _, s in ipairs(limbSprites) do
        if not s.mat or s.mat:IsError() then
            return false
        end
    end
    return true
end

local function GetSpriteTransform(rects)
    local pelvis = rects.pelvis
    local px = pelvis.x + pelvis.w * 0.5
    local py = pelvis.y + pelvis.h * 0.5
    local sc = pelvis.w / SPRITE_PELVIS_BBOX_W
    local ox = px - SPRITE_ANCHOR_X * sc
    local oy = py - SPRITE_ANCHOR_Y * sc
    return ox, oy, sc
end

local function EnsureStatusIconMaterials()
    for key, path in pairs(statusIconPaths) do
        local mat = statusIconMats[key]
        if (not mat or mat:IsError()) and not statusIconAttempted[key] then
            statusIconAttempted[key] = true
            local paths = istable(path) and path or {path}
            for i = 1, #paths do
                local candidate = Material(paths[i], "smooth")
                if candidate and not candidate:IsError() then
                    statusIconMats[key] = candidate
                    statusIconDims[key] = nil
                    break
                end
            end
        end

        local final = statusIconMats[key]
        if final and not final:IsError() and not statusIconDims[key] then
            local w = isfunction(final.Width) and final:Width() or 0
            local h = isfunction(final.Height) and final:Height() or 0
            if (w or 0) <= 0 or (h or 0) <= 0 then
                local tex = isfunction(final.GetTexture) and final:GetTexture("$basetexture") or nil
                w = tex and isfunction(tex.Width) and tex:Width() or w
                h = tex and isfunction(tex.Height) and tex:Height() or h
            end
            w = tonumber(w) or 0
            h = tonumber(h) or 0
            if w <= 0 or h <= 0 then
                w, h = 1, 1
            end
            statusIconDims[key] = {w = w, h = h}
        end
    end
end

local function EnsureArmorSlotMaterials()
    if armorSlotMats then return end
    local function LoadMat(candidates)
        for i = 1, #candidates do
            local m = Material(candidates[i], "noclamp")
            if m and not m:IsError() then
                return m
            end
        end
        return Material("icon16/shield.png", "smooth mips")
    end
    armorSlotMats = {
        ears = LoadMat({"homigrad/limbs/ears_slot.png", "homigrad/limbs/ears_slot"}),
        face = LoadMat({"homigrad/limbs/face_slot.png", "homigrad/limbs/face_slot"}),
        head = LoadMat({"homigrad/limbs/helmet_slot.png", "homigrad/limbs/helmet_slot"}),
        torso = LoadMat({"homigrad/limbs/torso_slot.png", "homigrad/limbs/torso_slot"})
    }
end

local function GetShakeSeed(id)
    local cached = limbShakeSeedCache[id]
    if cached then return cached end
    local seed = 0
    for i = 1, #id do
        seed = seed + string.byte(id, i)
    end
    limbShakeSeedCache[id] = seed
    return seed
end

local function GetArmorSlots(ent)
    local slots = {ears = false, face = false, head = false, torso = false}
    if not IsValid(ent) then return slots end

    local armor = nil
    if hg and isfunction(hg.GetCurrentArmor) then
        armor = hg.GetCurrentArmor(ent)
    end
    if isfunction(ent.GetNetVar) then
        armor = armor or ent:GetNetVar("Armor", nil)
    end
    if not armor and istable(ent.armors) then
        armor = ent.armors
    end

    if not istable(armor) then return slots end

    local function HasVal(v)
        return v ~= nil and v ~= false and v ~= "" and v ~= 0
    end

    if armor.head ~= nil or armor.torso ~= nil or armor.face ~= nil or armor.ears ~= nil or armor.headphones ~= nil then
        slots.head = HasVal(armor.head)
        slots.torso = HasVal(armor.torso)
        slots.face = HasVal(armor.face)
        slots.ears = HasVal(armor.ears) or HasVal(armor.headphones)
    end

    for _, v in pairs(armor) do
        if isstring(v) then
            local s = string.lower(v)
            if string.find(s, "helmet", 1, true) then
                slots.head = true
            elseif string.find(s, "vest", 1, true) then
                slots.torso = true
            elseif string.find(s, "mask", 1, true) or string.find(s, "face", 1, true) or string.find(s, "gasmask", 1, true) or string.find(s, "nightvision", 1, true) then
                slots.face = true
            elseif string.find(s, "headphones", 1, true) or string.find(s, "ears", 1, true) then
                slots.ears = true
            end
        end
    end

    return slots
end

local limbArmTokens = {
    UpperArm = true,
    Forearm = true,
    Hand = true,
    Finger = true,
    Clavicle = true
}

local limbLegTokens = {
    Thigh = true,
    Calf = true,
    Foot = true,
    Toe = true
}

local function BoneBelongsToLimb(boneName, limb)
    if not isstring(boneName) or boneName == "" then return false end

    if limb == "larm" then
        if not boneName:find("Bip01_L_", 1, true) then return false end
        for token in pairs(limbArmTokens) do
            if boneName:find(token, 1, true) then return true end
        end
        return false
    end

    if limb == "rarm" then
        if not boneName:find("Bip01_R_", 1, true) then return false end
        for token in pairs(limbArmTokens) do
            if boneName:find(token, 1, true) then return true end
        end
        return false
    end

    if limb == "lleg" then
        if not boneName:find("Bip01_L_", 1, true) then return false end
        for token in pairs(limbLegTokens) do
            if boneName:find(token, 1, true) then return true end
        end
        return false
    end

    if limb == "rleg" then
        if not boneName:find("Bip01_R_", 1, true) then return false end
        for token in pairs(limbLegTokens) do
            if boneName:find(token, 1, true) then return true end
        end
        return false
    end

    if limb == "head" then
        return boneName:find("Head", 1, true) or boneName:find("Neck", 1, true) or boneName:find("Jaw", 1, true)
    end

    if limb == "chest" then
        return boneName:find("Spine", 1, true) or boneName:find("Rib", 1, true) or boneName:find("Chest", 1, true)
    end

    if limb == "pelvis" then
        return boneName:find("Pelvis", 1, true) or boneName:find("Hip", 1, true)
    end

    return false
end

local function LimbHasBleeding(org, limb)
    if not istable(org) then return false end

    local function CheckList(list)
        if not istable(list) or #list <= 0 then return false end
        for i = 1, #list do
            local wound = list[i]
            if istable(wound) then
                local amt = tonumber(wound[1] or 0) or 0
                local boneName = wound[4]
                if amt > 0.01 and BoneBelongsToLimb(boneName, limb) then
                    return true
                end
            end
        end
        return false
    end

    if CheckList(org.wounds) then return true end
    if CheckList(org.arterialwounds) then return true end
    return false
end

local function LimbHasFracture(org, limb)
    if not istable(org) then return false end

    if limb == "head" then
        return (tonumber(org.skull or 0) or 0) >= 0.6
    end

    if limb == "chest" then
        return (tonumber(org.chest or 0) or 0) > 0
    end

    if limb == "pelvis" then
        return (tonumber(org.pelvis or 0) or 0) >= 0.99
    end

    local v = tonumber(org[limb] or 0) or 0
    if limb == "larm" and org.larmamputated then return false end
    if limb == "rarm" and org.rarmamputated then return false end
    if limb == "lleg" and org.llegamputated then return false end
    if limb == "rleg" and org.rlegamputated then return false end
    return v >= 0.99
end

local function LimbHasDislocation(org, limb)
    if not istable(org) then return false end
    if limb ~= "larm" and limb ~= "rarm" and limb ~= "lleg" and limb ~= "rleg" then return false end
    return org[limb .. "dislocation"] == true
end

local statusAnchorIds = {
    head = true,
    chest = true,
    pelvis = true,
    l_upperarm = true,
    r_upperarm = true,
    l_thigh = true,
    r_thigh = true
}

local function DrawStatusIcons(x, y, w, h, sc, flags)
    EnsureStatusIconMaterials()
    if not flags or (not flags.bleed and not flags.fracture and not flags.dislocation) then return end

    local size = math.floor(math.Clamp(math.min(w, h) * 0.32, 28, 74))
    local pad = math.floor(math.Clamp(size * 0.16, 4, 10))
    local count = (flags.bleed and 1 or 0) + (flags.fracture and 1 or 0) + (flags.dislocation and 1 or 0)
    local totalH = (count * size) + math.max((count - 1) * pad, 0)
    local ix = x + w * 0.5 - size * 0.5
    local iy = y + h * 0.5 - totalH * 0.5

    local function DrawIconFallback(kind)
        surface.SetDrawColor(0, 0, 0, 200)
        surface.DrawRect(ix, iy, size, size)
        surface.SetDrawColor(255, 255, 255, 230)
        surface.DrawOutlinedRect(ix, iy, size, size, 2)

        local cx = ix + size * 0.5
        local cy = iy + size * 0.5

        if kind == "bleed" then
            local drop = {
                {x = cx, y = iy + size * 0.12},
                {x = ix + size * 0.72, y = iy + size * 0.5},
                {x = cx, y = iy + size * 0.9},
                {x = ix + size * 0.28, y = iy + size * 0.5},
            }
            draw.NoTexture()
            surface.SetDrawColor(255, 255, 255, 240)
            surface.DrawPoly(drop)
            return
        end

        if kind == "fracture" then
            surface.SetDrawColor(255, 255, 255, 240)
            local x1 = ix + size * 0.22
            local x2 = ix + size * 0.78
            local y1 = iy + size * 0.28
            local y2 = iy + size * 0.72
            surface.DrawLine(x1, y2, x1 + size * 0.22, y1 + size * 0.22)
            surface.DrawLine(x1 + size * 0.22, y1 + size * 0.22, x2 - size * 0.22, y2 - size * 0.22)
            surface.DrawLine(x2 - size * 0.22, y2 - size * 0.22, x2, y1)
            surface.DrawLine(ix + size * 0.25, iy + size * 0.62, ix + size * 0.42, iy + size * 0.78)
            surface.DrawLine(ix + size * 0.58, iy + size * 0.22, ix + size * 0.75, iy + size * 0.38)
            return
        end

        if kind == "dislocation" then
            surface.SetDrawColor(255, 255, 255, 240)
            surface.DrawLine(ix + size * 0.25, iy + size * 0.35, ix + size * 0.75, iy + size * 0.35)
            surface.DrawLine(ix + size * 0.25, iy + size * 0.65, ix + size * 0.75, iy + size * 0.65)
            surface.DrawLine(ix + size * 0.52, iy + size * 0.26, ix + size * 0.52, iy + size * 0.46)
            surface.DrawLine(ix + size * 0.48, iy + size * 0.54, ix + size * 0.48, iy + size * 0.74)
            return
        end
    end

    local function DrawIcon(key, tint)
        local mat = statusIconMats[key]
        if mat and not mat:IsError() then
            local dims = statusIconDims[key] or {w = 1, h = 1}
            local mw = math.max(tonumber(dims.w) or 1, 1)
            local mh = math.max(tonumber(dims.h) or 1, 1)
            local scale = math.min(size / mw, size / mh)
            local dw = mw * scale
            local dh = mh * scale
            local dx = ix + (size - dw) * 0.5
            local dy = iy + (size - dh) * 0.5

            surface.SetMaterial(mat)
            local c = tint or color_white
            surface.SetDrawColor(c.r, c.g, c.b, 240)
            surface.DrawTexturedRect(dx, dy, dw, dh)
        else
            DrawIconFallback(key)
        end
        iy = iy + size + math.max(1, math.floor(pad * 0.7))
    end

    if flags.bleed then
        local s = math.Clamp(tonumber(flags.bleedStrength or 0) or 0, 0, 1)
        local g = math.floor(255 * (1 - s))
        local tint = Color(255, g, g)
        DrawIcon("bleed", tint)
    end
    if flags.fracture then DrawIcon("fracture") end
    if flags.dislocation then DrawIcon("dislocation") end
end

local limbStatusCache = {
    entIndex = nil,
    nextUpdate = 0,
    data = nil
}

local function BuildLimbStatusData(target, org)
    local entIndex = IsValid(target) and target:EntIndex() or -1
    if limbStatusCache.data and limbStatusCache.entIndex == entIndex and CurTime() < (limbStatusCache.nextUpdate or 0) then
        return limbStatusCache.data
    end

    local data = {
        head = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        chest = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        pelvis = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        larm = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        rarm = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        lleg = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false},
        rleg = {bleed = false, bleedStrength = 0, fracture = false, dislocation = false}
    }

    if istable(org) then
        data.larm.dislocation = org.larmdislocation == true
        data.rarm.dislocation = org.rarmdislocation == true
        data.lleg.dislocation = org.llegdislocation == true
        data.rleg.dislocation = org.rlegdislocation == true

        data.head.fracture = (tonumber(org.skull or 0) or 0) >= 0.6
        data.chest.fracture = (tonumber(org.chest or 0) or 0) > 0
        data.pelvis.fracture = (tonumber(org.pelvis or 0) or 0) >= 0.99
        data.larm.fracture = (not org.larmamputated) and ((tonumber(org.larm or 0) or 0) >= 0.99)
        data.rarm.fracture = (not org.rarmamputated) and ((tonumber(org.rarm or 0) or 0) >= 0.99)
        data.lleg.fracture = (not org.llegamputated) and ((tonumber(org.lleg or 0) or 0) >= 0.99)
        data.rleg.fracture = (not org.rlegamputated) and ((tonumber(org.rleg or 0) or 0) >= 0.99)

        local function AddBleedForBone(boneName, amount)
            if not isstring(boneName) or boneName == "" then return end

            local v = math.max(tonumber(amount) or 0, 0)
            if boneName:find("Pelvis", 1, true) or boneName:find("Hip", 1, true) then
                data.pelvis.bleed = true
                data.pelvis.bleedStrength = data.pelvis.bleedStrength + v
                return
            end

            if boneName:find("Spine", 1, true) or boneName:find("Rib", 1, true) or boneName:find("Chest", 1, true) then
                data.chest.bleed = true
                data.chest.bleedStrength = data.chest.bleedStrength + v
                return
            end

            if boneName:find("Head", 1, true) or boneName:find("Neck", 1, true) or boneName:find("Jaw", 1, true) then
                data.head.bleed = true
                data.head.bleedStrength = data.head.bleedStrength + v
                return
            end

            local isLeft = boneName:find("Bip01_L_", 1, true) ~= nil
            local isRight = boneName:find("Bip01_R_", 1, true) ~= nil
            if not isLeft and not isRight then return end

            local isLeg = boneName:find("Thigh", 1, true)
                or boneName:find("Calf", 1, true)
                or boneName:find("Foot", 1, true)
                or boneName:find("Toe", 1, true)

            if isLeft then
                if isLeg then
                    data.lleg.bleed = true
                    data.lleg.bleedStrength = data.lleg.bleedStrength + v
                else
                    data.larm.bleed = true
                    data.larm.bleedStrength = data.larm.bleedStrength + v
                end
            else
                if isLeg then
                    data.rleg.bleed = true
                    data.rleg.bleedStrength = data.rleg.bleedStrength + v
                else
                    data.rarm.bleed = true
                    data.rarm.bleedStrength = data.rarm.bleedStrength + v
                end
            end
        end

        local function ResolveBoneName(boneField)
            if isstring(boneField) then return boneField end
            if isnumber(boneField) and IsValid(target) then
                return target:GetBoneName(boneField)
            end
            return nil
        end

        local function ScanWounds(list)
            if not istable(list) or #list <= 0 then return end
            for i = 1, #list do
                local wound = list[i]
                if istable(wound) then
                    local amt = tonumber(wound[1] or 0) or 0
                    if amt > 0.01 then
                        AddBleedForBone(ResolveBoneName(wound[4]), amt)
                    end
                end
            end
        end

        local function ScanArterial(list)
            if not istable(list) or #list <= 0 then return end
            for i = 1, #list do
                local wound = list[i]
                if istable(wound) then
                    AddBleedForBone(ResolveBoneName(wound[4]), 22)
                end
            end
        end

        local netWounds = (IsValid(target) and target.GetNetVar) and target:GetNetVar("wounds", nil) or nil
        local netArterial = (IsValid(target) and target.GetNetVar) and target:GetNetVar("arterialwounds", nil) or nil

        ScanWounds(netWounds or org.wounds)
        ScanArterial(netArterial or org.arterialwounds)

        local function NormalizeStrength(seg)
            seg.bleedStrength = math.Clamp((tonumber(seg.bleedStrength) or 0) / 40, 0, 1)
        end

        NormalizeStrength(data.head)
        NormalizeStrength(data.chest)
        NormalizeStrength(data.pelvis)
        NormalizeStrength(data.larm)
        NormalizeStrength(data.rarm)
        NormalizeStrength(data.lleg)
        NormalizeStrength(data.rleg)
    end

    limbStatusCache.entIndex = entIndex
    limbStatusCache.nextUpdate = CurTime() + 0.15
    limbStatusCache.data = data
    return data
end

local function DrawLimbSprites(rects, hoveredId, accent, org, statusData)
    EnsureLimbSpriteMaterials()
    local ox, oy, sc = GetSpriteTransform(rects)
    local baseA = 235
    local hoverA = 255
    local anchors = {}
    for _, s in ipairs(limbSprites) do
        local b = s.bbox
        local x = ox + b[1] * sc
        local y = oy + b[2] * sc
        local w = (b[3] - b[1] + 1) * sc
        local h = (b[4] - b[2] + 1) * sc
        local u0 = b[1] / SPRITE_CANVAS_W
        local v0 = b[2] / SPRITE_CANVAS_H
        local u1 = (b[3] + 1) / SPRITE_CANVAS_W
        local v1 = (b[4] + 1) / SPRITE_CANVAS_H

        local dmg = tonumber(org and s.orgKey and org[s.orgKey] or 0) or 0
        dmg = math.Clamp(dmg, 0, 1)
        local shakeT = math.Clamp((dmg - 0.8) / 0.2, 0, 1)
        if shakeT > 0 and (s.limb == "larm" or s.limb == "rarm" or s.limb == "lleg" or s.limb == "rleg") then
            local amp = (shakeT ^ 1.25) * (2.2 * sc)
            local tick = math.floor(RealTime() * 26)
            local seed = GetShakeSeed(s.limb)
            local rx = (NoiseHash(seed, tick, 11) - 0.5) * 2
            local ry = (NoiseHash(seed + 97, tick, 23) - 0.5) * 2
            x = x + math.Round(rx * amp)
            y = y + math.Round(ry * amp)
        end

        surface.SetMaterial(s.mat)
        surface.SetDrawColor(255, 255, 255, (hoveredId == s.id) and hoverA or baseA)
        surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)

        local t = math.Clamp((dmg - 0.08) / 0.75, 0, 1)
        t = t ^ 0.55
        if t > 0 then
            local gb = math.floor(120 * (1 - t))
            surface.SetDrawColor(255, gb, gb, math.floor(245 * t))
            surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
        end

        if hoveredId == s.id then
            surface.SetDrawColor(accent.r, accent.g, accent.b, 70)
            surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)

            surface.SetDrawColor(255, 255, 255, 90)
            surface.DrawTexturedRectUV(x - 1, y - 1, w + 2, h + 2, u0, v0, u1, v1)
        end
        if statusAnchorIds[s.id] and s.limb then
            anchors[#anchors + 1] = {x = x, y = y, w = w, h = h, limb = s.limb}
        end
    end

    if statusData and #anchors > 0 then
        for i = 1, #anchors do
            local a = anchors[i]
            local flags = statusData[a.limb] or statusData[a.limb == "head" and "head" or a.limb]
            DrawStatusIcons(a.x, a.y, a.w, a.h, sc, flags)
        end
    end
end

local function GetHoveredLimbFromSprites(mx, my, rects)
    if not HasLimbSpriteMaterials() then return nil, nil end
    local ox, oy, sc = GetSpriteTransform(rects)
    for _, s in ipairs(limbSprites) do
        local b = s.bbox
        local x = ox + b[1] * sc
        local y = oy + b[2] * sc
        local w = (b[3] - b[1] + 1) * sc
        local h = (b[4] - b[2] + 1) * sc
        if mx >= x and mx <= x + w and my >= y and my <= y + h then
            return s.id, s.limb
        end
    end
    return nil, nil
end

local function EnsureFonts()
    surface.CreateFont("zcity_um_title", {font = "04b11", size = 18, weight = 900, antialias = false, extended = true})
    surface.CreateFont("zcity_um_text", {font = "04b11", size = 14, weight = 700, antialias = false, extended = true})
    surface.CreateFont("zcity_um_small", {font = "04b11", size = 12, weight = 600, antialias = false, extended = true})
end

local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function DrawScanlines(x, y, w, h, a)
    local alpha = a or 14
    surface.SetDrawColor(0, 0, 0, alpha)
    local step = 3
    for py = y + 2, y + h - 2, step do
        surface.DrawRect(x + 2, py, w - 4, 1)
    end
end

local function DrawPanel(x, y, w, h, accent, bgA)
    surface.SetDrawColor(accent.r, accent.g, accent.b, 220)
    surface.DrawOutlinedRect(x, y, w, h, 2)
    surface.SetDrawColor(0, 0, 0, bgA or 200)
    surface.DrawRect(x + 2, y + 2, w - 4, h - 4)
    surface.SetDrawColor(accent.r, accent.g, accent.b, 35)
    surface.DrawRect(x + 2, y + 2, w - 4, h - 4)
    DrawScanlines(x, y, w, h, 18)
end

local function DrawCircleFilled(cx, cy, r, col)
    surface.SetMaterial(circleMat)
    surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
    surface.DrawTexturedRect(cx - r, cy - r, r * 2, r * 2)
end

local function DrawOutlinedCircle(cx, cy, r, outlineCol, fillCol)
    DrawCircleFilled(cx, cy, r + 2, outlineCol)
    DrawCircleFilled(cx, cy, r, fillCol)
end

local function DrawOutlinedRoundedBox(radius, x, y, w, h, outlineCol, fillCol, thickness)
    local t = thickness or 2
    draw.RoundedBox(radius + t, x - t, y - t, w + t * 2, h + t * 2, outlineCol)
    draw.RoundedBox(radius, x, y, w, h, fillCol)
end

NoiseHash = function(x, y, s)
    local b = bit
    local n = x * 15731 + y * 789221 + s * 1376312589
    if b then
        n = b.bxor(b.lshift(n, 13), n)
    end
    local nn = (n * (n * n * 15731 + 789221) + 1376312589)
    if b then
        nn = b.band(nn, 0x7fffffff)
    else
        nn = math.abs(nn)
    end
    return nn / 2147483647
end

local function DrawNoise(x, y, w, h, alpha, step)
    local a = alpha or 10
    local st = step or 4
    local s = math.floor(RealTime() * 18)
    surface.SetDrawColor(0, 0, 0, a)
    for py = y, y + h, st do
        for px = x, x + w, st do
            if NoiseHash(px, py, s) > 0.62 then
                surface.DrawRect(px, py, st, st)
            end
        end
    end
end

local function DrawVignette(w, h)
    surface.SetDrawColor(0, 0, 0, 80)
    surface.DrawRect(0, 0, w, 70)
    surface.DrawRect(0, h - 70, w, 70)
    surface.DrawRect(0, 0, 70, h)
    surface.DrawRect(w - 70, 0, 70, h)
end

local function DrawDislocationIcon(x, y, size)
    local s = size or 18
    DrawOutlinedRoundedBox(4, x, y, s, s, Color(255, 255, 255), Color(210, 40, 40), 2)
    surface.SetDrawColor(255, 255, 255, 240)
    surface.DrawRect(x + math.floor(s * 0.2), y + math.floor(s * 0.46), math.floor(s * 0.6), math.max(2, math.floor(s * 0.12)))
    surface.DrawRect(x + math.floor(s * 0.46), y + math.floor(s * 0.2), math.max(2, math.floor(s * 0.12)), math.floor(s * 0.6))
end

local function GetTarget()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end

    if IsValid(forcedTarget) then
        local ent = forcedTarget
        if ent:IsRagdoll() and hg and hg.RagdollOwner then
            ent = hg.RagdollOwner(ent) or ent
        end
        if IsValid(ent) and ent:IsPlayer() and ent.organism and ply:GetPos():DistToSqr(ent:GetPos()) <= 10000 then
            return ent
        end
        forcedTarget = nil
    end

    local ent = nil
    if hg and hg.eyeTrace then
        local tr = hg.eyeTrace(ply)
        ent = tr and tr.Entity or nil
    end

    if IsValid(ent) then
        if ent:IsRagdoll() and hg and hg.RagdollOwner then
            ent = hg.RagdollOwner(ent) or ent
        end
        if IsValid(ent) and ent:IsPlayer() and ent.organism and ply:GetPos():DistToSqr(ent:GetPos()) <= 10000 then
            return ent
        end
    end

    return ply
end

local function GetOrg(ent)
    if not IsValid(ent) then return nil end
    return ent.organism
end

local function GetLimbRects(cx, cy, scale)
    local s = scale or 1

    local headR = 22 * s
    local torsoR = 24 * s
    local pelvisR = 22 * s

    local shoulderY = cy - 78 * s
    local torsoY = shoulderY + 22 * s
    local pelvisY = torsoY + 58 * s

    local upperArmW = 46 * s
    local armH = 18 * s
    local foreArmW = 40 * s
    local handW = 18 * s

    local upperLegW = 22 * s
    local upperLegH = 46 * s
    local lowerLegH = 44 * s
    local footW = 28 * s
    local footH = 16 * s

    local head = {id = "head", limb = "head", x = cx - headR, y = cy - 128 * s - headR, w = headR * 2, h = headR * 2}
    local chest = {id = "chest", limb = "chest", x = cx - torsoR, y = torsoY - torsoR, w = torsoR * 2, h = torsoR * 2}
    local pelvis = {id = "pelvis", limb = "pelvis", x = cx - pelvisR, y = pelvisY - pelvisR, w = pelvisR * 2, h = pelvisR * 2}

    local lUpperArm = {id = "l_upperarm", limb = "larm", x = cx - torsoR - upperArmW, y = shoulderY, w = upperArmW, h = armH}
    local lForeArm = {id = "l_forearm", limb = "larm", x = lUpperArm.x - foreArmW, y = shoulderY + 2 * s, w = foreArmW, h = armH - 4 * s}
    local lHand = {id = "l_hand", limb = "larm", x = lForeArm.x - handW - 4 * s, y = shoulderY - 2 * s, w = handW, h = armH + 4 * s}

    local rUpperArm = {id = "r_upperarm", limb = "rarm", x = cx + torsoR, y = shoulderY, w = upperArmW, h = armH}
    local rForeArm = {id = "r_forearm", limb = "rarm", x = rUpperArm.x + upperArmW, y = shoulderY + 2 * s, w = foreArmW, h = armH - 4 * s}
    local rHand = {id = "r_hand", limb = "rarm", x = rForeArm.x + foreArmW + 4 * s, y = shoulderY - 2 * s, w = handW, h = armH + 4 * s}

    local legStartY = pelvisY + pelvisR * 0.8
    local lThigh = {id = "l_thigh", limb = "lleg", x = cx - 20 * s - upperLegW, y = legStartY, w = upperLegW, h = upperLegH}
    local lCalf = {id = "l_calf", limb = "lleg", x = lThigh.x, y = lThigh.y + upperLegH - 2 * s, w = upperLegW, h = lowerLegH}
    local lFoot = {id = "l_foot", limb = "lleg", x = lThigh.x - (footW - upperLegW) * 0.5, y = lCalf.y + lowerLegH - 2 * s, w = footW, h = footH}

    local rThigh = {id = "r_thigh", limb = "rleg", x = cx + 20 * s, y = legStartY, w = upperLegW, h = upperLegH}
    local rCalf = {id = "r_calf", limb = "rleg", x = rThigh.x, y = rThigh.y + upperLegH - 2 * s, w = upperLegW, h = lowerLegH}
    local rFoot = {id = "r_foot", limb = "rleg", x = rThigh.x - (footW - upperLegW) * 0.5, y = rCalf.y + lowerLegH - 2 * s, w = footW, h = footH}

    return {
        head = head,
        chest = chest,
        pelvis = pelvis,
        lUpperArm = lUpperArm,
        lForeArm = lForeArm,
        lHand = lHand,
        rUpperArm = rUpperArm,
        rForeArm = rForeArm,
        rHand = rHand,
        lThigh = lThigh,
        lCalf = lCalf,
        lFoot = lFoot,
        rThigh = rThigh,
        rCalf = rCalf,
        rFoot = rFoot
    }
end

local function HitRect(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

local function GetHoveredLimb(mx, my, rects)
    local sid, slim = GetHoveredLimbFromSprites(mx, my, rects)
    if sid then return sid, slim end
    for _, r in pairs(rects) do
        if istable(r) and r.x and HitRect(mx, my, r) then
            return r.id, r.limb
        end
    end
    return nil, nil
end

local function GetBodyScale(sw, sh)
    return 2.8
end

local function DrawSilhouette(rects, outline, fill, hoveredId, accent)
    local h = rects.head
    local chest = rects.chest
    local pelvis = rects.pelvis

    DrawOutlinedCircle(h.x + h.w * 0.5, h.y + h.h * 0.5, h.w * 0.5, outline, fill)
    DrawOutlinedCircle(chest.x + chest.w * 0.5, chest.y + chest.h * 0.5, chest.w * 0.5, outline, fill)
    DrawOutlinedCircle(pelvis.x + pelvis.w * 0.5, pelvis.y + pelvis.h * 0.5, pelvis.w * 0.5, outline, fill)

    local function Seg(r, rad)
        local radius = rad or 6
        DrawOutlinedRoundedBox(radius, r.x, r.y, r.w, r.h, outline, fill, 3)
        if hoveredId == r.id then
            surface.SetDrawColor(accent.r, accent.g, accent.b, 70)
            surface.DrawRect(r.x + 2, r.y + 2, r.w - 4, r.h - 4)
        end
    end

    Seg(rects.lUpperArm, 8)
    Seg(rects.lForeArm, 8)
    Seg(rects.lHand, 8)
    Seg(rects.rUpperArm, 8)
    Seg(rects.rForeArm, 8)
    Seg(rects.rHand, 8)

    Seg(rects.lThigh, 10)
    Seg(rects.lCalf, 10)
    Seg(rects.lFoot, 8)
    Seg(rects.rThigh, 10)
    Seg(rects.rCalf, 10)
    Seg(rects.rFoot, 8)
end

local function DrawBar(x, y, w, h, pct, accent, label, valueText)
    DrawPanel(x, y, w, h, accent, 190)
    local fillW = math.floor((w - 8) * Clamp01(pct))
    surface.SetDrawColor(accent.r, accent.g, accent.b, 180)
    surface.DrawRect(x + 4, y + h - 10, fillW, 6)
    draw.SimpleText(label, "zcity_um_small", x + 8, y + 6, accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(valueText, "zcity_um_small", x + w - 8, y + 6, accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

local function GetLimbStatus(org, limbKey, amputatedKey, dislocationKey)
    if not org then return "None", Color(170, 170, 170) end
    if amputatedKey and org[amputatedKey] then return "AMPUTATED", Color(255, 80, 80) end
    if dislocationKey and org[dislocationKey] then return "DISLOCATED", Color(255, 170, 80) end
    local val = tonumber(org[limbKey] or 0) or 0
    if val >= 0.95 then return "DESTROYED", Color(255, 80, 80) end
    if val >= 0.7 then return "SEVERE", Color(255, 140, 70) end
    if val >= 0.35 then return "MODERATE", Color(240, 210, 90) end
    if val >= 0.15 then return "MINOR", Color(190, 240, 140) end
    return "NORMAL", Color(140, 240, 170)
end

local function CanFixDislocation(org, limb)
    if not org then return false end
    return org[limb .. "dislocation"] == true
end

local function GroupFromLimb(limb)
    if limb == "lleg" or limb == "rleg" then return 1 end
    if limb == "larm" or limb == "rarm" then return 2 end
    if limb == "jaw" then return 3 end
    return nil
end

local function Toggle()
    opened = not opened
    if opened then
        EnsureFonts()
        gui.EnableScreenClicker(true)
        selectedTarget = GetTarget()
    else
        gui.EnableScreenClicker(false)
        selectedTarget = nil
        lastHoveredLimb = nil
        forcedTarget = nil
    end
end

_G.ZCityDeltaToggleUnitMenu = Toggle
_G.ZCityDeltaForceUnitMenuTarget = function(ent)
    forcedTarget = ent
end

hook.Add("Think", "zcity_delta_unitmenu_input", function()
    if not opened then return end

    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    if rightDown and not lastRightDown then
        opened = false
        gui.EnableScreenClicker(false)
        selectedTarget = nil
        lastHoveredLimb = nil
        lastRightDown = rightDown
        lastLeftDown = input.IsMouseDown(MOUSE_LEFT)
        return
    end
    lastRightDown = rightDown

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = input.GetCursorPos()
    end

    local sw, sh = ScrW(), ScrH()
    local bodyCx = math.floor(sw * 0.5)
    local bodyCy = math.floor(sh * 0.56)
    local rects = GetLimbRects(bodyCx, bodyCy, GetBodyScale(sw, sh))
    local hoveredId, hoveredLimb = GetHoveredLimb(mx, my, rects)
    lastHoveredLimb = hoveredId

    local leftDown = input.IsMouseDown(MOUSE_LEFT)
    if leftDown and not lastLeftDown then
        if hoveredLimb and selectedTarget and IsValid(selectedTarget) then
            local org = GetOrg(selectedTarget)
            if hoveredLimb == "head" and CanFixDislocation(org, "jaw") then
                local g = GroupFromLimb("jaw")
                if g then
                    RunConsoleCommand("hg_med_dislocation", g, (selectedTarget ~= LocalPlayer()) and "target" or "")
                end
            elseif hoveredLimb == "larm" and CanFixDislocation(org, "larm") then
                local g = GroupFromLimb("larm")
                if g then
                    RunConsoleCommand("hg_med_dislocation", g, (selectedTarget ~= LocalPlayer()) and "target" or "")
                end
            elseif hoveredLimb == "rarm" and CanFixDislocation(org, "rarm") then
                local g = GroupFromLimb("rarm")
                if g then
                    RunConsoleCommand("hg_med_dislocation", g, (selectedTarget ~= LocalPlayer()) and "target" or "")
                end
            elseif hoveredLimb == "lleg" and CanFixDislocation(org, "lleg") then
                local g = GroupFromLimb("lleg")
                if g then
                    RunConsoleCommand("hg_med_dislocation", g, (selectedTarget ~= LocalPlayer()) and "target" or "")
                end
            elseif hoveredLimb == "rleg" and CanFixDislocation(org, "rleg") then
                local g = GroupFromLimb("rleg")
                if g then
                    RunConsoleCommand("hg_med_dislocation", g, (selectedTarget ~= LocalPlayer()) and "target" or "")
                end
            end
        end
    end
    lastLeftDown = leftDown
end)

hook.Add("HUDPaint", "zcity_delta_unitmenu_draw", function()
    if not opened then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    selectedTarget = GetTarget()
    local target = selectedTarget
    if not IsValid(target) then return end
    local org = GetOrg(target)

    local sw, sh = ScrW(), ScrH()
    local accent = Color(0, 255, 190)
    local accentDim = Color(0, 200, 150)
    local white = Color(255, 255, 255)
    local black = Color(0, 0, 0)

    surface.SetDrawColor(0, 0, 0, 135)
    surface.DrawRect(0, 0, sw, sh)
    DrawVignette(sw, sh)
    DrawNoise(0, 0, sw, sh, 6, 12)

    local bodyCx = math.floor(sw * 0.5)
    local bodyCy = math.floor(sh * 0.56)

    local leftX = 22
    local leftW = 280
    local leftY = 20
    local leftH = math.floor(sh - 40)

    DrawPanel(leftX, leftY, leftW, leftH, accent, 200)

    local cell = 74
    local gap = 9
    local pad = 13
    local armorW = pad * 2 + cell * 4 + gap * 3
    local armorH = 32 + cell + 13
    local armorX = math.floor(bodyCx - armorW * 0.5)
    local armorY = 4

    EnsureArmorSlotMaterials()
    local slots = GetArmorSlots(target)
    local gridX = armorX + pad
    local gridY = armorY
    local function DrawArmorSlot(ix, iy, mat, has)
        surface.SetDrawColor(accent.r, accent.g, accent.b, 255)
        surface.DrawOutlinedRect(ix, iy, cell, cell, 1)
        surface.DrawOutlinedRect(ix + 1, iy + 1, cell - 2, cell - 2, 1)
        if mat and not mat:IsError() then
            local iconAlpha = has and 255 or 70
            local ds = cell - 10
            local dx = math.floor(ix + (cell - ds) * 0.5)
            local dy = math.floor(iy + (cell - ds) * 0.5)
            surface.SetMaterial(mat)
            surface.SetDrawColor(255, 255, 255, iconAlpha)
            surface.DrawTexturedRect(dx, dy, ds, ds)
        end
    end
    DrawArmorSlot(gridX + (cell + gap) * 0, gridY, armorSlotMats.torso, slots.torso)
    DrawArmorSlot(gridX + (cell + gap) * 1, gridY, armorSlotMats.head, slots.head)
    DrawArmorSlot(gridX + (cell + gap) * 2, gridY, armorSlotMats.face, slots.face)
    DrawArmorSlot(gridX + (cell + gap) * 3, gridY, armorSlotMats.ears, slots.ears)

    draw.SimpleText("EXPERIMENT", "zcity_um_small", leftX + 10, leftY + 8, accentDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local charLine = "UNIT-HEALTH v2.04"
    draw.SimpleText(charLine, "zcity_um_title", leftX + 10, leftY + 26, accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local nameLine = IsValid(target) and target:Nick() or "UNKNOWN"
    draw.SimpleText(nameLine, "zcity_um_small", leftX + 10, leftY + 52, accentDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local temp = tonumber(org and org.temperature or 36.6) or 36.6
    local blood = tonumber(org and org.blood or 0) or 0
    local bleed = tonumber(org and org.bleed or 0) or 0
    local pain = tonumber(org and org.pain or 0) or 0
    local hb = tonumber(org and org.heartbeat or 0) or 0

    local barY = leftY + 78
    DrawBar(leftX + 10, barY, leftW - 20, 34, Clamp01(blood / 5000), accent, "BLOOD", string.format("%.0f", blood))
    barY = barY + 40
    DrawBar(leftX + 10, barY, leftW - 20, 34, 1 - Clamp01(pain / 150), accent, "MOR", string.format("%.1f", pain))
    barY = barY + 40
    DrawBar(leftX + 10, barY, leftW - 20, 34, 1 - Clamp01(bleed / 25), accent, "BLOODLOSS", string.format("%.2f", bleed))

    barY = barY + 46
    local infoX = leftX + 10
    local infoW = leftW - 20
    local infoH = 62
    DrawPanel(infoX, barY, infoW, infoH, accentDim, 205)
    draw.SimpleText("TEMP", "zcity_um_small", infoX + 8, barY + 8, accentDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(string.format("%.1fC", temp), "zcity_um_small", infoX + infoW - 8, barY + 8, accentDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    draw.SimpleText("BPM", "zcity_um_small", infoX + 8, barY + 34, accentDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(string.format("%.0f", hb), "zcity_um_small", infoX + infoW - 8, barY + 34, accentDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    barY = barY + infoH + 14

    local statusText = org and org.otrub and "(DISABLED)" or "(ONLINE)"
    draw.SimpleText(statusText, "zcity_um_text", leftX + leftW * 0.5, leftY + leftH - 26, org and org.otrub and Color(255, 120, 120) or accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then mx, my = input.GetCursorPos() end
    local rects = GetLimbRects(bodyCx, bodyCy, GetBodyScale(sw, sh))
    local hoveredId, hoveredLimb = GetHoveredLimb(mx, my, rects)
    local statusData = BuildLimbStatusData(target, org)
    if HasLimbSpriteMaterials() then
        DrawLimbSprites(rects, hoveredId, accent, org, statusData)
    else
        DrawSilhouette(rects, white, black, hoveredId, accent)
    end

    local function DrawLimbHint(limbKey, limbRect, label, amputatedKey, disKey)
        local status, statusColor = GetLimbStatus(org, limbKey, amputatedKey, disKey)
        if hoveredLimb == limbRect then
            local bx = mx + 14
            local by = my + 14
            local bw = 240
            local bh = 86
            DrawPanel(bx, by, bw, bh, accentDim, 215)
            draw.SimpleText(label, "zcity_um_text", bx + 10, by + 8, accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(status, "zcity_um_small", bx + 10, by + 30, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local dmg = Clamp01(tonumber(org and org[limbKey] or 0) or 0)
            if amputatedKey and org and org[amputatedKey] then
                dmg = 1
            end
            local cond = math.floor((1 - dmg) * 100 + 0.5)
            draw.SimpleText("COND:", "zcity_um_small", bx + 10, by + 48, accentDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(string.format("%d%%", cond), "zcity_um_small", bx + bw - 10, by + 48, accentDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end

    if hoveredLimb == "head" then
        DrawLimbHint("skull", "head", "HEAD", nil, "jawdislocation")
    elseif hoveredLimb == "chest" then
        DrawLimbHint("chest", "chest", "CHEST")
    elseif hoveredLimb == "pelvis" then
        DrawLimbHint("pelvis", "pelvis", "PELVIS")
    elseif hoveredLimb == "larm" then
        DrawLimbHint("larm", "larm", "LEFT ARM", "larmamputated", "larmdislocation")
    elseif hoveredLimb == "rarm" then
        DrawLimbHint("rarm", "rarm", "RIGHT ARM", "rarmamputated", "rarmdislocation")
    elseif hoveredLimb == "lleg" then
        DrawLimbHint("lleg", "lleg", "LEFT LEG", "llegamputated", "llegdislocation")
    elseif hoveredLimb == "rleg" then
        DrawLimbHint("rleg", "rleg", "RIGHT LEG", "rlegamputated", "rlegdislocation")
    end

    local slotSize = 42
    local slotY = sh - 120
    local slotX = bodyCx - slotSize - 6
    DrawPanel(slotX, slotY, slotSize, slotSize, accentDim, 220)
    DrawPanel(slotX + slotSize + 12, slotY, slotSize, slotSize, accentDim, 220)
end)
