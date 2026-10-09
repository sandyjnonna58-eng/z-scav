--[[
    Z-SCAV: Викодин - обезболивающее с привыканием (weapon_zscav_vicodin).

    Таблетка: как морфин, но в 2-3 раза слабее (+0.4 обезболивания против 1.0).
    У викодина есть "потолок" - если обезболивания уже много, таблетка почти ничего не добавляет,
    поэтому передознуться им сложно.

    Привыкание: каждая таблетка добавляет 15-25% зависимости. С 40% персонаж зависим.
    Зависимый без таблеток:
      - примерно каждые ~100 с говорит (субтитрами), что болит голова; каждая такая фраза -
        шаг к детоксикации (фразы становятся всё хуже);
      - через 10 минут без викодина начинается ДЕТОКСИКАЦИЯ (ломка) на 3 минуты:
        сильная боль, каждое движение отдаётся болью, рвота. От этой боли сознание НЕ теряется.
      - пережил ломку (не принимал викодин до конца) - зависимость пропадает.
      - выпил таблетку во время ломки - ломка прекращается, но зависимость остаётся и всё сначала.

    zscav_vicodin_addict [0..1] - выставить себе зависимость (админ), zscav_vicodin_detox - сразу ломка.
]]

hg.organism.vicodinCfg = hg.organism.vicodinCfg or {}
local CFG = hg.organism.vicodinCfg
CFG.DOSE          = 0.4    -- обезболивание за таблетку (морфин - 1.0)
CFG.CEILING       = 1.2    -- выше этого суммарного обезболивания таблетка не добавляет (передоз с 1.5)
CFG.ADDICT_MIN    = 0.15
CFG.ADDICT_MAX    = 0.25
CFG.ADDICTED      = 0.4
CFG.FIRST_LINE    = 100    -- сек без таблетки до первой жалобы
CFG.LINE_EVERY    = {80, 115}
CFG.DETOX_AFTER   = 600    -- 10 минут без викодина
CFG.DETOX_TIME    = 180
CFG.DETOX_PAIN    = {45, 65} -- фоновая боль ломки (растёт к середине)
CFG.MOVE_PAIN     = 14     -- боль за секунду бега/движения
CFG.PAIN_MAX      = 78     -- выше 80 боль даёт шок - не даём
CFG.VOMIT_EVERY   = {30, 55}

local HEADACHE = {
    "Голова побаливает...",
    "Голова раскалывается. Где мои таблетки?",
    "Виски ломит... одну таблетку. Всего одну.",
    "Голова... как будто сверлят изнутри.",
    "Не могу думать. Голова. Мне нужен викодин.",
    "Всё болит. ВСЁ. Где эти чёртовы таблетки?!",
}
local DETOX_START = "Началось... всё тело выкручивает."
local DETOX_LINES = {"Больно... каждое движение...", "Меня сейчас вырвет...", "Терпи. Просто терпи.", "Кости ломит..."}
local MOVE_LINES = {"Ай!..", "Чёрт, больно!", "Ох... медленнее..."}
local DETOX_END = "Кажется... отпустило. Таблетки больше не нужны."

local function Say(owner, text)
    if IsValid(owner) and owner.Notify then owner:Notify(text, 6, "zscav_vicodin", 0, nil, Color(215, 215, 255)) end
end

-- принять таблетку (вызывается из weapon_zscav_vicodin)
function hg.organism.VicodinTake(org)
    if not org then return end
    local total = (org.analgesia or 0) + (org.analgesiaAdd or 0)
    local add = math.Clamp(CFG.CEILING - total, 0, CFG.DOSE)
    org.analgesiaAdd = math.min((org.analgesiaAdd or 0) + add, 4)
    if hg.organism.AddDrugHigh then hg.organism.AddDrugHigh(org, add * 0.25) end

    local now = CurTime()
    org.remVicLast = now
    org.remVicLines = 0
    org.remVicNextLine = now + CFG.FIRST_LINE
    org.remVicAddict = math.min((org.remVicAddict or 0) + math.Rand(CFG.ADDICT_MIN, CFG.ADDICT_MAX), 1)
    if (org.remVicDetoxEnd or 0) > now then
        org.remVicDetoxEnd = 0
        Say(org.owner, "Полегчало... Но надолго ли.")
    end
end

local function StartDetox(owner, org, now)
    org.remVicDetoxEnd = now + CFG.DETOX_TIME
    org.remVicDetoxStart = now
    org.remVicNextVomit = now + math.Rand(8, 15)
    org.remVicNextDetoxLine = now + math.Rand(20, 30)
    Say(owner, DETOX_START)
