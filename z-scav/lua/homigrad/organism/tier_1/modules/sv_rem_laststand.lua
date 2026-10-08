--[[
    Z-SCAV: последний рубеж (по правилам Casualties: Unknown, Last stand).

    Срабатывает ТОЛЬКО во время процесса умирания (таймер "You will die in..."):
    в начале умирания один раз бросается шанс, зависящий от настроения (счастья):

        настроение | шанс
        -100..-30  |   0%
        -30..-10.02|  0 -> 10%
        -10..0     |  20%
          0..10    |  20 -> 50%
         10..70    |  50 -> 100%
         70..100   | 100%

    Сработал - персонаж приходит в себя, таймер умирания снимается, и сразу:
      мозг 75-90% здоровья, сытость и вода на полпути к полным, кровь не меньше 3.75 л,
      пульс 120, фибрилляция/аритмия/остановка сердца убраны, давление ~135,
      кислород 100% и удерживается 6.7 с, инсульт (кровоизлияние) убран, яд/угарный газ убраны,
      выносливость полная (и не падает ниже половины 200 с), пневмоторакс вдвое меньше,
      температура 37, внутреннее кровотечение -95%, кровотечение из ран -95%,
      опиаты отменены, привыкание к ним снижено.
    Потом 5 минут адреналин держится высоким и не спадает.
    Выключить: zscav_laststand 0
]]

