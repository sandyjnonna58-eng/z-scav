--[[
    Z-SCAV: части тела (общая таблица для сервера и клиента).
    id совпадают с куклой в меню здоровья.
]]

hg.RemParts = {
    head       = {name = "ГОЛОВА",            bones = {"ValveBiped.Bip01_Head1"}},
    neck       = {name = "ШЕЯ",               bones = {"ValveBiped.Bip01_Neck1"}},
    chest      = {name = "ГРУДЬ",             bones = {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine3"}},
    abdomen    = {name = "ЖИВОТ И ТАЗ",       bones = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Pelvis"}},
    r_upperarm = {name = "ПРАВОЕ ПЛЕЧО",      bones = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Clavicle"}, limb = "rarm", site = 3},
    r_forearm  = {name = "ПРАВОЕ ПРЕДПЛЕЧЬЕ", bones = {"ValveBiped.Bip01_R_Forearm"}, limb = "rarm", site = 3},
    r_hand     = {name = "ПРАВАЯ КИСТЬ",      bones = {"ValveBiped.Bip01_R_Hand"}, limb = "rarm"},
    l_upperarm = {name = "ЛЕВОЕ ПЛЕЧО",       bones = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Clavicle"}, limb = "larm", site = 4},
    l_forearm  = {name = "ЛЕВОЕ ПРЕДПЛЕЧЬЕ",  bones = {"ValveBiped.Bip01_L_Forearm"}, limb = "larm", site = 4},
    l_hand     = {name = "ЛЕВАЯ КИСТЬ",       bones = {"ValveBiped.Bip01_L_Hand"}, limb = "larm"},
    r_thigh    = {name = "ПРАВОЕ БЕДРО",      bones = {"ValveBiped.Bip01_R_Thigh"}, limb = "rleg", site = 1},
    r_shin     = {name = "ПРАВАЯ ГОЛЕНЬ",     bones = {"ValveBiped.Bip01_R_Calf"}, limb = "rleg", site = 1},
    r_foot     = {name = "ПРАВАЯ СТОПА",      bones = {"ValveBiped.Bip01_R_Foot", "ValveBiped.Bip01_R_Toe0"}, limb = "rleg"},
    l_thigh    = {name = "ЛЕВОЕ БЕДРО",       bones = {"ValveBiped.Bip01_L_Thigh"}, limb = "lleg", site = 2},
    l_shin     = {name = "ЛЕВАЯ ГОЛЕНЬ",      bones = {"ValveBiped.Bip01_L_Calf"}, limb = "lleg", site = 2},
    l_foot     = {name = "ЛЕВАЯ СТОПА",       bones = {"ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_L_Toe0"}, limb = "lleg"},
}

hg.RemPartByBone = {}
for id, p in pairs(hg.RemParts) do
    for _, b in ipairs(p.bones) do hg.RemPartByBone[b] = id end
end

-- режущее оружие (для ампутации) - клиенту тоже нужно для списка предметов
if CLIENT then
    local BLADE_WORDS = {"knife", "machete", "saw", "axe", "hatchet", "cleaver", "sword", "katana", "bayonet"}
    function hg.RemIsBlade(wepOrClass)
        local cls = isstring(wepOrClass) and wepOrClass or (IsValid(wepOrClass) and wepOrClass:GetClass())
        if not cls then return false end
        cls = string.lower(cls)
        for _, w in ipairs(BLADE_WORDS) do
            if string.find(cls, w, 1, true) then return true end
        end
        return false
    end
end

-- является ли оружие медициной (всё, что построено на бинте-основе)
function hg.RemIsMedicine(wepOrClass)
    local cls = isstring(wepOrClass) and wepOrClass or (IsValid(wepOrClass) and wepOrClass:GetClass())
    if not cls then return false end
    if cls == "weapon_bandage_sh" then return true end
    -- еда и напитки построены на основе бинта, но это не медицина
    if cls == "weapon_bigconsumable" or weapons.IsBasedOn(cls, "weapon_bigconsumable") then return false end
    return weapons.IsBasedOn(cls, "weapon_bandage_sh") == true
end
