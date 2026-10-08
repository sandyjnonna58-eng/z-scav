--[[
    Z-SCAV: пока идёт таймер умирания, все звуки мира плавно затихают -
    остаётся только музыка умирания (Dying).

    Музыка Z-SCAV играет отдельным каналом (sound.PlayFile) и сама уходит в тишину
    при умирании (Despair, Drowning, усталость, PainDrone, "Is this the end", Fury-13).
    Звуки мира глушатся движковым затуханием "soundfade" (команда volume_sfx на серверах
    часто заблокирована для Lua). Если и soundfade заблокирован - мир приглушается фильтром (DSP).
    Выключить: zscav_dying_silence 0
]]

local cv = CreateClientConVar("zscav_dying_silence", "1", true, false, "Z-SCAV: тишина мира при умирании", 0, 1)

local function CanRun(cmd)
    if IsConCommandBlocked and IsConCommandBlocked(cmd) then return false end
    return true
end
local function SafeRun(cmd, ...)
    if not CanRun(cmd) then return false end
    return pcall(RunConsoleCommand, cmd, ...)
end

local active, nextFade, dspSet = false, 0, false

local function Dying()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    local org = ply.organism
    return org and (tonumber(org.deathStateEnd) or 0) > 0 or false
end

hook.Add("Think", "ZSCAV_DyingSilence", function()
    local on = cv:GetBool() and Dying()
    hg.RemDyingSilence = on

    if on then
        if not active then active, nextFade = true, 0 end
        if RealTime() >= nextFade then
            nextFade = RealTime() + 1
            -- soundfade <глушение %> <держать> <затухание> <возврат>
            if not SafeRun("soundfade", "100", "2", "1.5", "1.5") and not dspSet then
                -- запасной вариант: сильно приглушить мир фильтром
                local ply = LocalPlayer()
                if IsValid(ply) then ply:SetDSP(31, false) dspSet = true end
            end
        end
    elseif active then
        active = false
        if dspSet then
            local ply = LocalPlayer()
            if IsValid(ply) then ply:SetDSP(0, false) end
            dspSet = false
        end
        -- soundfade вернёт звук сам через пару секунд
    end
end)
