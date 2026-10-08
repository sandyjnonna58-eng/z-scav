hg = hg or {}
hg.MedicalMinigame = hg.MedicalMinigame or {}

if hg.MedicalMinigame.__zcity_delta_loaded then return end
hg.MedicalMinigame.__zcity_delta_loaded = true

local includedPaths = {}

local function SafeInclude(path)
    if includedPaths[path] then return true end
    if not file.Exists(path, "LUA") then return false end

    local ok, err = pcall(include, path)
    if not ok then
        ErrorNoHalt("[zcity-delta-addon] include failed: " .. path .. "\n" .. tostring(err) .. "\n")
        return false
    end

    includedPaths[path] = true
    return true
end

if SERVER then
    AddCSLuaFile("zcity_delta/medical_minigame/sh_init.lua")
    AddCSLuaFile("zcity_delta/medical_minigame/cl_hud.lua")
    AddCSLuaFile("zcity_delta/medical_minigame/sv_logic.lua")
    AddCSLuaFile("zcity_delta/font_override_cl.lua")
    AddCSLuaFile("zcity_delta/medical_menu_cl.lua")
    AddCSLuaFile("zcity_delta/medical_properties_cl.lua")
    AddCSLuaFile("zcity_delta/commands_cl.lua")
    AddCSLuaFile("zcity_delta/dislocation_radial_cl.lua")
    resource.AddFile("sound/zcity_delta/miserable.mp3")
end

local sharedModules = {
    "zcity_delta/medical_minigame/sh_init.lua",
}

local serverModules = {
    "zcity_delta/medical_minigame/sv_logic.lua"
}

local clientModules = {
    "zcity_delta/font_override_cl.lua",
    "zcity_delta/medical_minigame/cl_hud.lua",
    "zcity_delta/medical_menu_cl.lua",
    "zcity_delta/medical_properties_cl.lua",
    "zcity_delta/commands_cl.lua",
    "zcity_delta/dislocation_radial_cl.lua",
    "zcity_delta/unitmenu_cl.lua"
}

local function LoadModuleList(list)
    for _, path in ipairs(list) do
        SafeInclude(path)
    end
end

local function LoadDeltaBootstrap()
    SafeInclude("zcity_delta/medical_minigame/sh_init.lua")
    LoadModuleList(sharedModules)

    if SERVER then
        LoadModuleList(serverModules)
        print("[zcity-delta-addon] medical minigame loaded (server)")
    else
        LoadModuleList(clientModules)
        print("[zcity-delta-addon] medical minigame loaded (client)")

        timer.Simple(1, function()
            if not IsValid(LocalPlayer()) then return end
            notification.AddLegacy("zcity-delta-addon: medical loaded", NOTIFY_GENERIC, 5)
        end)
    end
end

local function ApplyZCityDeltaPatches()
    if hg.__zcity_delta_patched then return end
    hg.__zcity_delta_patched = true

    if SERVER then
        return
    end
end

hook.Add("HomigradRun", "zcity_delta_apply_patches", ApplyZCityDeltaPatches)
hook.Add("Initialize", "zcity_delta_bootstrap", LoadDeltaBootstrap)
hook.Add("InitPostEntity", "zcity_delta_bootstrap_post", LoadDeltaBootstrap)
hook.Add("OnReloaded", "zcity_delta_bootstrap_reload", LoadDeltaBootstrap)

LoadDeltaBootstrap()

timer.Simple(0, function()
    LoadDeltaBootstrap()
    if hg and hg.loaded then
        ApplyZCityDeltaPatches()
    end
end)

timer.Simple(1, function()
    LoadDeltaBootstrap()
end)
