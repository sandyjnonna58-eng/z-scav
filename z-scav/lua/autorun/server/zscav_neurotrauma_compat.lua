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
