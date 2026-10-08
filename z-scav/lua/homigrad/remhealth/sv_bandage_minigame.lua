--[[
    REM: мини-игра перевязки (серверная часть).

    Когда игрок перевязывает САМ СЕБЯ бинтом (ЛКМ), вместо мгновенного лечения
    открывается мини-игра: нужно сделать несколько витков бинта, нажимая ЛКМ,
    когда стрелка проходит через зелёную зону.

      * чем точнее витки, тем больше бинт лечит; кривые витки тратят бинт впустую
      * промах - бинт дёргает рану: немного боли
      * ПКМ - отменить (бинт не тратится)

    Перевязка другого человека (ПКМ по нему) работает как раньше.
    Выключить мини-игру на сервере: hg_bandage_minigame 0
]]

hg.RemBandageMG = hg.RemBandageMG or {}
local MG = hg.RemBandageMG

-- Z-SCAV: по умолчанию бинты идут через мини-игру из zcity_delta (autorun/zz_zcity_delta_med_wep_patch.lua),
-- эта (обмотка кругами) остаётся запасной: hg_bandage_minigame 1 + убрать бинты из списка патча
local cv = CreateConVar("hg_bandage_minigame", "0", FCVAR_ARCHIVE + FCVAR_REPLICATED, "REM: мини-игра при перевязке себя бинтом", 0, 1)

MG.classes = {
    weapon_bandage_sh = true,
    weapon_bigbandage_sh = true,
}
MG.MISS_PAIN   = 4     -- боль за промах
MG.WASTE       = 0.5   -- какая доля "несработавшего" бинта теряется (остальное остаётся)
MG.MIN_QUALITY = 0.15  -- даже очень плохая перевязка чуть-чуть помогает

util.AddNetworkString("rem_bandage_mg")
util.AddNetworkString("rem_bandage_mg_done")

-- названия частей тела для заголовка
local PART_NAMES = {
    ["ValveBiped.Bip01_Head1"] = "ГОЛОВА",
    ["ValveBiped.Bip01_Neck1"] = "ШЕЯ",
    ["ValveBiped.Bip01_Spine4"] = "ГРУДЬ", ["ValveBiped.Bip01_Spine3"] = "ГРУДЬ", ["ValveBiped.Bip01_Spine2"] = "ГРУДЬ",
    ["ValveBiped.Bip01_Spine1"] = "ЖИВОТ", ["ValveBiped.Bip01_Spine"] = "ЖИВОТ", ["ValveBiped.Bip01_Pelvis"] = "ТАЗ",
    ["ValveBiped.Bip01_R_UpperArm"] = "ПРАВОЕ ПЛЕЧО", ["ValveBiped.Bip01_R_Forearm"] = "ПРАВОЕ ПРЕДПЛЕЧЬЕ", ["ValveBiped.Bip01_R_Hand"] = "ПРАВАЯ КИСТЬ",
    ["ValveBiped.Bip01_L_UpperArm"] = "ЛЕВОЕ ПЛЕЧО", ["ValveBiped.Bip01_L_Forearm"] = "ЛЕВОЕ ПРЕДПЛЕЧЬЕ", ["ValveBiped.Bip01_L_Hand"] = "ЛЕВАЯ КИСТЬ",
    ["ValveBiped.Bip01_R_Thigh"] = "ПРАВОЕ БЕДРО", ["ValveBiped.Bip01_R_Calf"] = "ПРАВАЯ ГОЛЕНЬ", ["ValveBiped.Bip01_R_Foot"] = "ПРАВАЯ СТОПА",
    ["ValveBiped.Bip01_L_Thigh"] = "ЛЕВОЕ БЕДРО", ["ValveBiped.Bip01_L_Calf"] = "ЛЕВАЯ ГОЛЕНЬ", ["ValveBiped.Bip01_L_Foot"] = "ЛЕВАЯ СТОПА",
}

-- есть ли что перевязывать (то же условие, что в SWEP:Bandage)
local function NeedsBandage(org)
    return #(org.wounds or {}) > 0 or org.lleg == 1 or org.rleg == 1 or (org.skull or 0) >= 0.6
        or org.chest == 1 or org.rarm == 1 or org.larm == 1
end

local function TargetName(org)
    local wounds = org.wounds or {}
    if #wounds > 0 then
        table.sort(wounds, function(a, b) return a[1] > b[1] end)
        local bone = wounds[1][4]
        if isnumber(bone) and IsValid(org.owner) then bone = org.owner:GetBoneName(bone) end
        return PART_NAMES[bone] or "РАНА", wounds[1][1] or 0
    end
    if (org.skull or 0) >= 0.6 then return "ГОЛОВА", 0 end
    if org.chest == 1 then return "ГРУДЬ", 0 end
    if org.lleg == 1 then return "ЛЕВАЯ НОГА", 0 end
    if org.rleg == 1 then return "ПРАВАЯ НОГА", 0 end
    if org.larm == 1 then return "ЛЕВАЯ РУКА", 0 end
    if org.rarm == 1 then return "ПРАВАЯ РУКА", 0 end
    return "РАНА", 0
