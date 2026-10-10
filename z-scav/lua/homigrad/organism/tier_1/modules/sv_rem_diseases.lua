--[[
    Z-SCAV: болезни (список - lua/autorun/sh_zscav_diseases.lua).

    При появлении игрока каждая болезнь бросается отдельно со своим шансом
    (* zscav_disease_chance_mul). Выключить все: zscav_diseases 0, одну: zscav_disease_<id> 0.

    Первые 5 минут после заражения болезнь скрыта (бешенство - 10 минут), потом
    появляются симптомы и она видна в меню здоровья (zscav_my_disease - узнать свою).
    Иммунитет: ниже нормы - болезнь тяжелее и быстрее, выше - легче, а лечение быстрее.
    Передозировка (больше N упаковок за 2 минуты): химия/альбендазол/рифампицин/ингибиторы >2 -
    инфаркт, антибиотики >2 - интоксикация и 70% инфаркт, иммуноглобулин >10 - кровотечение и смерть. Смертельные на 100% переходят в терминальную стадию и убивают.
    Лечение - курс лекарства (несколько приёмов не чаще раза в 30 с): первый приём
    останавливает болезнь, каждый снимает часть симптомов, полный курс - излечение.

      ecd        Эрдгейма-Честера  ингибиторы x3     сердечные приступы, лёгкие, координация
      neurosyph  нейросифилис      антибиотики x3    голова, депрессия, рвота, координация
      ncc        нейроцистицеркоз  альбендазол x2    голова, ВЧД (мозг), координация, судороги
      rabies     бешенство         иммуноглобулин x1 инкубация 10-15 мин; после симптомов
                                                     (жар до 40, гидрофобия, тахикардия)
                                                     лекарство не помогает - 4 мин и смерть
      leprosy    проказа           рифампицин x4     пятна (кожа), слабость, мутное зрение
      house      докторская        викодин глушит    постоянная боль в правом бедре, не лечится
      sclc       рак лёгких        химия x1          кровохарканье, кашель, одышка;
                                                     химия: 20% - организм не выдерживает

    Команды (админ): zscav_disease_give <id> [ник], zscav_disease_cure [id|*] [ник],
                     zscav_disease_list [ник]
]]

local D = ZSCAV_DISEASES or {}
local ORDER = ZSCAV_DISEASE_ORDER or {}
local SYM_AT = ZSCAV_DISEASE_SYMPTOM_AT or 0.12
local DOSE_GAP = 60          -- сек между приёмами курса
local SYM_DELAY = 300        -- симптомы через 5 минут после заражения
local RABIES_DELAY = 600     -- бешенство - через 10 минут
local RABIES_SYM_TIME = 240
local OD_WINDOW = 120        -- "за раз": приёмы за последние 2 минуты
-- передозировка: больше LIMIT упаковок за раз
local OVERDOSE = {
    chemo       = {limit = 2,  kind = "heart"},
    albendazole = {limit = 2,  kind = "heart"},
    rifampicin  = {limit = 2,  kind = "heart"},
    inhibitors  = {limit = 2,  kind = "heart"},
    antibiotics = {limit = 2,  kind = "detox"},
    rabies_ig   = {limit = 10, kind = "bleed"},
}

-- иммунитет (40..200, норма 100): ниже - болезнь тяжелее и быстрее, выше - легче,
-- и лечение/выздоровление идёт быстрее
local function Imm(org) return math.Clamp(org.remImmunity or 100, 40, 200) end
local function SevMul(org) return math.Clamp(100 / Imm(org), 0.6, 1.6) end
local function HealMul(org) return math.Clamp(Imm(org) / 100, 0.5, 1.6) end

local MED_TO = {} -- лекарство -> болезни
for id, d in pairs(D) do if d.med then MED_TO[d.med] = MED_TO[d.med] or {} table.insert(MED_TO[d.med], id) end end

local function Say(owner, text, key)
    if IsValid(owner) and owner.Notify then owner:Notify(text, 5, key or "zscav_disease", 0, nil, Color(230, 210, 190)) end
end

local function Intensity(st, org) return math.Clamp((st.p - SYM_AT) / (1 - SYM_AT) * (org and SevMul(org) or 1), 0, 1) end

