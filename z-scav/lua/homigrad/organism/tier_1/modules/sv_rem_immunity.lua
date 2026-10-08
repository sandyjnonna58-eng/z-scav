--[[
    Z-SCAV: иммунитет (по Casualties: Unknown).

    org.remImmunity 40..200 %, база 100. Цель считается из состояния тела,
    иммунитет плавно к ней тянется:
        стат            база     влияние
        сытость         70       +0.75% за единицу
        вода (100-жажда)60       +0.3%  за единицу
        энергия         60%      +0.2%  за 1% энергии
        температура     37 °C    +8%    за 1 °C
        кровь           5 л      +0.2%  за 0.025 л
        грязь           <50%     -1%    за каждый 1% выше 50
        болезни         -        -0.8%  за каждую (инфекция на части, сепсис, отравление)
        антибиотики     -        +70%   пока действуют
    Скорость инфекции (используется в sv_rem_skin.lua): 7.2%/мин при 100%,
    быстрее при низком иммунитете (x2.5 при 0), медленнее при высоком, ~195.8% - стоит,
    200% - регрессирует. Дезинфекция части (перевязка) вычитает 2.16%/мин.
    Выключить: zscav_immunity 0 (тогда иммунитет всегда 100%)
]]

local cv = CreateConVar("zscav_immunity", 1, FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: иммунитет", 0, 1)

hg.organism.immunityCfg = hg.organism.immunityCfg or {}
local CFG = hg.organism.immunityCfg
CFG.MIN, CFG.MAX = 40, 200
CFG.FOLLOW       = 1.0      -- %/с, как быстро иммунитет идёт к цели
CFG.BASE_RATE    = 7.2      -- %/мин рост инфекции при 100%
CFG.DISINFECT    = 2.16     -- %/мин, которые снимает дезинфекция
CFG.ANTIBIOTICS  = 70
CFG.DISINFECT_TIME = 600    -- сек: столько часть считается продезинфицированной после перевязки

-- множитель скорости инфекции от иммунитета (точки по вики CU, между ними - линейно)
local CURVE = {
    {0, 2.5}, {40, 1.9}, {50, 1.6}, {80, 1.1}, {100, 1.0}, {120, 0.9},
    {150, 0.6}, {180, 0.3}, {195, 0.12}, {195.8, 0}, {200, -0.117},
}
function hg.organism.InfectionMul(imm)
    if imm <= CURVE[1][1] then return CURVE[1][2] end
    for i = 2, #CURVE do
        local a, b = CURVE[i - 1], CURVE[i]
        if imm <= b[1] then
            return Lerp((imm - a[1]) / (b[1] - a[1]), a[2], b[2])
        end
    end
    return CURVE[#CURVE][2]
end

-- скорость инфекции части в %/сек (может быть отрицательной - регрессия)
function hg.organism.InfectionRate(org, disinfected)
    local imm = cv:GetBool() and (org.remImmunity or 100) or 100
    local perMin = CFG.BASE_RATE * hg.organism.InfectionMul(imm)
    if disinfected then
        perMin = perMin - CFG.DISINFECT
        -- при 40% и ниже дезинфекция не даёт инфекции отступить
        if imm <= 40 then perMin = math.max(perMin, 0) end
    end
    return perMin / 60
end

function hg.organism.Disinfect(org, part)
    if not org then return end
    org.remDisinfect = org.remDisinfect or {}
    org.remDisinfect[part] = CurTime() + CFG.DISINFECT_TIME
end

local function Target(org)
    local t = 100
    t = t + ((org.satiety or 70) - 70) * 0.75
    t = t + ((100 - (org.thirst or 0)) - 60) * 0.3
    t = t + ((org.remEnergy or 100) - 60) * 0.2 -- настоящая энергия (sv_rem_energy.lua)
    t = t + ((org.temperature or 37) - 37) * 8
    t = t + ((org.blood or 5000) - 5000) / 25 * 0.2
    local dirt = org.remDirt or 0
    if dirt > 50 then t = t - (dirt - 50) end
    local ill = 0
    for _, v in pairs(org.remInfect or {}) do if v > 0 then ill = ill + 1 end end
    if (org.remSepsis or 0) > 0 then ill = ill + 1 end
    if org.poison4 then ill = ill + 1 end
    t = t - ill * 0.8
    if (org.remAntibioticsUntil or 0) > CurTime() then t = t + CFG.ANTIBIOTICS end
    return math.Clamp(t, CFG.MIN, CFG.MAX)
end
hg.organism.ImmunityTarget = Target

hook.Add("Org Think", "ZSCAV_Immunity", function(owner, org, timeValue)
    if not org.alive then return end
    if not cv:GetBool() then org.remImmunity = 100 return end
    org.remImmunity = math.Approach(org.remImmunity or 100, Target(org), CFG.FOLLOW * timeValue)
end)

hook.Add("Org Clear", "ZSCAV_Immunity", function(org)
    org.remImmunity = 100
    org.remDisinfect = {}
    org.remAntibioticsUntil = 0
end)
