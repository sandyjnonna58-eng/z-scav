--[[
    Z-SCAV: осколки от взрывов.

    Взрыв рядом - в теле застревают осколки (на случайных частях тела).
    Стекло тоже: ударил/пнул окно, пролетел сквозь него, получил бутылкой или куском стекла -
    осколки стекла в руках/ногах/теле (мельче, сидят неглубоко).
    Пока осколок внутри: рана понемногу кровит, при движении болит.
    Вытащить: меню здоровья (N) -> выбрать "РУКИ" -> нажать на часть с осколком -> мини-игра.
      медленно и ровно - осколок выходит чисто (маленькая рана)
      дёрнул быстро    - рвёт мышцу: сильное кровотечение и боль
]]

hg.organism.shardCfg = hg.organism.shardCfg or {}
local CFG = hg.organism.shardCfg

CFG.MIN_DAMAGE   = 12    -- урон взрывом, с которого летят осколки
CFG.PER_DAMAGE   = 22    -- +1 осколок за столько урона
CFG.MAX_SHARDS   = 8     -- больше в теле не держим
CFG.WOUND_BLOOD  = 3     -- рана от попадания осколка
CFG.REBLEED_TIME = 25    -- пока внутри - рана снова кровит раз в N сек
CFG.REBLEED      = 1.2
CFG.MOVE_PAIN    = 0.25  -- боль в секунду за осколок при беге
CFG.CLEAN_BLOOD  = 1     -- рана после аккуратного извлечения
CFG.CLEAN_PAIN   = 6
CFG.TORN_BLOOD   = 8     -- рана, если дёрнул
CFG.TORN_PAIN    = 20

local HIT_PARTS = {
    "chest", "chest", "abdomen", "abdomen",
    "r_upperarm", "l_upperarm", "r_forearm", "l_forearm",
    "r_thigh", "l_thigh", "r_thigh", "l_thigh", "r_shin", "l_shin",
    "head", "neck", "r_hand", "l_hand", "r_foot", "l_foot",
}

util.AddNetworkString("rem_shard_mg")
util.AddNetworkString("rem_shard_mg_done")

-- осколки уходят клиенту отдельной сетевой переменной: обычная отправка организма
-- на клиенте "сливает" таблицы (table.Merge), и удалённые осколки там не пропадали бы
local function Sync(org)
    local owner = org.owner
    if not IsValid(owner) then return end
    local list = {}
    for i, s in ipairs(org.remShards or {}) do
        list[i] = {id = s.id, part = s.part, kind = s.kind}
    end
    owner:SetNetVar("remShards", list)
end

CFG.GLASS_BLOOD  = 2     -- рана от осколка стекла
CFG.GLASS_COOLDOWN = 0.6 -- не чаще (на игрока)

local function AddShard(ply, org, partId, kind)
    org.remShards = org.remShards or {}
    if #org.remShards >= CFG.MAX_SHARDS then return end
    org.remShardId = (org.remShardId or 0) + 1
    local part = hg.RemParts[partId]
    local bone = part.bones[1]
    local glass = kind == "glass"
    table.insert(org.remShards, {
        id = org.remShardId, part = partId, kind = kind or "metal",
        depth = glass and math.Rand(0.36, 0.5) or math.Rand(0.45, 0.62),
        nextBleed = CurTime() + CFG.REBLEED_TIME,
    })
    if hg.organism.AddWoundManual then
        hg.organism.AddWoundManual(ply, glass and CFG.GLASS_BLOOD or CFG.WOUND_BLOOD, vector_origin, angle_zero, bone, CurTime())
    end
end