function hg.organism.GiveDisease(org, id)
    if not org or not D[id] then return end
    org.remDis = org.remDis or {}
    if org.remDis[id] then return end
    local now = CurTime()
    local st = {p = 0, doses = 0, lastDose = 0, treated = false, t0 = now}
    st.symAt = now + (id == "rabies" and RABIES_DELAY or SYM_DELAY)
    if id == "rabies" then st.incEnd = st.symAt end
    if id == "house" then st.p = 1 end
    org.remDis[id] = st
end

function hg.organism.CureDisease(org, id)
    if not org or not org.remDis then return end
    if id then org.remDis[id] = nil else org.remDis = {} end
    org.remDiseaseRegen = nil
    org.remDisHR = 0
end

local function Cured(owner, org, id)
    hg.organism.CureDisease(org, id)
    Say(owner, "Кажется, болезнь отступила. (" .. D[id].name .. ")", "zscav_disease_cure")
    if hg.organism.AddMoodPermanent then hg.organism.AddMoodPermanent(org, 6) end
end

-- инфаркт
function hg.organism.HeartAttack(owner, org, msg)
    if not org then return end
    org.heartstop = true
    org.arrhythmia = 1
    org.painadd = (org.painadd or 0) + 40
    Say(owner, msg or "Сердце!.. Грудь разрывает!", "zscav_od")
end

