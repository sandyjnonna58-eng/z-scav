if CLIENT then return end

hg = hg or {}
hg.__zcity_delta_server_boot = hg.__zcity_delta_server_boot or {}

AddCSLuaFile("zcity_delta/medical_minigame/sh_init.lua")
AddCSLuaFile("zcity_delta/medical_minigame/cl_hud.lua")
AddCSLuaFile("autorun/client/zz_zcity_delta_client_boot.lua")
AddCSLuaFile("zcity_delta/font_override_cl.lua")
AddCSLuaFile("zcity_delta/medical_menu_cl.lua")
AddCSLuaFile("zcity_delta/medical_properties_cl.lua")
AddCSLuaFile("zcity_delta/commands_cl.lua")
AddCSLuaFile("zcity_delta/dislocation_radial_cl.lua")
AddCSLuaFile("zcity_delta/unitmenu_cl.lua")

local loaded = hg.__zcity_delta_server_boot

local function SafeInclude(path, key)
    if loaded[key] then return true end

    local ok, err = pcall(include, path)
    if not ok then
        ErrorNoHalt("[zcity-delta-addon] server include failed: " .. path .. "\n" .. tostring(err) .. "\n")
        return false
    end

    loaded[key] = true
    return true
end

local function BootServer()
    SafeInclude("zcity_delta/medical_minigame/sh_init.lua", "medical_shared")
    SafeInclude("zcity_delta/medical_minigame/sv_logic.lua", "medical_server")
end

hook.Add("Initialize", "zcity_delta_server_boot", BootServer)
hook.Add("InitPostEntity", "zcity_delta_server_boot_post", BootServer)
hook.Add("OnReloaded", "zcity_delta_server_boot_reload", BootServer)

BootServer()
timer.Simple(0, BootServer)
timer.Simple(1, BootServer)
