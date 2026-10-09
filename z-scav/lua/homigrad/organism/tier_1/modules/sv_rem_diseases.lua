--[[
    Z-SCAV: болезни (список - lua/autorun/sh_zscav_diseases.lua).

    При появлении игрока каждая болезнь бросается отдельно со своим шансом
    (* zscav_disease_chance_mul). Выключить все: zscav_diseases 0, одну: zscav_disease_<id> 0.

    Болезнь тихо развивается (прогресс 0..1), с 12% появляются симптомы и она видна
    в меню здоровья. Смертельные на 100% переходят в терминальную стадию и убивают.
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
local DOSE_GAP = 30
local RABIES_INC = {600, 900}
local RABIES_SYM_TIME = 240

local MED_TO = {} -- лекарство -> болезни
for id, d in pairs(D) do if d.med then MED_TO[d.med] = MED_TO[d.med] or {} table.insert(MED_TO[d.med], id) end end

local function Say(owner, text, key)
    if IsValid(owner) and owner.Notify then owner:Notify(text, 5, key or "zscav_disease", 0, nil, Color(230, 210, 190)) end
end

local function Intensity(st) return math.Clamp((st.p - SYM_AT) / (1 - SYM_AT), 0, 1) end

function hg.organism.GiveDisease(org, id)
    if not org or not D[id] then return end
    org.remDis = org.remDis or {}
    if org.remDis[id] then return end
    local st = {p = 0, doses = 0, lastDose = 0, treated = false}
    if id == "rabies" then st.incEnd = CurTime() + math.Rand(RABIES_INC[1], RABIES_INC[2]) end
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

-- приём лекарства. Возвращает true, если лекарство что-то лечило.
function hg.organism.DiseaseMedicine(owner, org, med)
    if not org or not org.remDis then return false end
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
            elseif now - (st.lastDose or 0) < DOSE_GAP then
                Say(owner, "Рано для следующего приёма.")
            else
                st.lastDose = now
                st.doses = st.doses + 1
                st.treated = true
                st.p = math.max(st.p - 0.3, 0)
                if st.doses >= (D[id].doses or 1) then
                    Cured(owner, org, id)
                else
                    Say(owner, ("Курс лечения: %d/%d"):format(st.doses, D[id].doses))
                end
            end
        end
    end
    return any
end

-- химиолучевая терапия: 20% - организм не выдерживает
function hg.organism.Chemotherapy(owner, org)
    if not org then return end
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
    -- ВЧД: мозг понемногу страдает
    if (org.brain or 0) < 0.45 then org.brain = (org.brain or 0) + dt * 0.00015 * s end
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

    if not org.remDis then return end
    for id, st in pairs(org.remDis) do
        local d = D[id]
        local fn = SYM[id]
        if not d or not fn or not GetConVar("zscav_disease_" .. id):GetBool() then continue end
        if not st.treated and (d.time or 0) > 0 and id ~= "rabies" then
            st.p = math.min(st.p + dt / d.time, d.lethal and 1.2 or 1)
        end
        if id == "rabies" or st.p >= SYM_AT then
            if not st.announced and id ~= "rabies" and id ~= "house" then
                st.announced = true
                Say(owner, "Мне нехорошо... (" .. d.name .. ")")
            end
            fn(owner, org, st, Intensity(st), dt, now)
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
    if id == "rabies" then st.incEnd = CurTime() + 5 elseif id ~= "house" then st.p = math.max(st.p, SYM_AT + 0.05) end
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
