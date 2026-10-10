--[[
    Z-SCAV: совместимость с аддоном Project Hemogen (модуль NeuroTrauma - травмы мозга).

    NeuroTrauma рассчитан на пороги чистого Z-City (мозг >= 0.6 - остановка сердца, >= 0.7 - смерть).
    В Z-SCAV они другие: сердце останавливается с 0.75, смерть мозга - 0.85, есть последний бой,
    таймер умирания и своя эпилепсия. Из-за этого были проблемы с повреждением мозга:
      * отказ ствола мозга ставил 0.60 - у нас этого мало, человек застревал в бесконечной коме;
      * последний бой лечил мозг, а NeuroTrauma сразу возвращал повреждение обратно;
      * каждое "поднятие пола" мозга от NeuroTrauma запускало ещё и нашу эпилепсию -
        приступы шли двойные и почти без перерыва.
    Здесь это исправлено. Если аддона нет - файл ничего не делает.
]]
if not SERVER then return end

local function Patch()
    local NT = NeuroTrauma
    if not istable(NT) or not istable(NT.ZC) or not istable(NT.Config) then return false end
    if NT.ZSCAVPatched then return true end
    NT.ZSCAVPatched = true
    local Z, C = NT.ZC, NT.Config

    -- 1) пороги мозга под Z-SCAV (sv_pulse.lua: сердце с 0.75; sv_lungs/sv_blood: смерть мозга 0.85)
    if istable(C.Out) then
        C.Out.brainFailure = 0.78 -- отказ ствола: сердце и дыхание останавливаются (раньше 0.60)
    end

    -- 2) последний бой: пока он действует, NeuroTrauma не поднимает повреждение мозга
    --    и не гасит сознание (иначе лечение последнего боя сразу отменялось)
    local origFloor, origCap = Z.FloorBrain, Z.CapConsciousness
    Z.FloorBrain = function(org, floor)
        if istable(org) and (org.remLastStandUntil or 0) > CurTime() then return end
        return origFloor(org, floor)
    end
    Z.CapConsciousness = function(org, cap)
        if istable(org) and (org.remLastStand or 0) > CurTime() then return end -- первые секунды рубежа - в сознании
        return origCap(org, cap)
    end

    -- 3) удар по голове (бита, кулак): остановка дыхания после удара короче (было до 40 с)
    if istable(C.Load) then C.Load.apnoeaMax = math.min(C.Load.apnoeaMax or 40, 12) end

    print("[Z-SCAV] NeuroTrauma: совместимость включена (пороги мозга, последний бой, эпилепсия)")
    return true
end

hook.Add("InitPostEntity", "ZSCAV_NeuroTraumaCompat", function()
    if Patch() then return end
    timer.Create("ZSCAV_NeuroTraumaCompat", 1, 30, function()
        if Patch() then timer.Remove("ZSCAV_NeuroTraumaCompat") end
    end)
end)

-- последний бой сбрасывает модель травмы мозга NeuroTrauma (наш рубеж лечит почти всё)
hook.Add("Org Think", "ZSCAV_NeuroTraumaLastStand", function(owner, org)
    if not NeuroTrauma or not NeuroTrauma.Reset then return end
    local until_ = org.remLastStandUntil or 0
    if until_ > CurTime() and org.zscavNTResetFor ~= until_ then
        org.zscavNTResetFor = until_
        pcall(NeuroTrauma.Reset, owner)
    end
end)

-- NeuroTrauma ведёт свои судороги: наша эпилепсия от изменений мозга при нём не нужна
function ZSCAV_NeuroTraumaActive()
    local NT = NeuroTrauma
    return istable(NT) and isfunction(NT.Enabled) and NT.Enabled() == true
end

-- 4) Нокаут от удара по голове - не смерть. Раньше: NeuroTrauma вырубал и останавливал дыхание,
--    кислород падал ниже 5 -> наш организм считал это "умиранием" -> таймер смерти 60 с ->
--    мозг "умирал" от одного удара битой. Теперь пока NeuroTrauma держит нокаут/апноэ, а
--    настоящих смертельных причин нет (кровь, сердце, позвоночник, трахея, мозг < 0.6),
--    кислород не падает ниже безопасного и таймер умирания не запускается.
--    Вызывается из основного цикла организма (sv_organism.lua) перед решением об умирании.
local function TransientOnly(org)
    if org.heartstop or (org.brain or 0) >= 0.6 then return false end
    if (org.blood or 5000) <= 3000 or (org.bleed or 0) >= 3 then return false end
    if (org.pulse or 70) < 15 or (org.trachea or 0) >= 0.5 then return false end
    if (org.spine2 or 0) >= (hg.organism.fake_spine2 or 1) or (org.spine3 or 0) >= (hg.organism.fake_spine3 or 1) then return false end
    return true
end

function ZSCAV_NTSafety(owner, org)
    local NT = NeuroTrauma
    if not istable(NT) or not isfunction(NT.Get) or not ZSCAV_NeuroTraumaActive() then return end
    local st = NT.Get(org)
    if not st then return end
    local C = NT.Config or {}
    local stemFail = istable(C.Brain) and C.Brain.stemFailure or 0.95
    if (st.stemLasting or 0) >= stemFail then return end -- настоящий отказ ствола мозга - не трогаем
    if st.terminal then return end                         -- пуля винтовки в голову (правило аддона)
    if not TransientOnly(org) then return end
    local now = CurTime()
    local knocked = org.otrub or now < (st.locUntil or 0) or now < (st.apnoeaUntil or 0)
    if not knocked then return end
    if istable(org.o2) and (org.o2[1] or 30) < 9 then org.o2[1] = 9 end
    org.incapacitated = false
end
