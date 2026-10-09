--[[
    Z-SCAV: переедание.
    Сытость может уйти выше 100. Чем больше перебор, тем хуже:
      100+  "объелся" - тяжесть, немного боли в животе
      120+  тошнит - с каждой секундой растёт шанс, что вырвет
      140+  рвота почти сразу
    Рвота: часть съеденного уходит (сытость -45), хочется пить, настроение падает.
    Лёжа на спине - можно захлебнуться (как у обычной рвоты гейммода).
    Выключить: zscav_overeat 0
]]

local cv = CreateConVar("zscav_overeat", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: рвота от переедания", 0, 1)

hg.organism.overeatCfg = hg.organism.overeatCfg or {}
local CFG = hg.organism.overeatCfg
CFG.FULL       = 100
CFG.NAUSEA     = 120
CFG.SURE       = 140
CFG.RATE       = 0.03   -- шанс рвоты в секунду на каждую единицу сытости выше NAUSEA (в %)
CFG.LOSE       = 45     -- сколько сытости уходит при рвоте
CFG.THIRST     = 12
CFG.COOLDOWN   = 8

local function FoodVomit(owner, org, msg)
    org.satiety = math.max(0, (org.satiety or 0) - CFG.LOSE)
    org.hungry = math.max(0, 100 - org.satiety)
    if org.thirst then org.thirst = math.min(100, org.thirst + CFG.THIRST) end
    org.painadd = (org.painadd or 0) + 6
    if org.happiness then org.happiness = math.max(0, org.happiness - 0.08) end

    local ent = hg.GetCurrentCharacter and hg.GetCurrentCharacter(owner) or owner
    if not IsValid(ent) then ent = owner end
    local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
    local mat = bone and ent:GetBoneMatrix(bone)
    local onSpine = mat and mat:GetAngles():Right()[3] > 0.25
    if onSpine then org.vomitInThroat = true end -- лёжа на спине - в горло
    owner:SetNetVar("vomiting", CurTime() + 1.5)
    ent:EmitSound("vomit/vomit5.mp3", 70, math.random(95, 105))
    owner:Notify(msg or "Ух.. я слишком много съел..", 4, "zscav_overeat_vomit", 0)
end
hg.organism.FoodVomit = FoodVomit

hook.Add("Org Think", "ZSCAV_Overeat", function(owner, org, timeValue)
    if not cv:GetBool() or not org.alive or not IsValid(owner) or not owner:IsPlayer() then return end
    local sat = org.satiety or 0
    if sat <= CFG.FULL then org.remOverfullSaid = nil return end
    local now = CurTime()

    -- тяжесть в животе
    org.painadd = (org.painadd or 0) + timeValue * (sat - CFG.FULL) * 0.02
    if not org.remOverfullSaid then
        org.remOverfullSaid = true
        owner:Notify("Я наелся.. больше нельзя.", 4, "zscav_overeat", 0)
    end

    if sat < CFG.NAUSEA or now < (org.remOvereatCd or 0) then return end
    local chance = sat >= CFG.SURE and 0.5 or (sat - CFG.NAUSEA) * CFG.RATE / 100 * 10
    if math.Rand(0, 1) < chance * timeValue then
        org.remOvereatCd = now + CFG.COOLDOWN
        FoodVomit(owner, org)
    end
end)
