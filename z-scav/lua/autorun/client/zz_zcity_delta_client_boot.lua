if SERVER then return end

hg = hg or {}
hg.__zcity_delta_client_boot = hg.__zcity_delta_client_boot or {}

local loaded = hg.__zcity_delta_client_boot

local function SafeInclude(path, key)
    if loaded[key] then return true end

    local ok, err = pcall(include, path)
    if not ok then
        ErrorNoHalt("[zcity-delta-addon] client include failed: " .. path .. "\n" .. tostring(err) .. "\n")
        return false
    end

    loaded[key] = true
    return true
end

local function BootClient()
    SafeInclude("zcity_delta/medical_minigame/sh_init.lua", "medical_shared")
    SafeInclude("zcity_delta/medical_minigame/cl_hud.lua", "medical_hud")
    SafeInclude("zcity_delta/medical_menu_cl.lua", "medical_menu")
    SafeInclude("zcity_delta/medical_properties_cl.lua", "medical_properties")
    SafeInclude("zcity_delta/commands_cl.lua", "commands")
    SafeInclude("zcity_delta/unitmenu_cl.lua", "unitmenu")

    hook.Remove("radialOptions", "zcity_delta_dislocation_minigame")
    hook.Remove("radialOptions", "DislocatedJoint")
    hook.Remove("radialOptions", "DislocatedJoint2")
    hook.Remove("radialOptions", "DislocatedJaw")
end

hook.Add("Initialize", "zcity_delta_client_boot", BootClient)
hook.Add("InitPostEntity", "zcity_delta_client_boot_post", BootClient)
hook.Add("OnReloaded", "zcity_delta_client_boot_reload", BootClient)

BootClient()
timer.Simple(0, BootClient)
timer.Simple(1, BootClient)

-- Z-SCAV: на всякий случай снимаем пункты аддона из Q-меню, если их кто-то добавит снова
timer.Simple(0, function()
    hook.Remove("radialOptions", "zcity_delta_medical_amputation")
    hook.Remove("radialOptions", "zcity_delta_dislocation_minigame")
end)