hook.Add("EntityTakeDamage", "ZSCAV_Shards", function(ent, dmg)
    if not dmg:IsExplosionDamage() or dmg:GetDamage() < CFG.MIN_DAMAGE then return end
    local ply = ent:IsPlayer() and ent or (IsValid(ent.ply) and ent.ply) or (hg.RagdollOwner and hg.RagdollOwner(ent))
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local org = ply.organism
    if not org or not org.alive then return end

    local n = math.Clamp(math.floor(dmg:GetDamage() / CFG.PER_DAMAGE) + math.random(0, 1), 1, 5)
    for _ = 1, n do AddShard(ply, org, HIT_PARTS[math.random(#HIT_PARTS)]) end
    ply:Notify(n > 1 and "В меня воткнулось что-то острое.." or "Что-то застряло под кожей..", 5, "rem_shards", 0)
    Sync(org)
end)

-- ---------------------------------------------------------------------------
-- стекло
-- ---------------------------------------------------------------------------
local function IsGlass(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    if cls == "func_breakable_surf" then return true end
    if string.find(cls, "glass", 1, true) or string.find(cls, "bottle", 1, true) then return true end
    if (cls == "func_breakable" or cls == "prop_physics" or cls == "prop_physics_multiplayer") then
        if ent.GetMaterialType and ent:GetMaterialType() == MAT_GLASS then return true end
        local mdl = string.lower(ent:GetModel() or "")
        if string.find(mdl, "glass", 1, true) or string.find(mdl, "bottle", 1, true) or string.find(mdl, "window", 1, true) then return true end
    end
    return false
end
hg.organism.IsGlass = IsGlass

local GLASS_HANDS = {"r_hand", "l_hand", "r_hand", "l_hand", "r_forearm", "l_forearm"}
local GLASS_FEET  = {"r_foot", "l_foot", "r_shin", "l_shin"}
local GLASS_BODY  = {"head", "neck", "chest", "abdomen", "r_forearm", "l_forearm", "r_hand", "l_hand", "r_thigh", "l_thigh", "r_upperarm", "l_upperarm"}

local function GlassShards(ply, pool, n)
    local org = ply.organism
    if not org or not org.alive then return end
    if (ply.remGlassT or 0) > CurTime() then return end
    ply.remGlassT = CurTime() + CFG.GLASS_COOLDOWN
    for _ = 1, n do AddShard(ply, org, pool[math.random(#pool)], "glass") end
    ply:Notify(n > 1 and "Ай, в меня воткнулось стекло.." or "Осколок стекла застрял во мне..", 4, "rem_glass", 0)
    Sync(org)
end

local function OwnerOf(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    if IsValid(ent.ply) and ent.ply:IsPlayer() then return ent.ply end
    if hg.RagdollOwner then
        local o = hg.RagdollOwner(ent)
        if IsValid(o) and o:IsPlayer() then return o end
    end
end

hook.Add("EntityTakeDamage", "ZSCAV_GlassShards", function(target, dmg)
    local attacker, inflictor = dmg:GetAttacker(), dmg:GetInflictor()

    -- 1) игрока ранило стекло (бутылка, осколок, окно при пролёте)
    local victim = OwnerOf(target)
    if victim then
        if IsGlass(inflictor) or IsGlass(attacker) then
            if math.random() < 0.7 then GlassShards(victim, GLASS_BODY, math.random(1, 2)) end
        end
        return
    end

    -- 2) игрок сам разбил стекло
    if not IsGlass(target) then return end
    local ply = OwnerOf(attacker)
    if not ply then return end
    local wep = IsValid(inflictor) and inflictor:IsWeapon() and inflictor or nil
    local barehanded = not wep or wep:GetClass() == "weapon_hands_sh" or wep:GetClass() == "weapon_hg_coolhands"
    if not barehanded and inflictor ~= ply and not OwnerOf(inflictor) then return end -- разбил чем-то в руках - руки целы

    if IsValid(ply.FakeRagdoll) or OwnerOf(inflictor) == ply and inflictor ~= ply then
        -- пинок или пролетел телом
        if dmg:IsDamageType(DMG_SLASH) then
            if math.random() < 0.6 then GlassShards(ply, GLASS_FEET, math.random(1, 2)) end
        elseif math.random() < 0.7 then
            GlassShards(ply, GLASS_BODY, math.random(1, 3))
        end
    else
        -- удар кулаком
        if math.random() < 0.6 then GlassShards(ply, GLASS_HANDS, math.random(1, 2)) end
    end
end)

hook.Add("Org Think", "ZSCAV_Shards", function(owner, org, timeValue)
    local shards = org.remShards
    if not shards or #shards == 0 or not org.alive or not IsValid(owner) or not owner:IsPlayer() then return end
    -- болит при беге
    if owner:KeyDown(IN_SPEED) and owner:GetVelocity():Length2DSqr() > 150 * 150 then
        org.painadd = (org.painadd or 0) + timeValue * CFG.MOVE_PAIN * #shards
    end
    -- рана вокруг осколка не заживает
    local now = CurTime()
    for _, s in ipairs(shards) do
        if now >= (s.nextBleed or 0) then
            s.nextBleed = now + CFG.REBLEED_TIME
            if hg.organism.AddWoundManual then
                hg.organism.AddWoundManual(owner, CFG.REBLEED, vector_origin, angle_zero, hg.RemParts[s.part].bones[1], now)
            end
        end
    end
end)

hook.Add("Org Clear", "ZSCAV_Shards", function(org)
    org.remShards = {}
    Sync(org)
end)

-- старт мини-игры извлечения (из меню здоровья)
function hg.organism.StartShardExtract(ply, partId)
    local org = ply.organism
    if not org or not org.alive or not org.remShards then return end
    for _, s in ipairs(org.remShards) do
        if s.part == partId then
            ply.remShardMG = {id = s.id, start = CurTime()}
            local diff = math.Clamp((org.pain or 0) / 100 * 0.6 + math.max(0, 4000 - (org.blood or 5000)) / 1500 * 0.4, 0, 1)
            net.Start("rem_shard_mg")
                net.WriteUInt(s.id, 16)
                net.WriteString((s.kind == "glass" and "СТЕКЛО - " or "") .. hg.RemParts[partId].name)
                net.WriteFloat(s.depth)
                net.WriteFloat(diff)
            net.Send(ply)
            return true
        end
    end
    ply:Notify("Здесь нет осколков.", 3, "rem_shards_none", 0)
end

net.Receive("rem_shard_mg_done", function(_, ply)
    local id = net.ReadUInt(16)
    local result = net.ReadUInt(2) -- 0 отмена, 1 чисто, 2 разорвал
    local st = ply.remShardMG
    ply.remShardMG = nil
    if not st or st.id ~= id or result == 0 then return end
    if result == 1 and CurTime() - st.start < 1.5 then result = 2 end -- "мгновенно" = рывком

    local org = ply.organism
    if not org or not org.alive or not org.remShards then return end
    for i, s in ipairs(org.remShards) do
        if s.id == id then
            table.remove(org.remShards, i)
            local bone = hg.RemParts[s.part].bones[1]
            local blood = result == 1 and CFG.CLEAN_BLOOD or CFG.TORN_BLOOD
            org.painadd = (org.painadd or 0) + (result == 1 and CFG.CLEAN_PAIN or CFG.TORN_PAIN)
            if hg.organism.AddWoundManual then
                hg.organism.AddWoundManual(ply, blood, vector_origin, angle_zero, bone, CurTime())
            end
            ply:EmitSound(result == 1 and "physics/flesh/flesh_squishy_impact_hard1.wav" or "physics/flesh/flesh_bloody_break.wav", 55, math.random(95, 110))
            Sync(org)
            return
        end
    end
end)

hook.Add("PlayerDeath", "ZSCAV_Shards", function(ply) ply.remShardMG = nil end)
