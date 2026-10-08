if SERVER then return end

if _G.__zcity_delta_unitmenu_command_loaded then return end
_G.__zcity_delta_unitmenu_command_loaded = true

local function EnsureUnitMenuLoaded()
    if isfunction(_G.ZCityDeltaToggleUnitMenu) then return true end
    if not file.Exists("zcity_delta/unitmenu_cl.lua", "LUA") then return false end

    local ok, err = pcall(include, "zcity_delta/unitmenu_cl.lua")
    if not ok then
        ErrorNoHalt("[zcity-delta-addon] unitmenu include failed: zcity_delta/unitmenu_cl.lua\n" .. tostring(err) .. "\n")
        return false
    end

    return isfunction(_G.ZCityDeltaToggleUnitMenu)
end

concommand.Add("hg_unitmenu", function(_, _, args)
    if not EnsureUnitMenuLoaded() then return end

    local ent = nil
    local idx = tonumber(args and args[1] or nil)
    if idx then
        ent = Entity(math.floor(idx))
        if IsValid(ent) and ent:IsRagdoll() and hg and hg.RagdollOwner then
            ent = hg.RagdollOwner(ent) or ent
        end
    end

    if IsValid(ent) and isfunction(_G.ZCityDeltaForceUnitMenuTarget) then
        _G.ZCityDeltaForceUnitMenuTarget(ent)
    end

    _G.ZCityDeltaToggleUnitMenu()
end)
