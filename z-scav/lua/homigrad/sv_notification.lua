util.AddNetworkString("HGNotificate")
util.AddNetworkString("HGNotificateBerserk")
util.AddNetworkString("HGThought")

--local hg_old_notificate = ConVarExists("hg_old_notificate") and GetConVar("hg_old_notificate") or CreateConVar("hg_old_notificate",0,FCVAR_SERVER_CAN_EXECUTE,"enable old notifications (chatprints)",0,1)
local hev_color = Color(255,125,0)
local CreateThought
local thoughtMessages = {
    panicattack_start = "У вас паническая атака.",
    panicattack_heartstop = "Ваше сердце остановилось.",
    wake = "Вы пришли в сознание.",
    dislocations_unlucky = "Сустав встал на место.",
    painfromjawspeak = "Челюсть болит, когда вы говорите.",
    arteria = "Из сонной артерии хлещет кровь.",
    take_gasmask = "Противогаз вас душит.",
    take_gasmask2 = "Противогаз вас душит.",
    oxygen_lowintake = "Вам не хватает воздуха.",
    lowoxy = "У вас мало кислорода.",
    lowoxy2 = "У вас мало кислорода.",
    drugged = "Вы под препаратами.", 
    pneumothorax1 = "Что-то заполняет ваши лёгкие.",
    pneumothorax2 = "Дышать становится тяжелее.",
    pneumothorax3 = "Вы задыхаетесь.",
    brain = "Ваш мозг повреждён.",
    blood2 = "Вы на грани обморока.",
    internalbleed = "У вас внутреннее кровотечение.",
    hungry = "Вы голодны.",
    heart = "Резкая боль в груди.",
    heartstop = "Ваше сердце остановилось.",
    painfrommoving = "Нога болит при движении.",
    painfromjaw = "Челюсть болит.",
    painfromribs = "Из-за сломанных рёбер больно дышать.",
}

local scpcbHitgroupToCat = {
    [HITGROUP_HEAD] = "head",
    [HITGROUP_CHEST] = "chest",
    [HITGROUP_STOMACH] = "stomach",
    [HITGROUP_LEFTARM] = "leftarm",
    [HITGROUP_RIGHTARM] = "rightarm",
    [HITGROUP_LEFTLEG] = "leftleg",
    [HITGROUP_RIGHTLEG] = "rightleg",
    [HITGROUP_GENERIC] = "generic",
    [8] = "pelvis"
}