-- учёт приёма и передозировка ("не больше N упаковок за раз"). true - передоз.
-- amount - доля приёма (таблетка = 0.2, т.е. 5 таблеток = 1 прежний пузырёк)
function hg.organism.MedDose(owner, org, med, amount)
    local od = OVERDOSE[med]
    if not org or not od then return false end
    amount = amount or 1
    local now = CurTime()
    org.remMedLog = org.remMedLog or {}
    local log = org.remMedLog[med] or {}
    local fresh, sum = {}, 0
    for _, e in ipairs(log) do
        if istable(e) and now - e[1] < OD_WINDOW then fresh[#fresh + 1] = e sum = sum + e[2] end
    end
    fresh[#fresh + 1] = {now, amount}
    sum = sum + amount
    org.remMedLog[med] = fresh
    if sum <= od.limit + 0.001 then return false end
    org.remMedLog[med] = {} -- передоз уже случился, счёт заново

    if od.kind == "heart" then
        hg.organism.HeartAttack(owner, org, "Слишком много... сердце!")
    elseif od.kind == "detox" then
        -- антибиотики: тяжёлая интоксикация и высокий шанс инфаркта
        org.remAbxDetoxEnd = now + 120
        org.remAbxNextVomit = now + math.Rand(3, 8)
        Say(owner, "Меня всего выворачивает... перебрал с антибиотиками.", "zscav_od")
        if math.Rand(0, 1) < 0.7 then
            org.remAbxHeartAt = now + math.Rand(8, 25)
        end
    elseif od.kind == "bleed" then
        -- иммуноглобулин: обширное внутреннее кровотечение и смерть
        org.internalBleed = (org.internalBleed or 0) + 300
        org.blood = math.max((org.blood or 5000) - 1500, 0)
        org.painadd = (org.painadd or 0) + 30
        org.remIgDoomAt = now + 40
        Say(owner, "Внутри всё горит... кровь во рту...", "zscav_od")
    end
    return true
end

-- приём лекарства. Возвращает true, если лекарство что-то лечило.
function hg.organism.DiseaseMedicine(owner, org, med, amount)
    if not org then return false end
    amount = amount or 1
    if hg.organism.MedDose(owner, org, med, amount) then return true end
    if not org.remDis then return false end
    local now, any = CurTime(), false
    for _, id in ipairs(MED_TO[med] or {}) do
        local st = org.remDis[id]
        if st then
            any = true
            if id == "rabies" then
                if st.symStart then
                    Say(owner, "Слишком поздно... не помогает.")
                else
                    Cured(owner, org, id)
                end
            else
                -- 1 таблетка - небольшой эффект; 5 таблеток = 1 приём курса
                st.lastDose = now
                st.treated = true
                st.p = math.max(st.p - 0.3 * amount * HealMul(org), 0)
                st.doseAcc = (st.doseAcc or 0) + amount
                if st.doseAcc >= 0.999 then
                    st.doseAcc = st.doseAcc - 1
                    st.doses = st.doses + 1
                    if st.doses >= (D[id].doses or 1) then
                        Cured(owner, org, id)
                    else
                        Say(owner, ("Курс лечения: %d/%d"):format(st.doses, D[id].doses))
                    end
                end
            end
        end
    end
    return any
end

-- химиолучевая терапия: 20% - организм не выдерживает
function hg.organism.Chemotherapy(owner, org)
    if not org then return end
    if hg.organism.MedDose(owner, org, "chemo") then return end
    if math.Rand(0, 1) < 0.2 then
        Say(owner, "Организм не выдержал химиотерапии...", "zscav_chemo")
        if IsValid(owner) and owner:Alive() then owner:Kill() end
        return
    end
    if org.remDis and org.remDis.sclc then
        Cured(owner, org, "sclc")
    else
        Say(owner, "Химия... Зачем я это сделал.", "zscav_chemo")
    end
    -- побочные эффекты: тошнота и слабость несколько минут
    org.remChemoSick = CurTime() + 180
    org.remChemoNextVomit = CurTime() + math.Rand(5, 15)
end

local COUGH = {"ambient/voices/cough1.wav", "ambient/voices/cough2.wav", "ambient/voices/cough3.wav", "ambient/voices/cough4.wav"}

local function Vomit(owner, org)
    if not hg.organism.Vomit then return end
    local blood = org.blood
    hg.organism.Vomit(owner)
    if blood then org.blood = math.max(org.blood or 0, blood - 40) end
end

local function Every(st, key, now, a, b)
    if (st[key] or 0) <= now then
        local first = st[key] == nil
        st[key] = now + math.Rand(a, b)
        return not first
    end
    return false
end

local function Coordination(org, s)
    org.disorientation = math.max(org.disorientation or 0, 1.2 + 1.8 * s)
end

local function HeadachePain(org, s, base)
    org.pain = math.max(org.pain or 0, base * s)
end

local SYM = {}

SYM.ecd = function(owner, org, st, s, dt, now)
    Coordination(org, s)
    for _, k in ipairs({"lungsL", "lungsR"}) do
        if istable(org[k]) and (org[k][1] or 0) < 0.6 + 0.4 * st.p then org[k][1] = (org[k][1] or 0) + dt * 0.0005 * s end
    end
    if math.Rand(0, 1) < dt * 0.003 * s then
        org.arrhythmia = math.min((org.arrhythmia or 0) + 0.45, 1)
        org.painadd = (org.painadd or 0) + 20
        Say(owner, "Сердце... грудь сжимает!")
    end
    if st.p >= 1 and not st.ended then
        st.ended = true
        org.heartstop = true
        Say(owner, "Сердце... не...")
    end
end

SYM.neurosyph = function(owner, org, st, s, dt, now)
    Coordination(org, s)
    HeadachePain(org, s, 30)
    if hg.organism.AddDepression then hg.organism.AddDepression(org, dt * 0.002 * s) end
    if s > 0.3 and Every(st, "nextVomit", now, 90, 160) then Vomit(owner, org) end
    if Every(st, "nextLine", now, 70, 120) then Say(owner, table.Random({"Голова...", "Что-то со мной не так.", "Мысли путаются."})) end
    if st.p >= 1 then org.brain = math.min((org.brain or 0) + dt * 0.006, 1) end
end

SYM.ncc = function(owner, org, st, s, dt, now)
    Coordination(org, s)
    HeadachePain(org, s, 35)
    -- ВЧД: повышает внутричерепное давление (sv_rem_icp.lua), а уже оно бьёт по мозгу
    org.remICPAdd = math.max(org.remICPAdd or 0, 12 + 26 * s)
    if s > 0.4 and Every(st, "nextVomit", now, 110, 200) then Vomit(owner, org) end
    if hg.organism.AddSeizure and math.Rand(0, 1) < dt * 0.0025 * s then hg.organism.AddSeizure(org, 1) end
    if Every(st, "nextLine", now, 70, 120) then Say(owner, table.Random({"Голову распирает...", "В глазах темнеет.", "Давит изнутри черепа."})) end
    if st.p >= 1 then org.brain = math.min((org.brain or 0) + dt * 0.006, 1) end
end

SYM.rabies = function(owner, org, st, s, dt, now)
    if not st.symStart then
        if now < (st.incEnd or 0) then st.p = 0.01 return end
        st.symStart = now
        Say(owner, "Меня знобит... что-то не так.")
    end
    local t = math.Clamp((now - st.symStart) / RABIES_SYM_TIME, 0, 1)
    st.p = math.max(st.p, SYM_AT + (1 - SYM_AT) * t)
    org.remRabiesSym = true
    -- жар до 40
    org.temperature = math.max(org.temperature or 36.7, Lerp(t, 38, 40))
    org.remDisHR = math.max(org.remDisHR or 0, 25 + 40 * t)
    org.fear = math.max(org.fear or 0, 0.3 + 0.5 * t)
    if Every(st, "nextLine", now, 40, 70) then Say(owner, table.Random({"Вода... нет, только не вода!", "Горло сводит...", "Жарко. Так жарко.", "Сердце колотится."})) end
    if t >= 1 then org.brain = math.min((org.brain or 0) + dt * 0.03, 1) end
end

SYM.leprosy = function(owner, org, st, s, dt, now)
    org.remDiseaseRegen = math.min(org.remDiseaseRegen or 1, 1 - 0.45 * s)
    if org.remSkin and hg.organism.DamageSkin and Every(st, "nextSpot", now, 25, 50) then
        local parts = {}
        for p in pairs(org.remSkin) do parts[#parts + 1] = p end
        if #parts > 0 then hg.organism.DamageSkin(org, parts[math.random(#parts)], 6 + 10 * s) end
    end
    if Every(st, "nextLine", now, 120, 200) then Say(owner, table.Random({"Пятна на коже... их всё больше.", "Всё как в тумане.", "Нет сил."})) end
end

SYM.house = function(owner, org, st, s, dt, now)
    -- боль в правом бедре; викодин (и другие обезболивающие) приглушают
    local an = math.Clamp((org.analgesia or 0) + (org.painkiller or 0) * 0.5, 0, 1)
    local relief = 1 - 0.85 * an
    org.pain = math.max(org.pain or 0, 32 * relief)
    local ent = hg.GetCurrentCharacter and hg.GetCurrentCharacter(owner) or owner
    local speed = IsValid(ent) and ent:GetVelocity():Length() or 0
    if speed > 60 then org.pain = math.min((org.pain or 0) + dt * 8 * relief, 70) end
    if relief > 0.5 and Every(st, "nextLine", now, 90, 160) then Say(owner, table.Random({"Нога... опять.", "Бедро горит.", "Где мой викодин?"})) end
end

SYM.sclc = function(owner, org, st, s, dt, now)
    for _, k in ipairs({"lungsL", "lungsR"}) do
        if istable(org[k]) and (org[k][1] or 0) < 0.5 + 0.5 * st.p then org[k][1] = (org[k][1] or 0) + dt * 0.0004 * s end
    end
    if istable(org.o2) then org.o2[1] = math.max((org.o2[1] or 30) - dt * 0.25 * s, 0) end
    if Every(st, "nextCough", now, 60 - 40 * s, 90 - 50 * s) then
        local ent = hg.GetCurrentCharacter and hg.GetCurrentCharacter(owner) or owner
        if IsValid(ent) then ent:EmitSound(COUGH[math.random(#COUGH)], 65, math.random(95, 105)) end
        if s > 0.3 and math.random(1, 3) == 1 then
            org.blood = math.max((org.blood or 5000) - math.Rand(20, 50), 0)
            Say(owner, "Кашляю кровью...")
        end
    end
    if st.p >= 1 and istable(org.o2) then org.o2[1] = math.max((org.o2[1] or 30) - dt * 1.5, 0) end
end

-- вызывается из основного цикла организма
function hg.organism.DiseaseThink(owner, org, timeValue, isPly)
    org.remDiseaseRegen = nil
    org.remDisHR = 0
    org.remRabiesSym = nil
    if not isPly or not org.alive then return end
    local now, dt = CurTime(), timeValue or 0

    -- побочка химии
    if (org.remChemoSick or 0) > now then
        org.remDiseaseRegen = 0.6
        if (org.remChemoNextVomit or 0) < now then
            org.remChemoNextVomit = now + math.Rand(40, 70)
            Vomit(owner, org)
        end
    end

    -- передоз антибиотиков: интоксикация (рвота, боль), возможен инфаркт
    if (org.remAbxDetoxEnd or 0) > now then
        org.pain = math.max(org.pain or 0, 40)
        org.remDiseaseRegen = math.min(org.remDiseaseRegen or 1, 0.5)
        if (org.remAbxNextVomit or 0) < now then
            org.remAbxNextVomit = now + math.Rand(18, 30)
            Vomit(owner, org)
        end
    end
    if org.remAbxHeartAt and now >= org.remAbxHeartAt then
        org.remAbxHeartAt = nil
        hg.organism.HeartAttack(owner, org)
    end
    -- передоз иммуноглобулина: смерть
    if org.remIgDoomAt and now >= org.remIgDoomAt then
        org.remIgDoomAt = nil
        if IsValid(owner) and owner:Alive() then owner:Kill() end
        return
    end

    -- докторская болезнь: очень редко - трость
    if org.remDis and org.remDis.house and (org.remCaneNext or 0) < now then
        org.remCaneNext = now + 60
        if math.Rand(0, 1) < 0.004 and hg.organism.ShowCane then hg.organism.ShowCane(owner) end
    end

    if not org.remDis then return end
    for id, st in pairs(org.remDis) do
        local d = D[id]
        local fn = SYM[id]
        if not d or not fn or not GetConVar("zscav_disease_" .. id):GetBool() then continue end
        -- до симптомов (5 мин, бешенство 10 мин) болезнь скрыта
        if id ~= "house" and now < (st.symAt or 0) then
            -- лекарство до симптомов тоже работает (иммуноглобулин - только до них)
            continue
        end
        if id ~= "house" and id ~= "rabies" and st.p < SYM_AT and not st.treated then st.p = SYM_AT end
        if st.treated then
            -- идёт лечение: выздоровление, быстрее при хорошем иммунитете
            if id ~= "house" and id ~= "rabies" then
                st.p = math.max(st.p - dt * 0.0006 * HealMul(org), 0)
                if st.p <= 0 then Cured(owner, org, id) continue end
            end
        elseif (d.time or 0) > 0 and id ~= "rabies" then
            -- болезнь развивается; при слабом иммунитете быстрее
            st.p = math.min(st.p + dt / d.time * SevMul(org), d.lethal and 1.2 or 1)
        end
        if id == "rabies" or st.p >= SYM_AT then
            if not st.announced and id ~= "rabies" and id ~= "house" then
                st.announced = true
                Say(owner, "Мне нехорошо... (" .. d.name .. ")")
            end
            fn(owner, org, st, Intensity(st, org), dt, now)
        end
    end
end

-- бросок болезней при появлении
hook.Add("PlayerSpawn", "ZSCAV_Diseases", function(ply)
    timer.Simple(1.5, function()
        if not IsValid(ply) or not ply:Alive() or not ply.organism then return end
        local org = ply.organism
        org.remDis = {}
        if not GetConVar("zscav_diseases"):GetBool() then return end
        local mul = GetConVar("zscav_disease_chance_mul"):GetFloat()
        for _, id in ipairs(ORDER) do
            if GetConVar("zscav_disease_" .. id):GetBool() and math.Rand(0, 1) < D[id].chance * mul then
                hg.organism.GiveDisease(org, id)
                -- докторская болезнь: очень редко - трость сразу при заболевании
                if id == "house" and math.Rand(0, 1) < 0.05 then
                    timer.Simple(math.Rand(10, 40), function()
                        if IsValid(ply) and ply:Alive() and hg.organism.ShowCane then hg.organism.ShowCane(ply) end
                    end)
                end
            end
        end
    end)
end)

hook.Add("Org Clear", "ZSCAV_Diseases", function(org)
    org.remDis = {}
    org.remChemoSick = 0
    org.remDiseaseRegen, org.remDisHR, org.remRabiesSym = nil, 0, nil
end)

-- ---------------------------------------------------------------------------
-- команды
-- ---------------------------------------------------------------------------
local function Target(caller, nick)
    if nick and nick ~= "" then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(nick), 1, true) then return p end
        end
        return
    end
    return caller
end
local function Reply(c, m) if IsValid(c) then c:ChatPrint(m) else print(m) end end

concommand.Add("zscav_disease_give", function(c, _, args)
    if IsValid(c) and not c:IsAdmin() then return end
    local id, p = args[1], Target(c, args[2])
    if not D[id or ""] then Reply(c, "Болезни: " .. table.concat(ORDER, ", ")) return end
    if not IsValid(p) or not p.organism then Reply(c, "Игрок не найден.") return end
    hg.organism.GiveDisease(p.organism, id)
    -- для проверки - сразу с симптомами
    local st = p.organism.remDis[id]
    local quiet = args[3] == "0" -- zscav_disease_give <id> <ник> 0 - без ускорения, по-настоящему
    if not quiet then
        st.symAt = CurTime() + 3
        if id == "rabies" then st.incEnd = st.symAt end
    end
    Reply(c, D[id].name .. " -> " .. p:Nick())
end)

concommand.Add("zscav_disease_cure", function(c, _, args)
    if IsValid(c) and not c:IsAdmin() then return end
    local id, p = args[1], Target(c, args[2])
    if not IsValid(p) or not p.organism then Reply(c, "Игрок не найден.") return end
    hg.organism.CureDisease(p.organism, (id and id ~= "*" and D[id]) and id or nil)
    Reply(c, "Вылечено: " .. p:Nick())
end)

concommand.Add("zscav_disease_list", function(c, _, args)
    if IsValid(c) and not c:IsAdmin() then return end
    local p = Target(c, args[1])
    if not IsValid(p) or not p.organism then return end
    local out = {}
    for id, st in pairs(p.organism.remDis or {}) do
        out[#out + 1] = ("%s %d%%%s"):format(D[id].name, math.Round(st.p * 100), st.treated and (" курс " .. st.doses .. "/" .. D[id].doses) or "")
    end
    Reply(c, p:Nick() .. ": " .. (#out > 0 and table.concat(out, "; ") or "здоров"))
end)

-- любой игрок: какая у меня болезнь (в консоль и в чат)
local function FmtTime(sec) sec = math.max(0, math.floor(sec)) return ("%d:%02d"):format(sec / 60, sec % 60) end
concommand.Add("zscav_my_disease", function(ply)
    if not IsValid(ply) or not ply.organism then return end
    local org, now = ply.organism, CurTime()
    local lines = {}
    for _, id in ipairs(ORDER) do
        local st = org.remDis and org.remDis[id]
        if st then
            local d = D[id]
            local state
            if id ~= "house" and now < (st.symAt or 0) then
                state = "без симптомов, проявится через " .. FmtTime(st.symAt - now)
            elseif id == "rabies" and st.symStart then
                state = "симптомы! осталось ~" .. FmtTime(st.symStart + RABIES_SYM_TIME - now)
            else
                state = ("развитие %d%%"):format(math.min(st.p, 1) * 100)
            end
            if st.treated and d.doses > 0 then state = state .. (" | курс %d/%d"):format(st.doses, d.doses) end
            lines[#lines + 1] = ("%s (%s) - %s. Лекарство: %s. %s."):format(d.name, d.kind, state, d.cure, d.lethal and "СМЕРТЕЛЬНО" or "не смертельно")
        end
    end
    lines[#lines + 1] = ("Иммунитет: %d%%"):format(Imm(org))
    if #lines == 1 then table.insert(lines, 1, "Болезней нет.") end
    for _, l in ipairs(lines) do
        ply:PrintMessage(HUD_PRINTCONSOLE, l)
        ply:ChatPrint(l)
    end
end)

-- трость (эффект докторской болезни)
util.AddNetworkString("zscav_cane")
function hg.organism.ShowCane(ply)
    if not IsValid(ply) then return end
    net.Start("zscav_cane") net.Send(ply)
end