end

-- вызывается из основного цикла организма (до решения "без сознания")
function hg.organism.VicodinThink(owner, org, timeValue, isPly)
    if not isPly or not org.alive then return end
    local now = CurTime()
    local addict = org.remVicAddict or 0

    -- ЛОМКА
    if (org.remVicDetoxEnd or 0) > now then
        local frac = math.Clamp((now - (org.remVicDetoxStart or now)) / CFG.DETOX_TIME, 0, 1)
        local base = Lerp(math.sin(frac * math.pi), CFG.DETOX_PAIN[1], CFG.DETOX_PAIN[2])
        org.pain = math.max(org.pain or 0, base)

        -- каждое движение отдаётся болью
        local ent = IsValid(owner) and hg.GetCurrentCharacter and hg.GetCurrentCharacter(owner) or owner
        local speed = IsValid(ent) and ent:GetVelocity():Length() or 0
        if speed > 40 then
            local k = math.Clamp(speed / 200, 0.3, 1.5)
            org.pain = math.min((org.pain or 0) + CFG.MOVE_PAIN * k * timeValue, math.max(CFG.PAIN_MAX, base))
            if (org.remVicNextMoveLine or 0) < now and math.random(1, 40) == 1 then
                org.remVicNextMoveLine = now + 12
                Say(owner, MOVE_LINES[math.random(#MOVE_LINES)])
            end
        end

        -- от боли ломки сознание не теряется: шок ниже порога, сознание держится
        org.shock = math.min(org.shock or 0, 20)
        org.consciousness = math.max(org.consciousness or 1, 0.55)

        -- рвота
        if (org.remVicNextVomit or 0) < now then
            org.remVicNextVomit = now + math.Rand(CFG.VOMIT_EVERY[1], CFG.VOMIT_EVERY[2])
            if hg.organism.Vomit then
                local blood = org.blood
                hg.organism.Vomit(owner)
                if blood then org.blood = math.max(org.blood or 0, blood - 50) end -- рвота при ломке почти не тратит кровь
            end
        end
        if (org.remVicNextDetoxLine or 0) < now then
            org.remVicNextDetoxLine = now + math.Rand(25, 40)
            Say(owner, DETOX_LINES[math.random(#DETOX_LINES)])
        end
        return
    elseif (org.remVicDetoxEnd or 0) > 0 then
        -- пережил ломку
        org.remVicDetoxEnd = 0
        org.remVicAddict = 0
        org.remVicLines = 0
        Say(owner, DETOX_END)
        if hg.organism.AddMoodPermanent then hg.organism.AddMoodPermanent(org, 5) end
        return
    end

    if addict < CFG.ADDICTED or not org.remVicLast then return end
    local since = now - org.remVicLast

    -- 10 минут без викодина - ломка
    if since >= CFG.DETOX_AFTER then
        StartDetox(owner, org, now)
        return
    end

    -- жалобы на голову: каждая - шаг к детоксикации
    if (org.remVicNextLine or 0) <= now and not org.otrub then
        org.remVicNextLine = now + math.Rand(CFG.LINE_EVERY[1], CFG.LINE_EVERY[2])
        org.remVicLines = (org.remVicLines or 0) + 1
        local idx = math.Clamp(math.ceil(since / CFG.DETOX_AFTER * #HEADACHE), 1, #HEADACHE)
        Say(owner, HEADACHE[idx])
        org.pain = math.max(org.pain or 0, 8 + idx * 3) -- голова и правда болит
    end
end

hook.Add("Org Clear", "ZSCAV_Vicodin", function(org)
    org.remVicAddict, org.remVicLast, org.remVicLines = 0, nil, 0
    org.remVicNextLine, org.remVicDetoxEnd, org.remVicDetoxStart = 0, 0, 0
end)

-- админ-команды для проверки
concommand.Add("zscav_vicodin_addict", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not IsValid(ply) or not ply.organism then return end
    local org = ply.organism
    org.remVicAddict = math.Clamp(tonumber(args[1] or "") or 1, 0, 1)
    org.remVicLast = CurTime()
    org.remVicNextLine = CurTime() + 10
    ply:ChatPrint(("Зависимость от викодина: %d%%"):format(math.Round(org.remVicAddict * 100)))
end)

concommand.Add("zscav_vicodin_detox", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not IsValid(ply) or not ply.organism then return end
    ply.organism.remVicAddict = math.max(ply.organism.remVicAddict or 0, CFG.ADDICTED)
    StartDetox(ply, ply.organism, CurTime())
end)
