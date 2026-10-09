--[[
    Z-SCAV: медицина только через меню здоровья.

    ЛКМ медициной "в мир" на себя больше не лечит - игрок открывает меню здоровья (N),
    выбирает предмет внизу и нажимает на часть тела. Сервер разрешает применение
    на короткое окно и запускает предмет (или его мини-игру) на выбранную часть.
    Лечение других игроков (ПКМ по ним) работает как раньше.
    Выключить: hg_med_menu_only 0
]]

local cv = CreateConVar("hg_med_menu_only", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Z-SCAV: медицина на себя только через меню здоровья", 0, 1)

local APPLY_TIME = 2.5 -- сек "удержания" для предметов без мини-игры (аптечка, жгут и т.п.)

util.AddNetworkString("rem_med_use")

-- вызывается в начале SWEP:PrimaryAttack медицины. true = не применять
function hg.RemMedGate(wep)
    if not cv:GetBool() then return false end
    if hg.RemIsMedicine and not hg.RemIsMedicine(wep) then return false end -- еда, напитки
    if wep.ZSCAVPills then return false end -- банки с таблетками принимаются сразу, без меню
    local ply = wep:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if (ply.remMedAllowUntil or 0) >= CurTime() and ply.remMedAllowWep == wep then return false end
    if (ply.remMedHintT or 0) < CurTime() then
        ply.remMedHintT = CurTime() + 4
        ply:Notify("Медицину на себя применяй через меню здоровья (N).", 4, "rem_med_hint", 0)
    end
    return true
end

-- предметы с мини-игрой аддона zcity_delta (жгут, набор от ушибов)
local DELTA_MINIGAME = {weapon_tourniquet = true, weapon_bruicekit = true}

local function IsMinigameItem(wep)
    local cls = wep:GetClass()
    return (hg.RemBandageMG and hg.RemBandageMG.classes and hg.RemBandageMG.classes[cls])
        or (hg.RemSyringeMG and hg.RemSyringeMG.classes and hg.RemSyringeMG.classes[cls])
        or DELTA_MINIGAME[cls]
end

-- режущее оружие для ампутации
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

local DISLOC_GROUP = {rleg = 1, lleg = 1, rarm = 2, larm = 2}

local OPIATES = {weapon_morphine = true, weapon_fentanyl = true}

net.Receive("rem_med_use", function(_, ply)
    local wep = net.ReadEntity()
    local partId = net.ReadString()
    local action = net.ReadUInt(2) -- 0 медицина, 1 руки (осколок / вывих), 2 ампутация
    if not IsValid(ply) or not ply:Alive() then return end
    local part = hg.RemParts[partId]
    if not part then return end
    local org = ply.organism

    -- Z-SCAV (CU): при плохом настроении действие в меню здоровья может "не получиться"
    if action ~= 2 and hg.organism.RefuseChance and (ply.remMedNextUse or 0) <= CurTime() then
        local c = hg.organism.RefuseChance(org)
        if c > 0 and math.Rand(0, 1) < c then
            ply.remMedNextUse = CurTime() + 0.5
            ply:Notify(table.Random({"Не могу себя заставить..", "Какой смысл..", "Руки не слушаются."}), 3, "zscav_apathy", 0)
            return
        end
    end

    if action == 1 then
        if (ply.remMedNextUse or 0) > CurTime() then return end
        ply.remMedNextUse = CurTime() + 0.5
        -- 1) осколки в этой части
        if org and org.remShards then
            for _, s in ipairs(org.remShards) do
                if s.part == partId then
                    hg.organism.StartShardExtract(ply, partId)
                    return
                end
            end
        end
        -- 2) вывих (мини-игра вправления из zcity_delta)
        local group = (partId == "head" and org and org.jawdislocation) and 3
            or (part.limb and org and org[part.limb .. "dislocation"] and DISLOC_GROUP[part.limb])
        if group and hg.MedicalMinigame and hg.MedicalMinigame.StartDislocationMinigame then
            if (org.pain or 0) > 60 then
                ply:Notify("Слишком больно, чтобы вправлять. Сначала обезболь.", 4, "rem_disloc_pain", 0)
                return
            end
            hg.MedicalMinigame.StartDislocationMinigame(ply, ply, group)
            return
        end
        ply:Notify("Руками здесь нечего делать: " .. part.name, 3, "rem_hands_none", 0)
        return
    end

    if action == 2 then
        if (ply.remMedNextUse or 0) > CurTime() then return end
        ply.remMedNextUse = CurTime() + 0.5
        if not IsValid(wep) or wep:GetOwner() ~= ply or not hg.RemIsBlade(wep) then return end
        if not part.limb then
            ply:Notify("Это нельзя ампутировать.", 3, "rem_amp_no", 0)
            return
        end
        if hg.MedicalMinigame and hg.MedicalMinigame.StartAmputationMinigame then
            if ply:GetActiveWeapon() ~= wep then ply:SelectWeapon(wep:GetClass()) end
            hg.MedicalMinigame.StartAmputationMinigame(ply, ply, part.limb)
        end
        return
    end
    if not IsValid(wep) or wep:GetOwner() ~= ply or not hg.RemIsMedicine(wep) then return end
    if (ply.remMedNextUse or 0) > CurTime() then return end
    -- Z-SCAV (CU, Miserable): ниже -75 настроения из меню можно использовать только опиаты
    if org and (org.mood or 0) < -0.75 and not OPIATES[wep:GetClass()] then
        ply.remMedNextUse = CurTime() + 0.5
        ply:Notify("Нет сил заниматься этим. Только опиаты...", 3, "zscav_miserable", 0)
        return
    end
    ply.remMedNextUse = CurTime() + 0.5

    -- Z-SCAV: антисептик - сразу на выбранную часть
    if wep:GetClass() == "weapon_zscav_antiseptic" then
        if hg.ZSCAVAntiseptic then hg.ZSCAVAntiseptic(ply, partId, wep) end
        return
    end

    ply.remMedPart = partId
    ply.remMedPartT = CurTime()
    -- бинт/аптечка на часть = дезинфекция (иммунитет и инфекции, sv_rem_immunity.lua)
    local cls = wep:GetClass()
    if hg.organism.Disinfect and (string.find(cls, "bandage", 1, true) or string.find(cls, "medkit", 1, true)) then
        hg.organism.Disinfect(ply.organism, partId)
    end
    -- Z-SCAV: бинт и аптечка восстанавливают кожу на этой части
    if hg.organism.HealSkin then
        if string.find(cls, "medkit", 1, true) then hg.organism.HealSkin(ply.organism, partId, 40)
        elseif string.find(cls, "bandage", 1, true) then hg.organism.HealSkin(ply.organism, partId, 25) end
    end
    -- предмет должен быть в руках (у многих лечение завязано на активное оружие)
    if ply:GetActiveWeapon() ~= wep then ply:SelectWeapon(wep:GetClass()) end

    ply.remMedAllowWep = wep
    if IsMinigameItem(wep) then
        ply.remMedAllowUntil = CurTime() + 0.3
        timer.Simple(0.15, function()
            if IsValid(wep) and IsValid(ply) and wep:GetOwner() == ply then wep:PrimaryAttack() end
        end)
    else
        ply.remMedAllowUntil = CurTime() + APPLY_TIME + 0.2
        ply.remMedApply = {wep = wep, untilT = CurTime() + APPLY_TIME}
    end
end)

-- предметы без мини-игры: как будто держим ЛКМ APPLY_TIME секунд
hook.Add("Think", "REM_MedApply", function()
    for _, ply in ipairs(player.GetAll()) do
        local a = ply.remMedApply
        if not a then continue end
        if not IsValid(a.wep) or a.wep:GetOwner() ~= ply or not ply:Alive() or CurTime() > a.untilT then
            ply.remMedApply = nil
            continue
        end
        if ply:GetActiveWeapon() == a.wep then
            local ok = pcall(a.wep.PrimaryAttack, a.wep)
            if not ok then ply.remMedApply = nil end
        end
    end
end)

-- выбранная в меню часть тела "живёт" недолго
function hg.RemMedTakePart(ply)
    if ply.remMedPart and CurTime() - (ply.remMedPartT or 0) < 2 then
        local p = ply.remMedPart
        ply.remMedPart = nil
        return p
    end
end