local scpcbThoughts = {
    head = {
        "{weapon} — удар в голову. Мгновенная смерть.",
        "{weapon} — попадание в голову. Мгновенная смерть.",
        "{weapon} пробивает череп. Мгновенная смерть.",
        "{weapon} — попадание в висок. Мгновенная смерть.",
        "{weapon} раскалывает череп. Мгновенная смерть.",
        "{weapon} разрывает мозг. Мгновенная смерть.",
        "{weapon} — попадание в лоб. Мгновенная смерть.",
        "{weapon} — удар в голову. Смерть мозга.",
        "{weapon} разбивает голову. Всё кончено."
    },
    pelvis = {
        "{weapon} пробивает таз, едва не задев самое ценное.",
        "{weapon} — попадание в поясницу. Сильная боль.",
        "{weapon} — попадание в таз. Вас передёргивает.",
        "{weapon} задевает пах, едва не задев самое ценное.",
        "{weapon} раздробляет бедро. Вы спотыкаетесь."
    },
    pelvis_lethal = {
        "{weapon} разрушает таз. Смертельная кровопотеря.",
        "{weapon} разрывает поясницу, перебив артерию.",
        "{weapon} раздробляет таз. Смерть от шока."
    },
    head_nonlethal = {
        "{weapon} — попадание в голову. Сильная боль.",
        "{weapon} — удар в голову.",
        "{weapon} — попадание в череп. Кружится голова.",
        "{weapon} задевает голову, оставив рваную рану.",
        "{weapon} — удар в череп. Вы оглушены.",
        "{weapon} — попадание в голову. У вас перехватывает дыхание."
    },
    chest = {
        "{weapon} — попадание в грудь. У вас перехватывает дыхание.",
        "{weapon} — удар в грудь. У вас перехватывает дыхание.",
        "{weapon} — попадание в рёбра. Сильная боль.",
        "{weapon} — удар в грудь. Дышать становится трудно.",
        "{weapon} пробивает грудь.",
        "{weapon} — попадание в грудь. Больно."
    },
    chest_lethal = {
        "{weapon} — удар в грудь. Смертельные внутренние травмы.",
        "{weapon} — попадание в грудь. Сердце разорвано.",
        "{weapon} пробивает лёгкое. Вы захлёбываетесь кровью.",
        "{weapon} — удар в грудь. Мгновенная смерть.",
        "{weapon} раздробляет грудную клетку и пробивает сердце."
    },
    stomach = {
        "{weapon} — попадание в живот. У вас перехватывает дыхание.",
        "{weapon} — удар в живот. Сильная боль.",
        "{weapon} — попадание в живот.",
        "{weapon} — удар в живот. Больно.",
        "{weapon} пробивает живот."
    },
    stomach_lethal = {
        "{weapon} — удар в живот. Смертельное внутреннее кровотечение.",
        "{weapon} разрывает живот. Смерть.",
        "{weapon} — попадание в печень. Сильное кровотечение.",
        "{weapon} разрушает желудок. Смерть."
    },
    leftarm = {
        "{weapon} — попадание в левую руку.",
        "{weapon} — удар в левую руку.",
        "{weapon} — попадание в левое плечо.",
        "{weapon} — удар в левое предплечье.",
        "{weapon} пробивает левую руку."
    },
    leftarm_lethal = {
        "{weapon} отсекает левую руку. Смертельная кровопотеря.",
        "{weapon} разрывает левую руку, задев артерию.",
        "{weapon} раздробляет левое плечо. Смерть от шока.",
        "{weapon} разрушает левую руку. Вы истекаете кровью."
    },
    rightarm = {
        "{weapon} — попадание в правую руку.",
        "{weapon} — удар в правую руку.",
        "{weapon} — попадание в правое плечо.",
        "{weapon} — удар в правое предплечье.",
        "{weapon} пробивает правую руку."
    },
    rightarm_lethal = {
        "{weapon} отсекает правую руку. Смертельная кровопотеря.",
        "{weapon} разрывает правую руку, задев артерию.",
        "{weapon} раздробляет правое плечо. Смерть от шока.",
        "{weapon} разрушает правую руку. Вы истекаете кровью."
    },
    leftleg = {
        "{weapon} — попадание в левую ногу.",
        "{weapon} — удар в левую ногу.",
        "{weapon} — попадание в левое бедро.",
        "{weapon} — удар в левую голень.",
        "{weapon} — попадание в левое колено.",
        "{weapon} пробивает левую ногу."
    },
    leftleg_lethal = {
        "{weapon} отсекает левую ногу. Смертельная кровопотеря.",
        "{weapon} разрывает левое бедро, перебив бедренную артерию.",
        "{weapon} раздробляет левую ногу. Смерть от шока.",
        "{weapon} разрушает левую ногу. Вы истекаете кровью."
    },
    rightleg = {
        "{weapon} — попадание в правую ногу.",
        "{weapon} — удар в правую ногу.",
        "{weapon} — попадание в правое бедро.",
        "{weapon} — удар в правую голень.",
        "{weapon} — попадание в правое колено.",
        "{weapon} пробивает правую ногу."
    },
    rightleg_lethal = {
        "{weapon} отсекает правую ногу. Смертельная кровопотеря.",
        "{weapon} разрывает правое бедро, перебив бедренную артерию.",
        "{weapon} раздробляет правую ногу. Смерть от шока.",
        "{weapon} разрушает правую ногу. Вы истекаете кровью."
    },
    generic = {
        "{weapon} — попадание.",
        "{weapon} — удар.",
        "{weapon} — попадание в тело.",
        "{weapon} — удар в торс.",
        "{weapon} — попадание. Больно."
    },
    generic_lethal = {
        "{weapon} — попадание. Мгновенная смерть.",
        "{weapon} — удар. Смертельная травма.",
        "{weapon} — попадание в тело. Смерть.",
        "{weapon} пробивает насквозь. Смертельное ранение."
    },
    near_miss = {
        "{weapon} пролетает совсем рядом.",
        "{weapon} свистит у самой головы.",
        "{weapon} пролетает у уха.",
        "{weapon} едва не попадает в вас.",
        "{weapon} проносится вплотную.",
        "{weapon} проходит в сантиметрах от головы.",
        "{weapon} пролетает мимо.",
        "{weapon} промахивается, но едва-едва."
    },
    armor_full = {
        "{weapon} — попадание в грудь. Жилет принял почти весь удар.",
        "{weapon} — попадание в грудь. Жилет принял часть удара.",
        "{weapon} — удар в жилет. Броня погасила удар.",
        "{weapon} — попадание в жилет.",
        "{weapon} — удар в жилет."
    },
    armor_partial = {
        "{weapon} — попадание в грудь. Жилет принял часть удара.",
        "{weapon} — удар в грудь. Жилет пробит.",
        "{weapon} — попадание в грудь. Пластина треснула, но удержала.",
        "{weapon} — удар в жилет, частичное пробитие.",
        "{weapon} — попадание в грудь. Броня ослабила удар, но он прошёл."
    }
}

