--[[
    Z-SCAV: в депрессии персонаж иногда "уходит в себя" и сам бредёт куда-то.
    Несколько секунд ноги идут сами, взгляд уплывает в сторону. Можно сопротивляться
    (жать назад/в стороны), но полностью остановиться трудно.
    Когда: депрессия от 40% или настроение -50 и ниже.
    Выключить: zscav_wander 0
]]

local cv = CreateConVar("zscav_wander", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: в депрессии персонаж сам бредёт", 0, 1)

hg.organism.wanderCfg = hg.organism.wanderCfg or {}
local CFG = hg.organism.wanderCfg
CFG.DEP_FROM  = 0.4
CFG.MOOD_FROM = -0.5
CFG.RATE      = 1 / 75    -- шанс в секунду при максимальной силе (~раз в 75 с)
CFG.COOLDOWN  = 40
CFG.TIME      = {4, 9}    -- сек

util.AddNetworkString("zscav_wander")

local PHRASES = {"Where am I even going..", "My legs just.. keep moving.", "I'm not here. I'm somewhere else.", "Just walk. Don't think."}

function hg.organism.StartWander(ply, dur)
    if not IsValid(ply) or not ply:Alive() then return end
    dur = dur or math.Rand(CFG.TIME[1], CFG.TIME[2])
    net.Start("zscav_wander")
        net.WriteFloat(dur)
        net.WriteFloat(math.Rand(-1, 1)) -- куда уплывает взгляд
    net.Send(ply)
    ply:Notify(PHRASES[math.random(#PHRASES)], 4, "zscav_wander", 0)
end

hook.Add("Org Think", "ZSCAV_Wander", function(owner, org, timeValue)
    if not cv:GetBool() or not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return end
    if not org.alive or org.otrub or owner:InVehicle() or IsValid(owner.FakeRagdoll) then return end
    if owner.GlideGetVehicle and IsValid(owner:GlideGetVehicle()) then return end
    local dep, mood = org.depression or 0, org.mood or 0
    local k = math.max(
        dep >= CFG.DEP_FROM and (dep - CFG.DEP_FROM) / (1 - CFG.DEP_FROM) * 0.7 + 0.3 or 0,
        mood <= CFG.MOOD_FROM and (CFG.MOOD_FROM - mood) / (1 + CFG.MOOD_FROM) * 0.7 + 0.3 or 0)
    if k <= 0 then return end
    local now = CurTime()
    if now < (org.remWanderNext or 0) then return end
    if math.Rand(0, 1) < CFG.RATE * k * timeValue then
        org.remWanderNext = now + CFG.COOLDOWN
        hg.organism.StartWander(owner)
    end
end)

hook.Add("Org Clear", "ZSCAV_Wander", function(org) org.remWanderNext = CurTime() + 60 end)

concommand.Add("rem_wander", function(caller, _, args)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local who = args[1] or "^"
    for _, p in ipairs(player.GetAll()) do
        if (who == "^" and p == caller) or who == "*" or (who ~= "^" and string.find(string.lower(p:Nick()), string.lower(who), 1, true)) then
            hg.organism.StartWander(p)
        end
    end
end)
