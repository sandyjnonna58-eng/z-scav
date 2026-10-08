--[[
    Z-SCAV: глухота (оглушение) от взрывов.
    Взрыв рядом -> org.remDeaf 0..1 (чем ближе и сильнее, тем больше).
    На клиенте: звук глохнет (DSP), звенит в ушах; со временем проходит.
    Выключить: zscav_deaf 0
]]

local cv = CreateConVar("zscav_deaf", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: глухота от взрывов", 0, 1)

hg.organism.deafCfg = hg.organism.deafCfg or {}
local CFG = hg.organism.deafCfg
CFG.PER_DAMAGE = 1 / 45   -- оглушение за единицу урона взрывом
CFG.MIN        = 0.25     -- любой взрыв, задевший игрока
CFG.RECOVER    = 1 / 50   -- в секунду (полная глухота проходит ~50 с)

hook.Add("EntityTakeDamage", "ZSCAV_Deaf", function(ent, dmg)
    if not cv:GetBool() or not dmg:IsExplosionDamage() then return end
    local ply = ent:IsPlayer() and ent or (IsValid(ent.ply) and ent.ply) or nil
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local org = ply.organism
    if not org or not org.alive then return end
    local add = math.max(CFG.MIN, dmg:GetDamage() * CFG.PER_DAMAGE)
    local before = org.remDeaf or 0
    org.remDeaf = math.min(1, before + add)
    if before < 0.2 and org.remDeaf >= 0.2 then
        ply:Notify("I can't hear anything.. just ringing.", 4, "zscav_deaf", 0)
    end
    ply.fullsend = true
end)

hook.Add("Org Think", "ZSCAV_Deaf", function(owner, org, timeValue)
    if (org.remDeaf or 0) > 0 then
        org.remDeaf = math.max(0, org.remDeaf - timeValue * CFG.RECOVER)
    end
end)

hook.Add("Org Clear", "ZSCAV_Deaf", function(org) org.remDeaf = 0 end)