local function SCPCBThoughtDamageType(dmginfo, target)
    if dmginfo:IsBulletDamage() or dmginfo:IsDamageType(DMG_BUCKSHOT) then return "bullet" end
    if dmginfo:IsDamageType(DMG_SLASH) then return "slash" end
    if dmginfo:IsDamageType(DMG_CLUB) or dmginfo:IsDamageType(DMG_CRUSH) then return "blunt" end

    local inflictor = dmginfo:GetInflictor()
    local attacker = dmginfo:GetAttacker()
    local wep = IsValid(inflictor) and inflictor or (IsValid(attacker) and attacker.GetActiveWeapon and attacker:GetActiveWeapon())

    if IsValid(wep) then
        if wep:GetClass() == "weapon_melee" or wep.Base == "weapon_melee" or wep.DamageType then
            return wep.DamageType == DMG_SLASH and "slash" or "blunt"
        end

        if wep.Base == "homigrad_base" or wep.Primary and wep.Primary.Ammo then
            return "bullet"
        end
    end

    if dmginfo:GetDamage() >= target:Health() then return "generic" end
end

local function SCPCBThoughtHitgroup(target, dmgType, dmginfo, hitPos)
    if dmgType == "generic" then return HITGROUP_GENERIC end

    hitPos = hitPos or dmginfo:GetDamagePosition()
    local plyPos = target:GetPos() + Vector(0, 0, target:OBBMins().z)
    local height = target:OBBMaxs().z - target:OBBMins().z
    local hitHeight = hitPos.z - plyPos.z

    if hitHeight > height * 0.85 then return HITGROUP_HEAD end

    local right = target:GetRight()
    local toHit = hitPos - plyPos
    toHit.z = 0
    toHit:Normalize()

    if hitHeight > height * 0.4 then
        local rightDot = right:Dot(toHit)

        if math.abs(rightDot) > 0.7 and hitHeight > height * 0.5 then
            return rightDot > 0 and HITGROUP_RIGHTARM or HITGROUP_LEFTARM
        end

        if hitHeight > height * 0.6 then return HITGROUP_CHEST end
        if hitHeight > height * 0.5 then return HITGROUP_STOMACH end
        return 8
    end

    return right:Dot(toHit) > 0 and HITGROUP_RIGHTLEG or HITGROUP_LEFTLEG
end

