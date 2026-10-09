--[[
    Z-SCAV: раны L4D2 Wounds Shader (Simple Wound v2) на игроках Homigrad.

    Сервер: попадания по игроку (и по его рэгдоллу) приходят через хук HomigradDamage -
            рана считается по костям того, во что попали, а рисуется на самом игроке.
            При возрождении раны с игрока снимаются (труп свои оставляет).
    Клиент: hg.renderOverride рисует тело через SimpleWound.DrawWithParams, поэтому
            одежда, аксессуары и броня Homigrad не пропадают. Рэгдолл игрока берёт раны игрока.

    Для отображения у КАЖДОГО игрока должен стоять бинарный модуль Simple Wound
    (gmcl_simple_wound_*.dll в garrysmod/lua/bin), см. https://github.com/2016killer/gmod-simple-wound-v2/releases
    Без него игра работает как раньше, просто без ран.
    zscav_sw2 0 - выключить раны на игроках.
]]
AddCSLuaFile()

local cv = CreateConVar("zscav_sw2", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Z-SCAV: раны Simple Wound на игроках", 0, 1)

if SERVER then
    util.AddNetworkString("zscav_sw2_reset")

    local WOUND_TYPES = bit.bor(DMG_BULLET, DMG_SLASH, DMG_BLAST, DMG_CLUB, DMG_BUCKSHOT, DMG_SNIPER, DMG_AIRBOAT, DMG_PLASMA, DMG_BLAST_SURFACE)

    -- тип урона приводим к ключу таблицы размеров ран аддона
    local function WoundType(t)
        if bit.band(t, DMG_BUCKSHOT) ~= 0 then return DMG_BUCKSHOT end
        if bit.band(t, DMG_SNIPER) ~= 0 then return DMG_SNIPER end
        if bit.band(t, DMG_BULLET) ~= 0 or bit.band(t, DMG_AIRBOAT) ~= 0 then return DMG_BULLET end
        if bit.band(t, DMG_SLASH) ~= 0 then return DMG_SLASH end
        if bit.band(t, DMG_BLAST) ~= 0 or bit.band(t, DMG_BLAST_SURFACE) ~= 0 then return DMG_BLAST end
        if bit.band(t, DMG_CLUB) ~= 0 then return DMG_CLUB end
        if bit.band(t, DMG_PLASMA) ~= 0 then return DMG_PLASMA end
    end

    hook.Add("HomigradDamage", "ZSCAV_SW2", function(ply, dmgInfo, hitgroup, ent)
        if not cv:GetBool() or not SimpleWoundTrigger or not SimpleWoundTrigger.Apply then return end
        if not IsValid(ply) or not ply:IsPlayer() or not dmgInfo then return end
        local dtype = dmgInfo:GetDamageType()
        if bit.band(dtype, WOUND_TYPES) == 0 or dmgInfo:GetDamage() < 1 then return end -- уколы, яд, голод - не раны
        local wtype = WoundType(dtype)
        if not wtype then return end

        local pos = dmgInfo:GetDamagePosition()
        if not pos or pos:IsZero() then return end
        local hitEnt = IsValid(ent) and ent or ply
        if hitEnt:GetPos():DistToSqr(pos) > 200 * 200 then return end

        -- не чаще 10 ран в секунду на игрока (дробь)
        local now = CurTime()
        if (ply.zscavSW2Next or 0) > now then return end
        ply.zscavSW2Next = now + 0.1

        local dir = -dmgInfo:GetDamageForce()
        if dir:IsZero() then
            local att = dmgInfo:GetAttacker()
            dir = IsValid(att) and (att:WorldSpaceCenter() - pos) or Vector(0, 0, 1)
        end
        if hitEnt:IsRagdoll() or not hitgroup or hitgroup == HITGROUP_GENERIC then
            hitgroup = SimpleWoundTrigger.GetHitGroupByPosition(hitEnt, pos)
        end

        local ok, err = pcall(SimpleWoundTrigger.Apply, hitEnt, pos, dir, hitgroup, wtype, ply)
        if not ok then ErrorNoHalt("[Z-SCAV SW2] " .. tostring(err) .. "\n") end
    end)

    hook.Add("PlayerSpawn", "ZSCAV_SW2", function(ply)
        net.Start("zscav_sw2_reset")
        net.WriteEntity(ply)
        net.Broadcast()
    end)
else
    net.Receive("zscav_sw2_reset", function()
        local ply = net.ReadEntity()
        if not IsValid(ply) then return end
        -- труп оставляет себе копию ран, у живого игрока они снимаются
        local rag = ply.FakeRagdoll
        if IsValid(rag) and rag.sw_params == ply.sw_params and ply.sw_params then
            rag.sw_params = table.Copy(ply.sw_params)
            rag.sw_materials = nil
        end
        ply.sw_params, ply.sw_materials, ply.sw_matlist, ply.sw_submat_cache = nil, nil, nil, nil
        ply.sw_alloc_n, ply.sw_runtime, ply.sw_fleshbones = nil, nil, nil
    end)

    -- какие раны рисовать на теле ent (self - игрок или сам рэгдолл, как в hg.renderOverride)
    function hg_ZSCAVWoundParams(ent, self)
        if not cv:GetBool() or not SimpleWound or not SimpleWound.DrawWithParams then return end
        if ent.sw_params and ent ~= self and IsValid(self) and self:IsPlayer() and self.sw_params and ent.sw_params ~= self.sw_params then
            -- рэгдолл уже со своими ранами (старый труп), но игрок жив и снова в нём - берём ранения игрока
            return self.sw_params
        end
        if ent.sw_params then return ent.sw_params end
        if IsValid(self) and self ~= ent and self.sw_params then return self.sw_params end
        if ent:IsRagdoll() then
            local p = ent:GetNWEntity("ply")
            if IsValid(p) and p.sw_params then return p.sw_params end
        end
    end
end
