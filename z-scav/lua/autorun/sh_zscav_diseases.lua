--[[
    Z-SCAV: список болезней (общий для сервера и клиента).
    Логика - lua/homigrad/organism/tier_1/modules/sv_rem_diseases.lua
    Эффекты на экране - lua/autorun/client/cl_zscav_diseases.lua

    БОЛЕЗНЬ | ВИД | ЛЕКАРСТВО | СИМПТОМЫ | СМЕРТЕЛЬНО | ШАНС ПРИ ПОЯВЛЕНИИ
]]

ZSCAV_DISEASES = {
    ecd = {
        name = "Болезнь Эрдгейма-Честера", kind = "генетическая мутация", cure = "ингибиторы",
        symptoms = "сердечный приступ, поражение лёгких, нарушение координации",
        lethal = true, chance = 0.10, time = 2400, med = "inhibitors", doses = 3,
    },
    neurosyph = {
        name = "Нейросифилис", kind = "венерическое", cure = "антибиотики",
        symptoms = "головная боль, депрессия, рвота, нарушение координации",
        lethal = true, chance = 0.30, time = 1800, med = "antibiotics", doses = 3,
    },
    ncc = {
        name = "Нейроцистицеркоз", kind = "паразит", cure = "альбендазол",
        symptoms = "головная боль, ВЧД, нарушение координации, эпилепсия",
        lethal = true, chance = 0.2477, time = 1800, med = "albendazole", doses = 2,
    },
    rabies = {
        name = "Бешенство", kind = "вирус", cure = "антирабический иммуноглобулин (только до симптомов)",
        symptoms = "температура до 40 °C, гидрофобия, тахикардия",
        lethal = true, chance = 0.05, time = 900, med = "rabies_ig", doses = 1,
    },
    leprosy = {
        name = "Проказа", kind = "хроническая инфекция", cure = "рифампицин",
        symptoms = "пятна на коже, слабость, ухудшение зрения",
        lethal = false, chance = 0.10, time = 1800, med = "rifampicin", doses = 4,
    },
    house = {
        name = "Докторская болезнь", kind = "инфаркт бедра правой ноги", cure = "викодин (не лечится)",
        symptoms = "хроническая сильная боль в ноге",
        lethal = false, chance = 0.0023, time = 0, med = nil, doses = 0,
    },
    sclc = {
        name = "Мелкоклеточный рак лёгких", kind = "рак", cure = "химиолучевая терапия (риск смерти 20%)",
        symptoms = "кровохарканье, кашель, одышка",
        lethal = true, chance = 0.20, time = 2100, med = "chemo", doses = 1,
    },
}
ZSCAV_DISEASE_ORDER = {"ecd", "neurosyph", "ncc", "rabies", "leprosy", "house", "sclc"}
ZSCAV_DISEASE_SYMPTOM_AT = 0.12 -- с этого прогресса болезнь проявляется (и видна в меню здоровья)

-- переключатели (сервер, реплицируются)
CreateConVar("zscav_diseases", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY, "Z-SCAV: болезни при появлении", 0, 1)
CreateConVar("zscav_disease_chance_mul", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Z-SCAV: множитель шанса болезней", 0, 10)
for _, id in ipairs(ZSCAV_DISEASE_ORDER) do
    CreateConVar("zscav_disease_" .. id, "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Z-SCAV: болезнь " .. ZSCAV_DISEASES[id].name, 0, 1)
end