local function SCPCBArmorProtection(ent, ply, hitgroup)
    local placement

    if hitgroup == HITGROUP_CHEST or hitgroup == HITGROUP_STOMACH or hitgroup == HITGROUP_GENERIC or hitgroup == 8 then
        placement = "torso"
    else
        return 0
    end

    local armors = (IsValid(ent) and ent.armors) or ply.armors
    if not armors then return 0 end

    local armor = armors[placement]
    local armorData = armor and hg.armor and hg.armor[placement] and hg.armor[placement][armor]
    if not armorData then return 0 end

    local broken = ((IsValid(ent) and ent.armors_broken) or ply.armors_broken or {})[armor]
    return broken and 0 or (armorData.protection or 0)
end

local SCPCBCreateThought

local function SCPCBHitThought(ply, target, dmgType, dmg, hitPos, dmginfo)
    if not dmg or dmg <= 0 then return end

    local isLethal = dmg >= ply:Health()
    local hitgroup = SCPCBThoughtHitgroup(target, dmgType, dmginfo, hitPos)
    local category = scpcbHitgroupToCat[hitgroup] or "generic"

    ply.scpcbThoughtHitTime = CurTime() + 0.25

    if !isLethal and SCPCBArmorProtection(target, ply, hitgroup) > 0 then
        category = dmg > SCPCBArmorProtection(target, ply, hitgroup) and "armor_partial" or "armor_full"
    elseif !isLethal and hitgroup == HITGROUP_HEAD then
        category = "head_nonlethal"
    end

    SCPCBCreateThought(ply, category, dmgType, isLethal)
end

