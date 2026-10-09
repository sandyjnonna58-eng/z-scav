--[[
    Z-SCAV: Чумной доктор - способность, выдаётся командой (админ / консоль сервера):
        zscav_plague_doctor [ник] [1|0]   - выдать / забрать (без числа - переключить; без ника - себе)
    Даёт: оружие weapon_zscav_plague (заражение болезнями, отрывание конечностей)
    и быстрый бег (x1.45, см. sh_inertia.lua). Способность остаётся после смерти, пока её не заберут.
]]

local SPEED = 1.45

local function Find(caller, nick)
    if nick and nick ~= "" then
        local low = string.lower(nick)
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), low, 1, true) then return p end
        end
        return
    end
    return caller
end

local function SetPlague(ply, on)
    ply:SetNWBool("zscav_plague", on)
    ply:SetNWFloat("zscav_plague_speed", on and SPEED or 1)
    if on then
        if not ply:HasWeapon("weapon_zscav_plague") then ply:Give("weapon_zscav_plague") end
        ply:Notify("Ты - Чумной доктор. ЛКМ - заразить, R - болезнь, ПКМ - оторвать конечность.", 6, "zscav_plague", 0)
    else
        ply:StripWeapon("weapon_zscav_plague")
        ply:Notify("Способности Чумного доктора забраны.", 4, "zscav_plague", 0)
    end
end

concommand.Add("zscav_plague_doctor", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then caller:ChatPrint("Только для админов.") return end
    local target = Find(caller, args[1])
    if not IsValid(target) then
        local m = "Игрок не найден."
        if IsValid(caller) then caller:ChatPrint(m) else print(m) end
        return
    end
    local on
    if args[2] == "1" then on = true elseif args[2] == "0" then on = false else on = not target:GetNWBool("zscav_plague") end
    SetPlague(target, on)
    local m = target:Nick() .. (on and " - Чумной доктор" or " - больше не Чумной доктор")
    if IsValid(caller) then caller:ChatPrint(m) else print(m) end
end)

-- после возрождения оружие выдаётся снова (гейммод забирает инвентарь при спавне)
hook.Add("PlayerSpawn", "ZSCAV_PlagueDoctor", function(ply)
    if not ply:GetNWBool("zscav_plague") then return end
    timer.Simple(2, function()
        if IsValid(ply) and ply:Alive() and ply:GetNWBool("zscav_plague") and not ply:HasWeapon("weapon_zscav_plague") then
            ply:Give("weapon_zscav_plague")
        end
    end)
end)
