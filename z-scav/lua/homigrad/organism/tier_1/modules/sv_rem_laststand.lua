--[[
    Z-SCAV: последний рубеж (по правилам Casualties: Unknown, Last stand).

    Срабатывает, когда начинается умирание (таймер "You will die in...") или мозг
    подходит к смерти (повреждение >= 78%, у нас 85% - смерть). Бросок один на эпизод, сам рубеж - один раз за жизнь.
    Шанс берётся по настроению 9-10 минут назад (каждую минуту настроение пишется
    в историю из 10 ячеек, как в CU). Точки кривой из вики, между ними - линейно:

        настроение | -30  -20  -10   0    10   20     40   60     70
        шанс       |  0%   5%  20%  20%  50%  58.3%  75%  91.7%  100%

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

CFG.HEAL_TIME      = 300    -- сек: сколько тело активно заживает после рубежа
CFG.ORGAN_HEAL     = 0.6    -- сразу: повреждение органов -60%
CFG.ORGAN_REGEN    = 1 / 120 -- потом: органы заживают на 1/120 в секунду
CFG.BLOOD_REGEN    = 6      -- мл/с, кровь восстанавливается до BLOOD_TARGET
CFG.BLOOD_TARGET   = 4500
CFG.BRAIN_CAP      = 0.3    -- пока действует рубеж, мозг сам не отмирает (только от новых ран)
CFG.IMMUNITY_TIME  = 240    -- как антибиотики

-- кривая шанса из вики (настроение -100..100 -> 0..1)
local CURVE = {{-30, 0}, {-20, 0.05}, {-10, 0.20}, {0, 0.20}, {10, 0.50}, {20, 0.5833}, {40, 0.75}, {60, 0.9167}, {70, 1}}
function hg.organism.LastStandChance(mood100)
    local m = mood100
    if m <= CURVE[1][1] then return 0 end
    for i = 2, #CURVE do
        local a, b = CURVE[i - 1], CURVE[i]
        if m <= b[1] then return Lerp((m - a[1]) / (b[1] - a[1]), a[2], b[2]) end
    end
    return 1
end

-- настроение 9-10 минут назад (если игрок жив меньше - самое старое, что есть)
local function OldMood(org)
    local h = org.remMoodHist
    if istable(h) and #h > 0 then return h[#h] end
    return (org.mood or 0) * 100
end

local function Heal(v, k) return isnumber(v) and math.max(v * (1 - k), 0) or v end

local PHRASES = {"Только не так.. ТОЛЬКО НЕ ТАК!", "Вставай. ВСТАВАЙ!", "Я здесь не умру!", "Ещё нет.. ещё нет!"}

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
    -- органы: повреждения -60% сразу, дальше заживают (см. LastStandThink)
    for _, k in ipairs({"heart", "liver", "stomach", "intestines", "trachea", "eyeL", "eyeR", "heartStrain"}) do
        org[k] = Heal(org[k], CFG.ORGAN_HEAL)
    end
    for _, k in ipairs({"lungsL", "lungsR"}) do
        if istable(org[k]) then org[k][1] = Heal(org[k][1], CFG.ORGAN_HEAL) org[k][2] = Heal(org[k][2], CFG.ORGAN_HEAL) end
    end
    org.critical = false
    -- мышцы +30% к здоровью (полные переломы - значение 1 - остаются)
    for _, k in ipairs({"lleg", "rleg", "larm", "rarm", "chest", "pelvis", "skull", "jaw"}) do
        if isnumber(org[k]) and org[k] < 1 then org[k] = org[k] * 0.7 end
    end
    -- иммунитет как от антибиотиков на 4 минуты, энергия полная, бодрость 200 с
    org.remAntibioticsUntil = math.max(org.remAntibioticsUntil or 0, now + CFG.IMMUNITY_TIME)
    org.remEnergy = 100
    org.remEnergized = now + CFG.ENERGY_TIME
    org.remLastStandHeal = now + CFG.HEAL_TIME
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
    org.stun = 0
    -- Z-SCAV: сам встаёт с земли
    if IsValid(owner) then
        owner.fakecd = 0
        org.needfake = false
        timer.Simple(0.4, function()
            if not IsValid(owner) or not owner:Alive() or not IsValid(owner.FakeRagdoll) then return end
            local o = owner.organism
            if o and (o.spine2 or 0) >= (hg.organism.fake_spine2 or 1) then return end -- сломан позвоночник - не встать
            owner.fakecd = 0
            if hg.FakeUp then hg.FakeUp(owner, true) end
        end)
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
            if hg.organism.StopSeizure then hg.organism.StopSeizure(owner, org)
            else org.seizure, org.seizureActive, org.seizureStart, org.seizureEnd = 0, false, 0, 0 end
            if IsValid(owner) then owner.fakecd = 0 end
        end
        org.depression = math.min(org.depression or 0, 0.1)
        org.panicattack, org.panicattackadd = 0, 0
        org.remSepsis = 0
    end
    -- история настроения: раз в минуту, 10 ячеек (последняя = 9-10 минут назад)
    if (org.remMoodHistNext or 0) <= now then
        org.remMoodHistNext = now + 60
        org.remMoodHist = org.remMoodHist or {}
        table.insert(org.remMoodHist, 1, (org.mood or 0) * 100)
        if #org.remMoodHist > 10 then org.remMoodHist[11] = nil end
    end

    -- Z-SCAV: 5 минут тело реально заживает, а не просто "просыпается"
    if (org.remLastStandHeal or 0) > now then
        local dt = timeValue or 0
        local r = CFG.ORGAN_REGEN * dt
        for _, k in ipairs({"heart", "liver", "stomach", "intestines", "trachea", "eyeL", "eyeR"}) do
            if isnumber(org[k]) and org[k] < 1 then org[k] = math.max(org[k] - r, 0) end
        end
        for _, k in ipairs({"lungsL", "lungsR"}) do
            if istable(org[k]) then
                if isnumber(org[k][1]) and org[k][1] < 1 then org[k][1] = math.max(org[k][1] - r, 0) end
                if isnumber(org[k][2]) then org[k][2] = math.max(org[k][2] - r, 0) end
            end
        end
        org.heartStrain = math.max((org.heartStrain or 0) - r, 0)
        -- мозг сам не отмирает и понемногу заживает
        org.brain = math.max(math.min(org.brain or 0, CFG.BRAIN_CAP) - r * 0.5, 0)
        org.lastSeizureBrain = org.brain
        -- кровь восстанавливается, раны подсыхают
        if (org.blood or 0) < CFG.BLOOD_TARGET then org.blood = math.min((org.blood or 0) + CFG.BLOOD_REGEN * dt, CFG.BLOOD_TARGET) end
        for _, w in ipairs(org.wounds or {}) do if isnumber(w[1]) then w[1] = math.max(w[1] - dt * 0.05, 0) end end
        for _, w in ipairs(org.arterialwounds or {}) do if isnumber(w[1]) then w[1] = math.max(w[1] - dt * 0.05, 0) end end
        if org.internalBleed then org.internalBleed = math.max(org.internalBleed - dt * 0.2, 0) end
        -- кислород не проваливается, сердце не встаёт (если оно не разрушено)
        if istable(org.o2) then org.o2[1] = math.max(org.o2[1] or 0, (org.o2.range or 30) * 0.5) end
        if org.heartstop and (org.heart or 0) < 1 then org.heartstop = false end
        org.arrhythmia = math.min(org.arrhythmia or 0, 0.4)
        -- боль глушится адреналином
        org.pain = math.min(org.pain or 0, 30)
        org.shock = math.min(org.shock or 0, 10)
        org.consciousness = math.max(org.consciousness or 1, 0.75)
    end

    if (org.remLastStand or 0) > now then
        org.needotrub = false   -- первые секунды держим в сознании
        return
    end

    -- процесс умирания идёт или мозг ниже 15%: один бросок на эпизод
    if (org.deathStateEnd and org.deathStateEnd > 0) or (org.brain or 0) >= 0.78 then -- 0.85 у нас уже смерть мозга, ловим чуть раньше
        if org.remLastStandRolled then return end
        org.remLastStandRolled = true
        if CFG.ONCE_PER_LIFE and org.remLastStandUsed then return end
        local chance = hg.organism.LastStandChance(OldMood(org))
        if math.Rand(0, 1) < chance then Activate(owner, org) end
    else
        org.remLastStandRolled = false
    end
end

hook.Add("Org Clear", "ZSCAV_LastStand", function(org)
    org.remLastStand, org.remLastStandSpO2, org.remLastStandEnergy, org.remLastStandAdren = 0, 0, 0, 0
    org.remLastStandUsed = false
    org.remLastStandRolled = false
    org.remLastStandHeal = 0
    org.remMoodHist, org.remMoodHistNext = {}, 0
end)