SCPCBCreateThought = function(ply, category, dmgType, isLethal)
    if not CreateThought or not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:GetInfoNum("hg_newthoughts", 0) <= 0 then return end
    if isLethal then return end

    local curTime = CurTime()
    ply.scpcbThoughtNext = ply.scpcbThoughtNext or 0

    if !isLethal and ply.scpcbThoughtNext > curTime then return end

    local targetCategory = category
    if isLethal and category != "head" and category != "near_miss" and category != "armor_full" and category != "armor_partial" then
        targetCategory = category .. "_lethal"
    end

    local options = scpcbThoughts[targetCategory] or scpcbThoughts.generic
    if not options then return end

    local weaponStr = "bullet"
    if dmgType == "blunt" then weaponStr = "тупой предмет" end
    if dmgType == "slash" then weaponStr = "острый предмет" end
    if dmgType == "generic" then weaponStr = "impact" end

    local msg = string.gsub(options[math.random(1, #options)], "{weapon}", weaponStr)
    local delay = isLethal and 1 or (category == "near_miss" and 12 or 8)

    if CreateThought(ply, msg, delay, "scpcb_damage_" .. targetCategory, 0, color_white) then
        ply.scpcbThoughtNext = curTime + (isLethal and 1 or (category == "near_miss" and 6 or 4))
    end
end

local function SCPCBThoughtOwner(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end

    if hg and hg.RagdollOwner then
        local ply = hg.RagdollOwner(ent)
        if IsValid(ply) then return ply end
    end

    local ply = ent.ply
    if IsValid(ply) and ply:IsPlayer() then return ply end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply.FakeRagdoll) and ply.FakeRagdoll == ent then return ply end
        if hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) == ent then return ply end
    end
end

local function CreateNotification(ply, msg, delay, msgKey, showTime, func, clr)
    if ply.organism and ply.organism.otrub then return end
    if ply.PlayerClassName and ply.PlayerClassName == "Gordon" and clr != hev_color then return end
    if msg == "" then return end
    if not IsValid(ply) or not ply:IsPlayer() then error("player is not valid!") return false end
    if not msg or not isstring(msg) then error("no message or message is invalid!") return false end
    msgKey = msgKey or msg

    if ply:GetInfoNum("hg_newthoughts", 0) > 0 and thoughtMessages[msgKey] and CreateThought then
        return CreateThought(ply, thoughtMessages[msgKey], delay, "thought_" .. msgKey, showTime, clr)
    end

    ply.msgs = ply.msgs or {}
    if msgKey and ply.msgs[msgKey] then
        if isnumber(ply.msgs[msgKey]) then
            if ply.msgs[msgKey] > CurTime() then
                return false
            end
        else
            return false
        end
    end

    delay = delay or 5

    if msgKey then ply.msgs[msgKey] = delay and (not isnumber(delay) or CurTime() + delay) or nil end
    --показывать один раз за промежуток времени
    --(если delay не номерок то оно пинганет в следующей жизни)

    if ply.organism and ply.organism.brain > 0.1 then
        for i = 1, utf8.len(msg) do
            if math.random(3) == 1 and msg[i] != "?" and msg[i] != "." then
                msg = hg.replace_by_index(msg, i, (math.random(1,2) > 1 and "m" or "b") )
            end
        end
    end
    
    showTime = showTime or 0

    local clr = clr or color_white
    local clr2 = Color(clr.r, clr.g, clr.b, 255)

    timer.Simple(showTime, function()
        if !IsValid(ply) then return end
        if !ply.msgs[msgKey] then return end

        if (ply.organism and ply.organism.otrub) or !ply:Alive() then
            return
        end

        if ply.organism and ply.organism.pain > 60 and (!clr or clr.g > 250) then
            return
        end

        if func and isfunction(func) then
            if func(ply) then return end
        end

        net.Start("HGNotificate")
        net.WriteString(msg)
        //net.WriteFloat(showTime or 3)
        net.WriteColor(clr2)
        net.Send(ply)
    end)

    return true
end

//erm it's ass but i don't care enough
local function CreateNotificationBerserk(ply, msg, delay, msgKey, showTime, func, clr)
    if ply.organism and ply.organism.otrub then return end
    if ply.PlayerClassName and ply.PlayerClassName == "Gordon" and clr != hev_color then return end
    if msg == "" then return end
    if not IsValid(ply) or not ply:IsPlayer() then error("player is not valid!") return false end
    if not msg or not isstring(msg) then error("no message or message is invalid!") return false end
    msgKey = msgKey or msg
    ply.msgs = ply.msgs or {}
    if msgKey and ply.msgs[msgKey] then
        if isnumber(ply.msgs[msgKey]) then
            if ply.msgs[msgKey] > CurTime() then
                return false
            end
        else
            return false
        end
    end

    delay = delay or 0

    if msgKey then ply.msgs[msgKey] = delay and (not isnumber(delay) or CurTime() + delay) or nil end
    --показывать один раз за промежуток времени
    --(если delay не номерок то оно пинганет в следующей жизни)
    if func and isfunction(func) then
        func(ply)
    end

    if ply.organism and ply.organism.brain > 0.1 then
        for i = 1, utf8.len(msg) do
            if math.random(3) == 1 and msg[i] != "?" and msg[i] != "." then
                msg = hg.replace_by_index(msg, i, (math.random(1,2) > 1 and "m" or "b") )
            end
        end
    end
    
    showTime = showTime or 0

    local clr = clr or color_white
    local clr2 = Color(clr.r, clr.g, clr.b, 255)

    timer.Simple(showTime, function()
        if !IsValid(ply) then return end
        if !ply.msgs[msgKey] then return end

        if (ply.organism and ply.organism.otrub) or !ply:Alive() then
            return
        end

        if ply.organism and ply.organism.pain > 60 and (!clr or clr.g > 250) then
            return
        end

        net.Start("HGNotificateBerserk")
        net.WriteString(msg)
        //net.WriteFloat(showTime or 3)
        net.WriteColor(clr2)
        net.Send(ply)
    end)

    return true
end

local function ResetNotification(ply, key)
    if not ply.msgs or not ply.msgs[key] then return end
    ply.msgs[key] = nil
end

CreateThought = function(ply, msg, delay, msgKey, showTime, clr)
    if ply.organism and ply.organism.otrub then return end
    if msg == "" then return end
    if not IsValid(ply) or not ply:IsPlayer() then error("player is not valid!") return false end
    if not msg or not isstring(msg) then error("no message or message is invalid!") return false end
    if ply:GetInfoNum("hg_newthoughts", 0) <= 0 then return false end

    msgKey = msgKey or msg
    ply.thoughtmsgs = ply.thoughtmsgs or {}
    if msgKey and ply.thoughtmsgs[msgKey] then
        if isnumber(ply.thoughtmsgs[msgKey]) then
            if ply.thoughtmsgs[msgKey] > CurTime() then
                return false
            end
        else
            return false
        end
    end

    delay = delay or 0

    if msgKey then ply.thoughtmsgs[msgKey] = delay and (not isnumber(delay) or CurTime() + delay) or nil end

    showTime = showTime or 0
    local clr = clr or color_white
    local clr2 = Color(clr.r, clr.g, clr.b, 255)

    timer.Simple(showTime, function()
        if !IsValid(ply) then return end
        if !ply.thoughtmsgs[msgKey] then return end
        if (ply.organism and ply.organism.otrub) or !ply:Alive() then return end

        net.Start("HGThought")
        net.WriteString(msg)
        net.WriteColor(clr2)
        net.Send(ply)
    end)

    return true
end

hg.CreateNotification = CreateNotification

hook.Add("Player Spawn","removeNotifications",function(ply)
    ply.msgs = {}
    ply.thoughtmsgs = {}
end)

hook.Add("HG_OnOtrub","removeNotifications",function(ply)
    ply.msgs = {}
    ply.thoughtmsgs = {}
end)

hook.Add("Player_Death","removeNotifications",function(ply)
    ply.msgs = {}
    ply.thoughtmsgs = {}
end)

local PLAYER = FindMetaTable("Player")

function PLAYER:Notify(...)
    return CreateNotification(self, ...)
end

function PLAYER:NotifyBerserk(...)
    return CreateNotificationBerserk(self, ...)
end

function PLAYER:Thought(...)
    return CreateThought(self, ...)
end

function PLAYER:ResetNotification(key)
    ResetNotification(self,key)
end

hook.Add("EntityTakeDamage", "SCPCB_HGThoughtDamage", function(target, dmginfo)
    if not dmginfo or dmginfo:GetDamage() <= 0 then return end

    local ply = SCPCBThoughtOwner(target)
    if not IsValid(ply) then return end
    if dmginfo:IsDamageType(DMG_FALL) or dmginfo:IsDamageType(DMG_CRUSH) then return end

    local dmgType = SCPCBThoughtDamageType(dmginfo, ply)
    if not dmgType then return end

    SCPCBHitThought(ply, target, dmgType, dmginfo:GetDamage(), nil, dmginfo)
end)

hook.Add("EntityFireBullets", "SCPCB_HGThoughtNearMiss", function(entity, data)
    if not IsValid(entity) then return end
    if (data.limit_ricochet or 0) > 0 or (data.penetrated or 0) > 0 then return end

    local oldCallback = data.Callback
    local shooter = IsValid(data.Attacker) and data.Attacker or (entity.GetOwner and entity:GetOwner() or entity)

    data.Callback = function(attacker, tr, dmginfo)
        shooter = IsValid(attacker) and attacker or shooter
        local hitPly = SCPCBThoughtOwner(tr.Entity)
        local blocked = false

        if IsValid(hitPly) and hitPly != shooter then
            blocked = hg.TryExtinguisherBulletBlock and hg.TryExtinguisherBulletBlock(tr.Entity, dmginfo)
            SCPCBHitThought(hitPly, tr.Entity, "bullet", dmginfo:GetDamage(), tr.HitPos, dmginfo)
        end

        local src = data.Src
        local hitPos = tr.HitPos
        local dir = hitPos - src
        local length = dir:Length()

        if length > 0 then
            dir:Normalize()

            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply:Alive() and ply != shooter and ply != entity and ply != hitPly and not blocked and (ply.scpcbThoughtHitTime or 0) < CurTime() then
                    local plyPos = ply:GetPos() + Vector(0, 0, 50)
                    local projection = math.Clamp((plyPos - src):Dot(dir), 0, length)
                    local closestPoint = src + dir * projection

                    if plyPos:Distance(closestPoint) < 125 then
                        SCPCBCreateThought(ply, "near_miss", "bullet", false)
                    end
                end
            end
        end

        if oldCallback then return oldCallback(attacker, tr, dmginfo) end
    end

end)