local cv = CreateConVar("zscav_laststand", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Z-SCAV: последний рубеж", 0, 1)

hg.organism.lastStandCfg = hg.organism.lastStandCfg or {}
local CFG = hg.organism.lastStandCfg
CFG.SHOW_TIME      = 20     -- сек: надпись/красные края на экране
CFG.SPO2_HOLD      = 6.7
CFG.ENERGY_TIME    = 200
CFG.ADRENALINE_TIME = 300
CFG.ADRENALINE_MIN = 1.5    -- уровень адреналина гейммода, ниже которого не опускается 5 минут
CFG.ONCE_PER_LIFE  = true

-- таблица шанса из вики (настроение -100..100 -> 0..1)
function hg.organism.LastStandChance(mood100)
    local m = mood100
    if m <= -30 then return 0 end
    if m < -10.01 then return math.Remap(m, -30, -10.02, 0, 0.10) end
    if m < 0 then return 0.20 end
    if m < 10 then return math.Remap(m, 0, 10, 0.20, 0.50) end
    if m < 70 then return math.Remap(m, 10, 70, 0.50, 1.00) end
    return 1
end

local PHRASES = {"Not like this.. NOT LIKE THIS!", "Get up. GET UP!", "I'm not dying here!", "Not yet.. not yet!"}

local function Activate(owner, org)
    local now = CurTime()
    org.remLastStandUntil = now + CFG.ADRENALINE_TIME
    org.remLastStandUsed = true
    org.remLastStand = now + CFG.SHOW_TIME
    org.remLastStandSpO2 = now + CFG.SPO2_HOLD
    org.remLastStandEnergy = now + CFG.ENERGY_TIME
    org.remLastStandAdren = now + CFG.ADRENALINE_TIME

    -- в себя
    org.needotrub = false
    org.otrub = false
    org.incapacitated = false
    org.deathStateEnd = nil
    org.deathStateKilled = nil
    org.consciousness = 1
    org.shock = 0

    -- мозг 75-90%
    org.brain = math.min(org.brain or 0, 1 - math.Rand(0.75, 0.90))
    org.brainHemorrhage = 0                         -- инсульт
    -- еда / вода на полпути к полным
    org.satiety = (org.satiety or 0) + (100 - (org.satiety or 0)) * 0.5
    org.hungry = 100 - org.satiety
    if org.thirst then org.thirst = org.thirst * 0.5 end
    -- кровь и сердце
    org.blood = math.max(org.blood or 0, 3750)
    org.heartstop = false
    org.fibrillation = false
    org.arrhythmia = 0
    org.heartbeat = 120
    org.pulse = math.max(org.pulse or 0, 75)
    org.bloodPressure = math.max(org.bloodPressure or 0, 98)  -- систолическое ~135
    org.systolic, org.diastolic = 135, 85
    -- дыхание
    if istable(org.o2) then org.o2[1] = org.o2.range or 30 end
    org.lungsfunction = true
    if org.pneumothorax then org.pneumothorax = org.pneumothorax * 0.5 end   -- "гемоторакс вдвое"
    -- яды
    org.CO, org.COregen = 0, 0
    org.poison4 = nil
    if IsValid(owner) then owner.ConsumePoisoned_KCN = nil end
    -- температура
    org.temperature = 37
    -- кровотечения
    if org.internalBleed then org.internalBleed = org.internalBleed * 0.05 end
    org.bleed = (org.bleed or 0) * 0.05
    for _, w in ipairs(org.wounds or {}) do w[1] = (w[1] or 0) * 0.05 end
    for _, w in ipairs(org.arterialwounds or {}) do if isnumber(w[1]) then w[1] = w[1] * 0.05 end end
    -- опиаты отменены, привыкание снижено
    org.analgesia, org.analgesiaAdd = 0, 0
    org.remOpioidTol = (org.remOpioidTol or 0) * 0.5
    org.remHigh, org.remComedown = 0, 0
    -- Z-SCAV: снимаются почти все негативные эффекты
    -- боль, шок, страх, паника, дезориентация
    org.pain, org.painadd, org.avgpain = 0, 0, 0
    org.shock = 0
    org.fear = 0
    org.panicattack, org.panicattackadd, org.panicattackActive = 0, 0, nil
    org.disorientation, org.immobilization = 0, 0
    org.hypotension, org.hypertension = 0, 0
    org.vomitInThroat = nil
    -- вывихи вправляются (переломы, ампутации и осколки остаются - это механика тела)
    org.larmdislocation, org.rarmdislocation, org.llegdislocation, org.rlegdislocation = false, false, false, false
    org.jawdislocation = false
    -- психика: депрессия, отходняк, плохое настроение
    org.depression, org.depressionadd, org.depressionStage = 0, 0, 0
    org.remComedown = 0
    org.happiness = math.max(org.happiness or 0.5, 0.65)
    org.remJoy = math.max(org.remJoy or 0, 0.3)
    -- кожа: инфекции и сепсис уходят, кожа подживает
    org.remSepsis = 0
    if org.remInfect then for k in pairs(org.remInfect) do org.remInfect[k] = 0 end end
    if org.remSkin then for k, v in pairs(org.remSkin) do org.remSkin[k] = math.min(100, v + 50) end end
    -- оглушение
    org.remDeaf = 0
    -- срывы, апатия, "уходы в себя", тяга ствола - не будет ещё 5 минут
    org.remPsychosisNext = now + CFG.ADRENALINE_TIME
    org.remAimPullNext = now + CFG.ADRENALINE_TIME
    org.remWanderNext = now + CFG.ADRENALINE_TIME
    if IsValid(owner) then owner.zscavApathy = nil end
    org.moodLockUntil = now + 30
    org.moodLockHappiness = 0.7

    -- эпилепсия (судороги) снимается
    if hg.organism.StopSeizure then hg.organism.StopSeizure(owner, org) else
        org.seizure, org.seizureActive, org.seizureStart, org.seizureEnd, org.nextSeizureSpasm = 0, false, 0, 0, 0
    end
    -- силы
    if istable(org.stamina) then org.stamina[1] = org.stamina.max or org.stamina.range or org.stamina[1] end
    org.adrenalineAdd = math.max(org.adrenalineAdd or 0, 2)

    if IsValid(owner) then
        owner:Notify(PHRASES[math.random(#PHRASES)], 5, "zscav_laststand", 0)
        owner.fullsend = true
        if owner.SetNetVar then owner:SetNetVar("wounds", org.wounds) end
    end
end

-- вызывается из основного цикла организма до решения "без сознания"
function hg.organism.LastStandThink(owner, org, timeValue, isPly)
    if not isPly or not cv:GetBool() or not org.alive then return end
    local now = CurTime()

    -- длительные эффекты после срабатывания
    if (org.remLastStandSpO2 or 0) > now and istable(org.o2) then org.o2[1] = org.o2.range or 30 end
    if (org.remLastStandEnergy or 0) > now and istable(org.stamina) then
        local mx = org.stamina.max or org.stamina.range or 180
        org.stamina[1] = math.max(org.stamina[1] or 0, mx * 0.5)
    end
    if (org.remLastStandAdren or 0) > now then
        org.adrenaline = math.max(org.adrenaline or 0, CFG.ADRENALINE_MIN)
        -- пока действует рубеж (5 мин) - новых судорог нет, психика не проваливается
        if org.seizureActive or (org.seizure or 0) > 0 then
            org.seizure, org.seizureActive, org.seizureStart, org.seizureEnd = 0, false, 0, 0
        end
        org.depression = math.min(org.depression or 0, 0.1)
        org.panicattack, org.panicattackadd = 0, 0
        org.remSepsis = 0
    end
    if (org.remLastStand or 0) > now then
        org.needotrub = false   -- первые секунды держим в сознании
        return
    end

    -- процесс умирания идёт: один бросок на эпизод
    if org.deathStateEnd and org.deathStateEnd > 0 then
        if org.remLastStandRolled then return end
        org.remLastStandRolled = true
        if CFG.ONCE_PER_LIFE and org.remLastStandUsed then return end
        local chance = hg.organism.LastStandChance((org.mood or 0) * 100)
        if math.Rand(0, 1) < chance then Activate(owner, org) end
    else
        org.remLastStandRolled = false
    end
end

hook.Add("Org Clear", "ZSCAV_LastStand", function(org)
    org.remLastStand, org.remLastStandSpO2, org.remLastStandEnergy, org.remLastStandAdren = 0, 0, 0, 0
    org.remLastStandUsed = false
    org.remLastStandRolled = false
end)
