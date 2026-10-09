--[[
    Z-SCAV: мысли персонажа во время таймера умирания.

    Пока идёт таймер ("You will die in..."), на экране одна за другой проступают
    мысли персонажа: сначала растерянность и попытки держаться, потом воспоминания,
    к концу - обрывки слов. Текст печатается по буквам, дрожит и гаснет.
    Набор мыслей зависит от настроения (хорошее - больше упрямства и надежды).

    zscav_dying_thoughts 0 - выключить.
]]

local cv = CreateClientConVar("zscav_dying_thoughts", "1", true, false, "Z-SCAV: мысли при умирании")

surface.CreateFont("ZSCAV_DyingThought", {font = "Courier New", size = math.max(18, math.floor(ScrH() / 38)), weight = 700, antialias = true, extended = true})
hook.Add("OnScreenSizeChanged", "ZSCAV_DyingThoughtFont", function()
    surface.CreateFont("ZSCAV_DyingThought", {font = "Courier New", size = math.max(18, math.floor(ScrH() / 38)), weight = 700, antialias = true, extended = true})
end)

-- фазы: доля прошедшего времени умирания -> набор мыслей
local PHASES = {
    { -- 0..35%: шок, попытки держаться
        until_ = 0.35,
        common = {
            "Что... что случилось?",
            "Я не чувствую рук.",
            "Почему так холодно?",
            "Вставай. Ну же, вставай.",
            "Кто-нибудь... хоть кто-нибудь...",
            "Уже даже не больно.",
            "Дыши. Просто дыши.",
            "Это не по-настоящему. Не может быть.",
        },
        good = {
            "Нет. Только не так.",
            "Я ещё выберусь. Я должен.",
            "Держись. Продержись ещё немного.",
        },
        bad = {
            "Ну конечно. Конечно, всё кончается вот так.",
            "Никто не придёт.",
            "Я знал, что рано или поздно это случится.",
        },
    },
    { -- 35..75%: воспоминания
        until_ = 0.75,
        common = {
            "Я так и не перезвонил...",
            "Мама пела, когда шёл дождь.",
            "Я всё ещё должен ему двадцатку.",
            "Лето у озера... было тепло.",
            "Я хотел увидеть море ещё раз.",
            "Я запер дверь?",
            "Забавно. Я всегда думал, что времени будет больше.",
            "Собака. Кто покормит собаку?",
            "Надо было извиниться.",
        },
        good = {
            "Хорошая была жизнь. В основном.",
            "Я хотя бы пытался.",
            "Я бы прожил всё это снова.",
        },
        bad = {
            "Я столько всего упустил.",
            "Кто-нибудь вообще заметит?",
            "Прости. За всё.",
        },
    },
    { -- 75..100%: обрывки
        until_ = 1.01,
        common = {
            "так... устал...",
            "теперь тихо",
            "...",
            "ещё... минутку...",
            "dark",
            "can't...",
            "warm...",
            "кто... там...",
        },
        good = {"не... сейчас...", "please..."},
        bad = {"finally...", "пусть..."},
    },
}

local shown = {}      -- активные надписи {text, born, life, x, y, typed}
local used = {}       -- чтобы не повторяться за одно умирание
local nextAt = 0
local wasDying = false
local dyingTotal = 0

local function PickThought(phase, mood)
    local pool = {}
    for _, t in ipairs(phase.common) do pool[#pool + 1] = t end
    if mood > 0.2 then for _, t in ipairs(phase.good) do pool[#pool + 1] = t; pool[#pool + 1] = t end end
    if mood < -0.3 then for _, t in ipairs(phase.bad) do pool[#pool + 1] = t; pool[#pool + 1] = t end end
    for _ = 1, 12 do
        local t = pool[math.random(#pool)]
        if not used[t] then used[t] = true return t end
    end
    return pool[math.random(#pool)]
end

local function DyingState()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    local org = ply.organism
    if not org or not org.otrub or org.remSleep then return false end
    local dEnd = tonumber(org.deathStateEnd) or 0
    if dEnd <= 0 then return false end
    return true, math.max(dEnd - CurTime(), 0), org
end

hook.Add("HUDPaint", "ZSCAV_DyingThoughts", function()
    if not cv:GetBool() then return end
    local dying, left, org = DyingState()
    local now = RealTime()

    if not dying then
        if wasDying then
            wasDying = false
            table.Empty(used)
        end
        -- уже показанные мысли спокойно догорают
        for i = #shown, 1, -1 do
            local s = shown[i]
            s.life = math.min(s.life, now - s.born + 0.6)
            if now - s.born > s.life then table.remove(shown, i) end
        end
        if #shown == 0 then return end
    else
        if not wasDying then
            wasDying = true
            dyingTotal = left
            nextAt = now + 1.2
            table.Empty(shown)
        end
        if left > dyingTotal then dyingTotal = left end -- дефибриллятор продлил

        local progress = dyingTotal > 0 and (1 - left / dyingTotal) or 1
        if now >= nextAt and #shown < 3 then
            local phase = PHASES[#PHASES]
            for _, ph in ipairs(PHASES) do
                if progress < ph.until_ then phase = ph break end
            end
            local text = PickThought(phase, tonumber(org.mood) or 0)
            local w, h = ScrW(), ScrH()
            -- мысли всплывают выше кольца, слегка в разных местах
            local x = w * 0.5 + math.Rand(-w * 0.18, w * 0.18)
            local y = h * math.Rand(0.16, 0.34)
            shown[#shown + 1] = {text = text, born = now, life = math.Rand(5, 7) - progress * 1.5, x = x, y = y, prog = progress}
            -- к концу мысли реже и короче
            nextAt = now + math.Rand(3.2, 5) + progress * 2.5
        end
    end

    for i = #shown, 1, -1 do
        local s = shown[i]
        local age = now - s.born
        if age > s.life then
            table.remove(shown, i)
        else
            -- печать по буквам, потом угасание
            local typed = math.min(#s.text, math.floor(age * 22))
            local str = string.sub(s.text, 1, typed)
            local a = math.Clamp(age / 0.6, 0, 1) * math.Clamp((s.life - age) / 1.6, 0, 1)
            local fade = 1 - (s.prog or 0) * 0.45 -- ближе к концу всё бледнее
            local jx = math.Rand(-1, 1) * (1 + (s.prog or 0) * 2)
            local jy = math.Rand(-1, 1) * (1 + (s.prog or 0) * 2)
            local yDrift = -age * 4
            draw.SimpleText(str, "ZSCAV_DyingThought", s.x + jx + 2, s.y + yDrift + jy + 2, Color(0, 0, 0, 200 * a * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(str, "ZSCAV_DyingThought", s.x + jx, s.y + yDrift + jy, Color(225, 225, 230, 235 * a * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)