end

-- вызывается из SWEP:PrimaryAttack. true = "не лечить сейчас, идёт мини-игра"
function MG.Intercept(wep)
    if not cv:GetBool() then return false end
    if not MG.classes[wep:GetClass()] then return false end

    local ply = wep:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    -- только что закончили - не начинаем сразу новую, пока держат ЛКМ
    if (ply.remBandageMGCooldown or 0) > CurTime() then return true end

    -- уже идёт - просто глушим автоматическую атаку
    if ply.remBandageMG then
        if IsValid(ply.remBandageMG.wep) and ply.remBandageMG.until_ > CurTime() then return true end
        ply.remBandageMG = nil
    end

    -- как в оригинале: лечим самого игрока (его organism общий с рэгдоллом)
    local ent = ply
    local org = ply.organism
    if not org or not org.alive then return false end
    if (wep.modeValues and wep.modeValues[1] or 0) <= 0 then return false end
    if not NeedsBandage(org) then return true end -- нечего бинтовать - ничего не делаем

    local name, size = TargetName(org)
    local bone

    -- часть тела, выбранная в меню здоровья
    local partId = hg.RemMedTakePart and hg.RemMedTakePart(ply)
    local part = partId and hg.RemParts and hg.RemParts[partId]
    if part then
        local best
        for _, w in ipairs(org.wounds or {}) do
            local b = w[4]
            if isnumber(b) then b = ply:GetBoneName(b) end
            if hg.RemPartByBone[b] == partId and (not best or w[1] > best[1]) then best = w bone = b end
        end
        local broken = part.limb and org[part.limb] == 1
        if not best and not broken then
            ply:Notify("Здесь нечего бинтовать: " .. part.name, 3, "rem_bandage_none", 0)
            return true
        end
        name, size = part.name, best and best[1] or 0
    end
    local needed = 3 + (size > 15 and 1 or 0) + (size > 35 and 1 or 0)

    -- сложность: боль и кровопотеря трясут руки
    local diff = math.Clamp((org.pain or 0) / 100 * 0.6 + math.max(0, 4000 - (org.blood or 5000)) / 1500 * 0.4, 0, 1)

    ply.remBandageMG = {
        wep = wep, ent = ent, start = CurTime(), needed = needed, bone = bone,
        until_ = CurTime() + 30,
    }

    net.Start("rem_bandage_mg")
        net.WriteEntity(wep)
        net.WriteString(name)
        net.WriteUInt(needed, 4)
        net.WriteFloat(diff)
    net.Send(ply)

    ply:EmitSound("physics/body/body_medium_impact_soft5.wav", 50, math.random(95, 105))
    return true
end

net.Receive("rem_bandage_mg_done", function(_, ply)
    local wep = net.ReadEntity()
    local cancelled = net.ReadBool()
    local quality = math.Clamp(net.ReadFloat(), 0, 1)
    local misses = math.min(net.ReadUInt(4), 15)

    local st = ply.remBandageMG
    ply.remBandageMG = nil
    ply.remBandageMGCooldown = CurTime() + 0.8
    if not st or st.wep ~= wep or not IsValid(wep) or wep:GetOwner() ~= ply then return end
    if cancelled then return end

    -- защита от "мгновенной" перевязки
    if CurTime() - st.start < st.needed * 0.25 then return end

    local ent = ply
    local org = ply.organism
    if not org or not org.alive then return end

    if misses > 0 then
        org.painadd = (org.painadd or 0) + misses * MG.MISS_PAIN
    end

    local avail = wep.modeValues[1] or 0
    if avail <= 0 then return end
    local q = math.max(quality, MG.MIN_QUALITY)
    local power = avail * q

    wep.modeValues[1] = power
    local done = wep:Bandage(ent, st.bone)
    local leftover = wep.modeValues[1] or 0
    wep.modeValues[1] = math.max(0, leftover + (avail - power) * (1 - MG.WASTE))
    if wep.modeValues[1] < 0.1 then wep.modeValues[1] = 0 end

    if done and wep.PostHeal then wep:PostHeal(ent, wep.mode) end
    -- ровно перевязался - чуть легче на душе
    if done and quality > 0.7 and hg.organism.AddJoy then hg.organism.AddJoy(org, 0.05 * quality) end
    wep:SetNetVar("modeValues", wep.modeValues)

    if wep.modeValues[1] <= 0 and wep.ShouldDeleteOnFullUse then
        ply:SelectWeapon("weapon_hands_sh")
        wep:Remove()
    end
end)

hook.Add("PlayerDeath", "REM_BandageMG", function(ply) ply.remBandageMG = nil end)
