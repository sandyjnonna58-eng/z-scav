--[[
    REM: мини-игра укола шприцем (серверная часть).

    Когда игрок колет САМ СЕБЯ (ЛКМ) шприцем из списка ниже:
      1) прицеливание - навести иглу на место укола (бедро или плечо) и нажать ЛКМ
      2) ввод - держать ЛКМ и удерживать угол иглы мышкой. Пока угол в зелёной зоне,
         лекарство вводится (по оригинальной логике самого шприца). Сильно перекосил -
         игла ломается: боль, небольшая рана, шприц испорчен.

    Укол другому человеку (ПКМ по нему) работает как раньше.
    Выключить: hg_syringe_minigame 0
]]

hg.RemSyringeMG = hg.RemSyringeMG or {}
local MG = hg.RemSyringeMG

local cv = CreateConVar("hg_syringe_minigame", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "REM: мини-игра при уколе себе шприцем", 0, 1)

MG.classes = {
    weapon_morphine   = "МОРФИН",
    weapon_fentanyl   = "ФЕНТАНИЛ",
    weapon_adrenaline = "АДРЕНАЛИН",
    weapon_naloxone   = "НАЛОКСОН",
    weapon_betablock  = "БЕТА-БЛОКАТОР",
    weapon_mannitol   = "МАННИТОЛ",
    weapon_fury13     = "FURY-13",
    weapon_fury16     = "НОРАДРЕНАЛИН",
}
MG.MISS_PAIN  = 3   -- укол мимо
MG.BREAK_PAIN = 18  -- сломанная игла
MG.BREAK_BLOOD = 7  -- рана от сломанной иглы: заметное кровотечение

-- места укола (кость модели для раны при поломке)
MG.sites = {
    {id = "r_thigh",    bone = "ValveBiped.Bip01_R_Thigh",    limb = "rleg"},
    {id = "l_thigh",    bone = "ValveBiped.Bip01_L_Thigh",    limb = "lleg"},
    {id = "r_upperarm", bone = "ValveBiped.Bip01_R_UpperArm", limb = "rarm"},
    {id = "l_upperarm", bone = "ValveBiped.Bip01_L_UpperArm", limb = "larm"},
}

util.AddNetworkString("rem_syringe_mg")
util.AddNetworkString("rem_syringe_mg_state")

local function Clear(ply)
    ply.remSyringeMG = nil
    ply.remSyringeMGCooldown = CurTime() + 0.8
end

function MG.Intercept(wep)
    if not cv:GetBool() then return false end
    local drug = MG.classes[wep:GetClass()]
    if not drug then return false end

    local ply = wep:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if (ply.remSyringeMGCooldown or 0) > CurTime() then return true end

    local st = ply.remSyringeMG
    if st then
        if IsValid(st.wep) and st.wep == wep then return true end
        ply.remSyringeMG = nil
    end

    local org = ply.organism
    if not org or not org.alive then return false end
    if (wep.modeValues and wep.modeValues[1] or 0) <= 0 then return false end

    -- место укола: случайная неампутированная конечность
    local free = {}
    for i, s in ipairs(MG.sites) do
        if not org[s.limb .. "amputated"] then free[#free + 1] = i end
    end
    if #free == 0 then return false end -- некуда колоть - как в оригинале
    local site = free[math.random(#free)]
    -- место укола из меню здоровья (бедро/плечо/предплечье/голень)
    local partId = hg.RemMedTakePart and hg.RemMedTakePart(ply)
    local part = partId and hg.RemParts and hg.RemParts[partId]
    if part and part.site and not org[MG.sites[part.site].limb .. "amputated"] then site = part.site end

    local diff = math.Clamp((org.pain or 0) / 100 * 0.5 + math.max(0, 4000 - (org.blood or 5000)) / 1500 * 0.3
        + (org.adrenaline or 0) * 0.05 + ((org.temperature or 36.7) < 35 and 0.2 or 0), 0, 1)

    ply.remSyringeMG = {wep = wep, site = site, start = CurTime(), injecting = false, nextNet = 0}

    net.Start("rem_syringe_mg")
        net.WriteEntity(wep)
        net.WriteString(drug)
        net.WriteUInt(site, 3)
        net.WriteFloat(diff)
    net.Send(ply)
    return true
end

-- клиент сообщает состояние: 0 - игла вошла (или промах), 1 - вводим, 2 - пауза, 3 - сломал, 4 - отмена/конец
net.Receive("rem_syringe_mg_state", function(_, ply)
    local st = ply.remSyringeMG
    local state = net.ReadUInt(3)
    local extra = net.ReadUInt(4)
    if not st or not IsValid(st.wep) or st.wep:GetOwner() ~= ply then return end
    local org = ply.organism
    if not org then return end

    if state == 0 then
        -- extra = промахов при прицеливании
        if extra > 0 then org.painadd = (org.painadd or 0) + math.min(extra, 5) * MG.MISS_PAIN end
        ply:EmitSound("snd_jack_hmcd_needleprick.wav", 55, math.random(95, 105))
        st.inserted = true
    elseif state == 1 then
        if st.inserted then st.injecting = true end
    elseif state == 2 then
        st.injecting = false
        -- extra = "кривой угол": игла рвёт мышцу
        if extra > 0 then org.painadd = (org.painadd or 0) + extra end
    elseif state == 3 then
        if not st.inserted then return end
        org.painadd = (org.painadd or 0) + MG.BREAK_PAIN
        local site = MG.sites[st.site]
        if site and hg.organism.AddWoundManual then
            hg.organism.AddWoundManual(ply, MG.BREAK_BLOOD, vector_origin, angle_zero, site.bone, CurTime())
        end
        ply:EmitSound("physics/glass/glass_bottle_break" .. math.random(1, 2) .. ".wav", 55, math.random(140, 160))
        local wep = st.wep
        Clear(ply)
        ply:SelectWeapon("weapon_hands_sh")
        wep:Remove()
    elseif state == 4 then
        Clear(ply)
    end
end)

-- пока игла в теле и держат ЛКМ под правильным углом - шприц делает своё обычное дело
hook.Add("Think", "REM_SyringeMG", function()
    for _, ply in ipairs(player.GetAll()) do
        local st = ply.remSyringeMG
        if not st then continue end
        local wep = st.wep
        if not IsValid(wep) or wep:GetOwner() ~= ply or not ply:Alive() or CurTime() - st.start > 40 then
            Clear(ply)
            continue
        end
        if st.injecting and (wep.modeValues and wep.modeValues[1] or 0) > 0 then
            local ok, done = pcall(wep.Heal, wep, ply, wep.mode)
            if not IsValid(wep) then Clear(ply) continue end
            if ok and done and wep.PostHeal then wep:PostHeal(ply, wep.mode) end
            if CurTime() >= st.nextNet then
                st.nextNet = CurTime() + 0.1
                wep:SetNetVar("modeValues", wep.modeValues)
            end
        end
    end
end)

hook.Add("PlayerDeath", "REM_SyringeMG", function(ply) ply.remSyringeMG = nil end)
