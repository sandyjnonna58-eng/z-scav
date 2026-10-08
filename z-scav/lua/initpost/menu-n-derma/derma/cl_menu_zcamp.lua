--[[
    ZCampMenu - главное меню-"лагерь".

    Вся сцена - одна картинка (materials/vgui/rem_camp_bg.png), на ней три интерактивные зоны:
        * аватар игрока (вместо фурри)   -> продолжить игру
        * синяя капсула (лампа слева)     -> выбор скина (редактор внешности)
        * планшет возле мешка             -> настройки
        * плеер с наушниками              -> ЛКМ: достижения, ПКМ: титры
        * спальный мешок                  -> выход

    Аватар - это тот же preview-model, что и в старом меню, поэтому он
    всегда показывает текущую внешность (hg_appearance_selected) и меняется
    вместе с ней, в том числе вживую в редакторе внешности.

    Загружается ПОСЛЕ cl_menu_panel.lua (файлы грузятся по алфавиту), наследуется
    от ZMainMenu и подменяет хук OnPauseMenuShow.

    Все координаты зон заданы в пикселях ИСХОДНОЙ картинки (imgW x imgH), поэтому
    при смене картинки/разрешения достаточно поправить таблицу CAMP ниже.
    Переключатель в консоли: hg_menu_camp 1/0 (0 - старое меню).
]]

local CAMP = {
    -- фон
    image  = "vgui/rem_camp_bg.png",
    imgW   = 1703,
    imgH   = 923,
    focusX = 812,   -- какую точку картинки держать по центру, если экран уже картинки
    alignY = 0.75,  -- 0 - прижать к верху, 1 - к низу, если экран шире картинки

    -- живой фон: слои с параллаксом (как в Casualties: Unknown).
    -- depth: 0 - не двигается, 1 - обычный слой, >1 - передний план (двигается сильнее)
    -- облака отдельным слоем: медленно плывут туда-обратно
    clouds = {mat = "vgui/rem_camp_clouds.png", depth = 0.05, amp = 90, period = 170},
    -- дождь иногда
    rain = {
        between  = {70, 220},  -- сек между дождями
        length   = {35, 90},   -- сек длится дождь
        start_chance = 0.25,   -- шанс, что дождь идёт уже при открытии меню
        ramp     = 6,          -- сек на усиление/ослабление
        drops    = 420,
        speed    = {1100, 1600}, -- пикс/сек при 1080p
        slant    = 0.18,       -- наклон (ветер)
        darken   = 70,         -- затемнение сцены при сильном дожде (0..255)
        sound    = {"sound/ambient/weather/rumble_rain_nowind.wav", "sound/ambient/weather/rumble_rain.wav"},
        volume   = 0.45,
        thunder  = {"ambient/weather/thunder1.wav", "ambient/weather/thunder2.wav", "ambient/weather/thunder3.wav", "ambient/weather/thunder4.wav"},
        flash_every = {12, 35},
    },
    layers = {
        {mat = "vgui/rem_camp_sky.png",  depth = 0.05, fallback = "vgui/rem_camp_far.png"}, -- небо и горы без облаков
        {mat = "vgui/rem_camp_near.png", depth = 1.0},  -- холм, дерево, вещи, аватар
        {mat = "vgui/rem_camp_lamp.png", depth = 1.0},  -- фонарь слева (в видео едет вместе с землёй)
    },
    parallax = {
        overscan    = 1.07, -- картинка чуть больше экрана, чтобы при сдвиге не было краёв
        edge_depth  = 1.0,  -- запас по краям считается для слоёв до этой глубины (фонарь у края может уезжать)
        mouse_x     = 42,   -- сдвиг слоя depth=1 от мышки (пикс. при 1080p), как в видео
        mouse_y     = 20,
        sway_x      = 4,    -- медленное "дыхание" камеры без мышки
        sway_y      = 3,
        sway_speed  = 0.35,
        breath      = 0.002, -- лёгкий зум туда-сюда
        breath_speed = 0.25,
        smooth      = 0.05, -- плавность следования за мышкой (меньше - плавнее)
    },
    fx = {
        lamp  = {x = 40,   y = 330, size = 420, color = Color(90, 140, 255)},
        moon  = {x = 1703, y = 55,  size = 300, color = Color(200, 200, 255)},
        warm  = {x = 715,  y = 430, size = 320, color = Color(255, 150, 70), alpha = 0.10},
        tablet = {
            red    = {x = 1040, y = 823},
            green  = {x = 1010, y = 808},
            screen = {x = 1060, y = 803},
            blink_period = 1.0, blink_on = 0.18, -- в видео: короткая вспышка раз в секунду
        },
        stars = {
        {158, 74},
        {214, 62},
        {521, 78},
        {390, 150},
        {178, 112},
        {1372, 185},
        {1422, 23},
        {1608, 345},
        {250, 6},
        {1349, 312},
        {1176, 183},
        {1507, 195},
        {1472, 317},
        {1415, 151},
        {1248, 149},
        {356, 67},
        {1147, 286},
        {989, 130},
        {1655, 67},
        {1590, 43},
        {1007, 215},
        {495, 197},
        {1036, 134},
        {1641, 182},
        {421, 87},
        {1685, 260},
        {475, 76},
        {1694, 312},
        {1254, 299},
        {1613, 288},
        {1119, 183},
        {979, 255},
        {440, 176},
        {1519, 314},
        {1092, 230},
        {78, 76},
        {1434, 353},
        {1424, 246},
        {238, 102},
        {494, 133},
        {966, 190},
        {1222, 212},
        {1325, 227},
        {1569, 264},
        {1292, 177}
        },
    },

    -- "exit": "disconnect" - как старая кнопка Disconnect (аватар уходит в мешок и выходит с сервера)
    --         "quit"       - закрыть игру целиком
    exitMode = "disconnect",

    -- аватар
    avatar = {
        -- прямоугольник, в который рисуется 3D-модель (координаты картинки)
        modelRect = {x = 458, y = 292, w = 506, h = 631},
        -- камера. Земля (z = 0) у ног модели, сидящий человек ~40 юнитов в высоту.
        -- Поднять/опустить модель в кадре: cam_z (больше -> модель ниже).
        -- Сделать крупнее/мельче: vfov (меньше -> крупнее).
        cam_dist  = 100,
        cam_z     = 19,
        cam_pitch = 0,
        vfov      = 28,
        fov_scale = 1.0,
        -- модель сидит спиной к камере; yaw 180 = ровно спиной, 0 = лицом
        entity_ang = Angle(0, 158, 0),
        -- поза "сидит на земле, ноги вытянуты вперёд":
        -- берётся анимация сидения (как в машине), колени выпрямляются,
        -- модель опускается так, чтобы таз и пятки стояли на земле
        sequences      = {"sit", "sit_passive", "sit_fist", "cidle_all"},
        knee_straighten = 78,   -- на сколько градусов разогнуть колени (0 - как на стуле)
        butt_offset     = 4,    -- насколько кость таза выше земли
        ground_extra    = 0,    -- доп. сдвиг модели вниз(+)/вверх(-) в юнитах
        -- камера для сцены ухода (модель в полный рост)
        exit_cam_z = 36,
        exit_vfov  = 70,
    },

    -- зоны (координаты картинки). labelSide: куда ставить подпись
    hotspots = {
        {
            id = "avatar", action = "continue",
            label = "CONTINUE",
            rect = {x = 569, y = 347, w = 292, h = 576},
            glow = Color(120, 170, 255), labelSide = "top",
        },
        {
            id = "skin", action = "appearance",
            label = "APPEARANCE", depth = 1.0,
            rect = {x = 0, y = 150, w = 110, h = 340},
            glow = Color(90, 140, 255), labelSide = "right",
        },
        {
            id = "player", action = "achievements", actionRMB = "credits",
            label = "ACHIEVEMENTS", hint = "RMB - CREDITS",
            rect = {x = 165, y = 500, w = 315, h = 140},
            glow = Color(150, 220, 255), labelSide = "top",
        },
        -- планшет стоит поверх угла мешка, поэтому он ДОЛЖЕН идти раньше "exit"
        {
            id = "settings", action = "settings",
            label = "SETTINGS",
            rect = {x = 965, y = 775, w = 170, h = 100},
            glow = Color(140, 200, 255), labelSide = "top",
        },
        {
            id = "exit", action = "exit",
            label = "EXIT",
            rect = {x = 945, y = 462, w = 665, h = 428},
            glow = Color(255, 170, 120), labelSide = "top",
        },
    },

    -- музыка (файлы в garrysmod/addons/<аддон>/sound/remorse/)
    music = {
        -- при каждом открытии меню выбирается один трек по весам
        menu = {
            {path = "sound/remorse/menu_proxynew.ogg",    weight = 60}, -- основная
            {path = "sound/remorse/menu_underground.ogg", weight = 20}, -- иногда попадается
            {path = "sound/remorse/menu_coldsong.ogg",    weight = 20}, -- Coldsong
        },
        settings = "sound/remorse/settings_landmines.ogg",
        credits  = "sound/remorse/credits_absolute.ogg",
        fallback = nil, -- старая музыка меню убрана
    },

    -- титры (ПКМ по плееру). {"текст", "big"/"head"/nil}; пустая строка = отступ
    credits = {
        speed = 55, -- пикселей в секунду при 1080p
        lines = {
            {"Z-SCAV", "big"},
            {""}, {""},
            {"BASED ON", "head"},
            {"Z-City - uzelezz123"},
            {"github.com/uzelezz123/Z-City"},
            {""},
            {"REMORSEISM (ОСНОВА)", "head"},
            {"github.com/kazoo43/remorseism"},
            {""},
            {"TEAM", "head"},
            {"впишите сюда команду"},
            {""},
            {"ART", "head"},
            {"впишите автора фона"},
            {""},
            {"USED ADDONS", "head"},
            {"Glide - StyledStrike"},
            {"vFire"},
            {"wOS DynaBase"},
            {""}, {""}, {""},
            {"THANK YOU FOR PLAYING", "head"},
        },
    },
}

hg.CampMenu = CAMP

-- ---------------------------------------------------------------------------
-- "ночной" фон для страниц меню (настройки, внешность, ачивки):
-- полупрозрачный тёмно-синий, сквозь него видна живая сцена лагеря.
-- Слева темнее (там текст/кнопки), снизу - лунный голубой отсвет.
-- ---------------------------------------------------------------------------
local nightGradL = surface.GetTextureID("vgui/gradient-l")
local nightGradR = surface.GetTextureID("vgui/gradient-r")
local nightGradU = surface.GetTextureID("vgui/gradient-u")
local nightGradD = surface.GetTextureID("vgui/gradient-d")

function hg.ZSCAVNightBG(panel, w, h, strength)
    strength = strength or 1
    if hg.DrawBlur then hg.DrawBlur(panel, 2 * strength) end
    surface.SetDrawColor(6, 10, 28, 105 * strength)
    surface.DrawRect(0, 0, w, h)
    -- левая колонка темнее, чтобы читался текст
    surface.SetDrawColor(5, 9, 24, 215 * strength)
    surface.SetTexture(nightGradR)
    surface.DrawTexturedRect(0, 0, w * 0.55, h)
    -- верх - ночное небо
    surface.SetDrawColor(4, 8, 22, 150 * strength)
    surface.SetTexture(nightGradD)
    surface.DrawTexturedRect(0, 0, w, h * 0.35)
    -- низ - холодный лунный отсвет
    surface.SetDrawColor(70, 105, 190, 45 * strength)
    surface.SetTexture(nightGradU)
    surface.DrawTexturedRect(0, h * 0.6, w, h * 0.4)
    -- правый край чуть темнее
    surface.SetDrawColor(4, 8, 22, 90 * strength)
    surface.SetTexture(nightGradL)
    surface.DrawTexturedRect(w * 0.8, 0, w * 0.2, h)
end

CreateClientConVar("hg_menu_camp", "1", true, false, "1 - camp main menu, 0 - classic main menu")

local SOUND_SELECT = "ui/rem_select.wav"
local SOUND_HOVER  = "ui/rem_hover.wav"

-- ---------------------------------------------------------------------------
-- Тишина мира в главном меню: птицы, ветер, шаги, стрельба и т.д. приглушаются.
-- Музыка меню (sound.PlayFile) и звуки интерфейса меню продолжают играть.
--
-- На многих серверах команда volume_sfx ЗАБЛОКИРОВАНА для Lua (ошибка
-- "RunConsoleCommand: Command is blocked! (volume_sfx)"), поэтому:
--   1) если volume_sfx разрешена - временно ставим её в 0 и потом возвращаем;
--   2) иначе - движковое затухание звуков "soundfade", повторяем его пока открыто меню
--      (после закрытия звуки сами плавно возвращаются через пару секунд);
--   3) если и это заблокировано - просто ничего не делаем (без ошибок).
-- Выключить: zscav_menu_mute 0
-- ---------------------------------------------------------------------------
local cvMenuMute = CreateClientConVar("zscav_menu_mute", "1", true, false, "Z-SCAV: глушить звуки мира в главном меню", 0, 1)
local worldMuted = false
local muteMode = nil
local nextFade = 0
local SFX_CVAR = "volume_sfx"

local function CanRun(cmd)
    if IsConCommandBlocked and IsConCommandBlocked(cmd) then return false end
    return true
end

local function SafeRun(cmd, ...)
    if not CanRun(cmd) then return false end
    return pcall(RunConsoleCommand, cmd, ...)
end

-- если игра закрылась прямо в меню - вернуть громкость при следующем запуске
do
    local saved = cookie.GetNumber("zscav_sfx_restore", -1)
    if saved >= 0 then
        if ConVarExists(SFX_CVAR) then SafeRun(SFX_CVAR, tostring(saved)) end
        cookie.Delete("zscav_sfx_restore")
    end
end

local function MuteWorld(on)
    if on == worldMuted then return end
    if on and not cvMenuMute:GetBool() then return end
    worldMuted = on
    if on then
        if ConVarExists(SFX_CVAR) and CanRun(SFX_CVAR) then
            muteMode = "sfx"
            cookie.Set("zscav_sfx_restore", tostring(GetConVar(SFX_CVAR):GetFloat()))
            SafeRun(SFX_CVAR, "0")
        elseif CanRun("soundfade") then
            muteMode = "fade"
            nextFade = 0
        else
            muteMode = nil
        end
    else
        if muteMode == "sfx" then
            local saved = cookie.GetNumber("zscav_sfx_restore", 1)
            if saved <= 0 then saved = 1 end -- не возвращаем "ноль" по ошибке
            SafeRun(SFX_CVAR, tostring(saved))
            cookie.Delete("zscav_sfx_restore")
        end
        -- режим "fade" возвращается сам: просто перестаём продлевать затухание
        muteMode = nil
    end
end
hg.ZSCAVMenuMuteWorld = MuteWorld

hook.Add("Think", "ZSCAV_MenuMuteGuard", function()
    -- страховка: меню пропало любым способом - громкость возвращаем
    if worldMuted and not (IsValid(MainMenu) and MainMenu.ClassName == "ZCampMenu") then
        MuteWorld(false)
        return
    end
    -- режим затухания: продлеваем, пока открыто меню
    if worldMuted and muteMode == "fade" and RealTime() >= nextFade then
        nextFade = RealTime() + 1
        -- soundfade <процент глушения> <держать сек> <затухание сек> <возврат сек>
        if not SafeRun("soundfade", "100", "2", "0.4", "1.5") then muteMode = nil end
    end
end)

-- звуки интерфейса меню - через BASS, чтобы их не глушила тишина мира
local function UISound(path)
    if not worldMuted then surface.PlaySound(path) return end
    sound.PlayFile("sound/" .. path, "noplay", function(st)
        if IsValid(st) then st:SetVolume(0.8) st:Play() end
    end)
end

local bgMat   = Material(CAMP.image, "smooth")
local layerMats = {}
for i, layer in ipairs(CAMP.layers or {}) do
    layerMats[i] = Material(layer.mat, "smooth")
    if layer.fallback and layerMats[i]:IsError() then layerMats[i] = Material(layer.fallback, "smooth") end
end
local cloudMat = CAMP.clouds and Material(CAMP.clouds.mat, "smooth")
-- облака имеют смысл только поверх "чистого" неба
local cloudsOK = cloudMat and not cloudMat:IsError() and not Material(CAMP.layers[1].mat, "smooth"):IsError()
local function LayersOK()
    if #layerMats == 0 then return false end
    for _, m in ipairs(layerMats) do
        if not m or m:IsError() then return false end
    end
    return true
end
local glowMat = Material("sprites/light_glow02_add")
local gradD   = surface.GetTextureID("vgui/gradient-d")

local function CreateCampFonts()
    surface.CreateFont("ZCamp_Label", {
        font = "Verily Serif Mono",
        size = ScreenScale(16),
        weight = 600,
        antialias = true,
    })
    surface.CreateFont("ZCamp_Hint", {
        font = "Verily Serif Mono",
        size = ScreenScale(7),
        weight = 400,
        antialias = true,
    })
    surface.CreateFont("ZCamp_CredBig", {
        font = "Verily Serif Mono",
        size = ScreenScale(30),
        weight = 800,
        antialias = true,
    })
    surface.CreateFont("ZCamp_CredHead", {
        font = "Verily Serif Mono",
        size = ScreenScale(9),
        weight = 600,
        antialias = true,
    })
    surface.CreateFont("ZCamp_Cred", {
        font = "Verily Serif Mono",
        size = ScreenScale(13),
        weight = 400,
        antialias = true,
    })
    surface.CreateFont("ZCamp_Back", {
        font = "Verily Serif Mono",
        size = ScreenScale(12),
        weight = 600,
        antialias = true,
    })
end
CreateCampFonts()
hook.Add("OnScreenSizeChanged", "ZCamp_Fonts", CreateCampFonts)

-- ---------------------------------------------------------------------------
-- раскладка: картинка -> экран (режим "cover" без искажений)
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- музыка
-- ---------------------------------------------------------------------------
local function MusicPath(path)
    local M = CAMP.music or {}
    if path and file.Exists(path, "GAME") then return path end
    return M.fallback
end

local function PickMenuTrack()
    local list, total = {}, 0
    for _, tr in ipairs((CAMP.music or {}).menu or {}) do
        if file.Exists(tr.path, "GAME") then
            list[#list + 1] = tr
            total = total + (tr.weight or 1)
        end
    end
    if total <= 0 then return MusicPath(nil) end
    local roll = math.Rand(0, total)
    for _, tr in ipairs(list) do
        roll = roll - (tr.weight or 1)
        if roll <= 0 then return tr.path end
    end
    return list[#list].path
end

local function CampLayout()
    local sw, sh = ScrW(), ScrH()
    local P = CAMP.parallax or {}
    local scale = math.max(sw / CAMP.imgW, sh / CAMP.imgH) * (P.overscan or 1)
    local vw, vh = sw / scale, sh / scale

    -- запас по краям под максимальный сдвиг самого "ближнего" слоя
    local maxDepth = P.edge_depth or 1
    local k = sh / 1080
    local mX = ((P.mouse_x or 0) + (P.sway_x or 0)) * k * maxDepth / scale
    local mY = ((P.mouse_y or 0) + (P.sway_y or 0)) * k * maxDepth / scale

    local spareX, spareY = CAMP.imgW - vw, CAMP.imgH - vh
    local ox = spareX > mX * 2 and math.Clamp(CAMP.focusX - vw * 0.5, mX, spareX - mX) or spareX * 0.5
    local oy = spareY > mY * 2 and math.Clamp(spareY * CAMP.alignY, mY, spareY - mY) or spareY * 0.5

    return {sw = sw, sh = sh, scale = scale, vw = vw, vh = vh, ox = ox, oy = oy,
            camX = 0, camY = 0, zoom = 1}
end

-- координаты картинки -> экран, с учётом сдвига камеры для слоя глубины depth
local function MapRect(L, r, depth)
    depth = depth or 1
    local z = 1 + ((L.zoom or 1) - 1) * depth
    local cx, cy = L.sw * 0.5, L.sh * 0.5
    local x = ((r.x - L.ox) * L.scale - cx) * z + cx + (L.camX or 0) * depth
    local y = ((r.y - L.oy) * L.scale - cy) * z + cy + (L.camY or 0) * depth
    return math.floor(x), math.floor(y), math.ceil(r.w * L.scale * z), math.ceil(r.h * L.scale * z)
end

local function VFovToFov(vfov, aspect)
    return math.deg(2 * math.atan(math.tan(math.rad(vfov * 0.5)) * aspect))
end

-- ---------------------------------------------------------------------------
-- панель
-- ---------------------------------------------------------------------------
local PANEL = {}

-- Таблица старого меню. От него НЕ наследуемся через vgui (иначе GMod вызовет его Init
-- и построит старое меню поверх нового), а копируем только нужные методы.
local ZMainMenuTbl = vgui.GetControlTable("ZMainMenu")

function PANEL:Init()
    self:SetAlpha(0)
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:SetTitle("")
    self:SetDraggable(false)
    self:SetBorder(false)
    self:ShowCloseButton(false)

    -- поля, которые читает базовый ZMainMenu
    self.LiveLerp = 0
    self.LogoHoverLerp = 0
    self.DisconnectCutscene = false
    self.DisconnectBackgroundAlpha = 255
    self.DisconnectBlackAlpha = 0

    self.UIFade = 1     -- видимость подписей/маркеров
    self.SubFade = 0    -- затемнение сцены под подменю
    self.Hot = nil
    self.HotLerp = {}
    self.InSubmenu = nil

    self.Layout = CampLayout()
    self.MenuTrack = PickMenuTrack()
    self:UseDefaultMenuMusic()
    MuteWorld(true)

    -- панель для подменю (настройки / внешность)
    self.panelparrent = vgui.Create("DPanel", self)
    self.panelparrent:SetPos(0, 0)
    self.panelparrent:SetSize(ScrW(), ScrH())
    self.panelparrent.Paint = function() end
    self.panelparrent:SetMouseInputEnabled(false)

    -- аватар = preview-model старого меню, только в нашем прямоугольнике
    local ar = CAMP.avatar.modelRect
    local x, y, w, h = MapRect(self.Layout, ar)
    self.PreviewRect = {x = x, y = y, w = w, h = h}
    self:CreateAppearancePreview()
    self:ApplyCampPreview()

    timer.Simple(0, function()
        if IsValid(self) then self:First() end
    end)
end

function PANEL:First()
    self:AlphaTo(255, 0.35, 0)
end

-- камера/поза/угол аватара
function PANEL:ApplyCampPreview()
    local pm = self.previewModel
    local holder = self.previewHolder
    if not IsValid(pm) or not IsValid(holder) then return end

    local prev = self.Layout
    self.Layout = CampLayout()
    if prev then -- не дёргаем камеру при возврате из подменю
        self.Layout.camX, self.Layout.camY, self.Layout.zoom = prev.camX, prev.camY, prev.zoom
    end
    local x, y, w, h = MapRect(self.Layout, CAMP.avatar.modelRect)
    holder:Stop() -- гасим MoveTo, который оставляет редактор внешности
    holder:SetSize(w, h)
    holder:SetPos(x, y)
    holder.TargetX, holder.TargetY = x, y
    holder.AppearanceFollow = false

    local a = CAMP.avatar
    pm.CamPosOverride      = Vector(a.cam_dist, 0, a.cam_z)
    pm.LookAngOverride     = Angle(a.cam_pitch, 180, 0)
    pm.FOVOverride         = VFovToFov(a.vfov, w / math.max(h, 1)) * a.fov_scale
    pm.EntityAngleOverride = a.entity_ang
    pm.SequenceNameOverride = nil
    pm.SequencePlaybackRate = nil
    pm.ActiveSequenceName   = nil
    self.SeqModel = nil
    self:InstallSitPose()
end

-- подбираем "сидячую" анимацию, которая реально есть у текущей модели
function PANEL:PickSitSequence()
    local pm = self.previewModel
    if not IsValid(pm) or not IsValid(pm.Entity) then return end
    local mdl = pm.Entity:GetModel()
    if self.SeqModel == mdl then return end
    self.SeqModel = mdl
    pm.SequenceNameOverride = nil
    for _, name in ipairs(CAMP.avatar.sequences) do
        if pm.Entity:LookupSequence(name) >= 0 then
            pm.SequenceNameOverride = name
            break
        end
    end
    pm.ActiveSequenceName = nil
end

-- ---------------------------------------------------------------------------
-- поза "на земле, ноги вперёд"
-- ---------------------------------------------------------------------------
local LEG_BONES = {
    "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf",
}

local function BonePos(ent, name)
    local id = ent:LookupBone(name)
    if not id then return end
    local m = ent:GetBoneMatrix(id)
    return m and m:GetTranslation()
end

local function SetLegAngles(ent, ang)
    for _, name in ipairs(LEG_BONES) do
        local id = ent:LookupBone(name)
        if id then ent:ManipulateBoneAngles(id, ang or angle_zero) end
    end
end

local function RefreshBones(ent)
    ent:InvalidateBoneCache()
    ent:SetupBones()
end

-- оси костей у разных моделей могут отличаться, поэтому ось сгиба колена
-- подбираем на месте: пробуем 6 вариантов и берём тот, где стопы
-- ушли дальше всего вперёд и ближе всего к высоте таза
local function CalibrateSit(ent)
    local a = CAMP.avatar
    local amt = a.knee_straighten or 0
    local candidates = {angle_zero}
    if amt ~= 0 then
        candidates = {
            Angle(amt, 0, 0), Angle(-amt, 0, 0),
            Angle(0, amt, 0), Angle(0, -amt, 0),
            Angle(0, 0, amt), Angle(0, 0, -amt),
        }
    end

    local best, bestScore
    for _, ang in ipairs(candidates) do
        SetLegAngles(ent, ang)
        RefreshBones(ent)
        local pelvis = BonePos(ent, "ValveBiped.Bip01_Pelvis")
        local lf = BonePos(ent, "ValveBiped.Bip01_L_Foot")
        local rf = BonePos(ent, "ValveBiped.Bip01_R_Foot")
        if pelvis and lf and rf then
            local foot = (lf + rf) * 0.5
            local flat = Vector(foot.x - pelvis.x, foot.y - pelvis.y, 0):Length()
            local score = flat - math.abs(foot.z - pelvis.z) * 1.5
            if not bestScore or score > bestScore then
                best, bestScore = ang, score
            end
        end
    end
    best = best or angle_zero

    SetLegAngles(ent, best)
    RefreshBones(ent)

    -- насколько опустить модель, чтобы таз и пятки легли на землю (z = 0)
    local base = ent:GetPos().z
    local lowest
    local pelvis = BonePos(ent, "ValveBiped.Bip01_Pelvis")
    if pelvis then lowest = pelvis.z - (a.butt_offset or 4) end
    for _, name in ipairs({"ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot", "ValveBiped.Bip01_L_Toe0", "ValveBiped.Bip01_R_Toe0"}) do
        local p = BonePos(ent, name)
        if p then lowest = math.min(lowest or p.z, p.z - 1.5) end
    end

    return {ang = best, drop = (lowest or base) - base + (a.ground_extra or 0)}
end

function PANEL:IsSitting()
    return not self.InSubmenu and not self.DisconnectCutscene and not self.QuitStart
end

-- оборачиваем LayoutEntity базового превью: сначала оно делает своё
-- (модель, одежда, анимация, голова за мышкой), потом мы сажаем модель
function PANEL:InstallSitPose()
    local pm = self.previewModel
    if not IsValid(pm) or pm.CampSitInstalled then return end
    pm.CampSitInstalled = true
    pm.CampCalib = {}

    local menu = self
    local origLayout = pm.LayoutEntity
    pm.LayoutEntity = function(this, ent)
        origLayout(this, ent)
        if not IsValid(ent) then return end

        local sitting = IsValid(menu) and menu:IsSitting()
            and this.SequenceNameOverride ~= nil
            and this.ActiveSequenceName == this.SequenceNameOverride

        if not sitting then
            if this.CampPosed then
                SetLegAngles(ent, angle_zero)
                this.CampPosed = false
            end
            return
        end

        local key = ent:GetModel() .. "|" .. tostring(this.SequenceNameOverride)
        local calib = this.CampCalib[key]
        if not calib then
            calib = CalibrateSit(ent)
            this.CampCalib[key] = calib
        elseif not this.CampPosed then
            SetLegAngles(ent, calib.ang)
        end
        this.CampPosed = true
        ent:SetPos(ent:GetPos() - Vector(0, 0, calib.drop))
    end
end

function PANEL:GetHotspotAt(mx, my)
    for _, hs in ipairs(CAMP.hotspots) do
        local x, y, w, h = MapRect(self.Layout, hs.rect, hs.depth)
        if mx >= x and mx <= x + w and my >= y and my <= y + h then
            return hs, x, y, w, h
        end
    end
end

-- камера: мышка + медленное покачивание + "дыхание" зумом;
-- аватар едет вместе со своим слоем
function PANEL:UpdateCamera()
    local L, P = self.Layout, CAMP.parallax or {}
    local mx, my = gui.MouseX(), gui.MouseY()
    if mx <= 0 and my <= 0 then mx, my = ScrW() * 0.5, ScrH() * 0.5 end
    local nx = math.Clamp((mx / ScrW() - 0.5) * 2, -1, 1)
    local ny = math.Clamp((my / ScrH() - 0.5) * 2, -1, 1)
    local k, t = ScrH() / 1080, RealTime()
    local sp = P.sway_speed or 0.35

    local tx = -nx * (P.mouse_x or 0) * k + math.sin(t * sp) * (P.sway_x or 0) * k
    local ty = -ny * (P.mouse_y or 0) * k + math.sin(t * sp * 1.37 + 1.3) * (P.sway_y or 0) * k
    L.camX = LerpFT(P.smooth or 0.06, L.camX or 0, tx)
    L.camY = LerpFT(P.smooth or 0.06, L.camY or 0, ty)
    L.zoom = 1 + math.sin(t * (P.breath_speed or 0.25)) * (P.breath or 0)

    local holder = self.previewHolder
    if IsValid(holder) and self.InSubmenu ~= "appearance" then
        local x, y, w, h = MapRect(L, CAMP.avatar.modelRect, 1)
        holder:SetPos(x, y)
        local cw, ch = holder:GetSize()
        if math.abs(cw - w) > 1 or math.abs(ch - h) > 1 then holder:SetSize(w, h) end
    end
end

-- ---------------------------------------------------------------------------
-- дождь
-- ---------------------------------------------------------------------------
function PANEL:RainInit()
    local R = CAMP.rain
    self.RainK = 0
    if math.Rand(0, 1) < R.start_chance then
        self.RainOn, self.RainEnd = true, RealTime() + math.Rand(R.length[1], R.length[2])
        self.RainK = 1
    else
        self.RainOn, self.RainNext = false, RealTime() + math.Rand(R.between[1], R.between[2])
    end
    self.Drops = {}
    for i = 1, R.drops do
        self.Drops[i] = {x = math.Rand(0, 1), y = math.Rand(0, 1), s = math.Rand(R.speed[1], R.speed[2]), l = math.Rand(14, 30)}
    end
end

function PANEL:RainThink()
    local R = CAMP.rain
    if not R then return end
    if self.RainK == nil then self:RainInit() end
    local now, dt = RealTime(), RealFrameTime()
    if self.RainOn and now >= self.RainEnd then
        self.RainOn, self.RainNext = false, now + math.Rand(R.between[1], R.between[2])
    elseif not self.RainOn and now >= (self.RainNext or 0) then
        self.RainOn, self.RainEnd = true, now + math.Rand(R.length[1], R.length[2])
    end
    self.RainK = math.Approach(self.RainK, self.RainOn and 1 or 0, dt / R.ramp)

    -- капли
    local h = ScrH()
    for _, d in ipairs(self.Drops) do
        d.y = d.y + d.s * (h / 1080) * dt / h
        d.x = d.x + d.s * R.slant * (h / 1080) * dt / ScrW()
        if d.y > 1.05 then d.y = d.y - 1.1 d.x = math.Rand(-0.1, 1) end
        if d.x > 1.05 then d.x = d.x - 1.1 end
    end

    -- звук дождя (через BASS - его не глушит тишина мира в меню)
    local target = R.volume * self.RainK
    if target > 0.01 then
        if not IsValid(self.RainSnd) and not self.RainSndLoading then
            local path
            for _, p in ipairs(R.sound) do if file.Exists(p, "GAME") then path = p break end end
            if path then
                self.RainSndLoading = true
                sound.PlayFile(path, "noplay", function(st)
                    if not IsValid(self) then if IsValid(st) then st:Stop() end return end
                    self.RainSndLoading = false
                    if not IsValid(st) then return end
                    self.RainSnd = st
                    st:EnableLooping(true)
                    st:SetVolume(0)
                    st:Play()
                end)
            end
        end
        if IsValid(self.RainSnd) then self.RainSnd:SetVolume(target) end
    elseif IsValid(self.RainSnd) then
        self.RainSnd:Stop()
        self.RainSnd = nil
    end

    -- молнии и гром в сильный дождь
    if self.RainK > 0.7 and now >= (self.NextFlash or 0) then
        self.NextFlash = now + math.Rand(R.flash_every[1], R.flash_every[2])
        if (self.FlashT or 0) > 0 or math.random() < 0.8 then
            self.FlashT = now
            local snd = R.thunder[math.random(#R.thunder)]
            timer.Simple(math.Rand(0.4, 2.2), function()
                if IsValid(self) and file.Exists("sound/" .. snd, "GAME") then
                    sound.PlayFile("sound/" .. snd, "noplay", function(st) if IsValid(st) then st:SetVolume(0.6) st:Play() end end)
                end
            end)
        end
    end
end

function PANEL:DrawRain(w, h)
    local k = self.RainK or 0
    if k <= 0.01 then return end
    if self.InSubmenu and self.InSubmenu ~= "credits" then return end -- не поверх настроек/гардероба
    local R = CAMP.rain
    -- сцена темнеет и синеет
    surface.SetDrawColor(10, 16, 34, R.darken * k)
    surface.DrawRect(0, 0, w, h)
    -- вспышка молнии
    if self.FlashT then
        local f = RealTime() - self.FlashT
        local a = (f < 0.08 and 1 or (f < 0.18 and 0.3 or (f < 0.26 and 0.8 or math.max(0, 1 - (f - 0.26) / 0.6)))) * k
        if a > 0.01 then
            surface.SetDrawColor(200, 210, 255, 120 * a)
            surface.DrawRect(0, 0, w, h)
        end
    end
    -- капли
    local n = math.floor(#self.Drops * k)
    local sl = R.slant
    for i = 1, n do
        local d = self.Drops[i]
        local x, y = d.x * w, d.y * h
        local len = d.l * (h / 1080)
        surface.SetDrawColor(170, 185, 230, (40 + (i % 5) * 18) * k)
        surface.DrawLine(x, y, x - len * sl, y - len)
    end
end

function PANEL:Think()
    -- музыка, сцена ухода, анимации базового меню
    if ZMainMenuTbl and ZMainMenuTbl.Think then ZMainMenuTbl.Think(self) end

    if ScrW() ~= self.Layout.sw or ScrH() ~= self.Layout.sh then
        self:SetSize(ScrW(), ScrH())
        self.Layout = CampLayout()
        self:ApplyCampPreview()
    end

    self:UpdateCamera()
    self:RainThink()

    local busy = self.InSubmenu or self.DisconnectCutscene or self.QuitStart
    if not busy then self:PickSitSequence() end

    -- что под курсором
    local hot
    if not busy and self:GetAlpha() > 200 then
        hot = self:GetHotspotAt(gui.MouseX(), gui.MouseY())
    end
    if hot ~= self.Hot then
        if hot then UISound(SOUND_HOVER) end
        self.Hot = hot
    end
    self:SetCursor(hot and "hand" or "arrow")

    for _, hs in ipairs(CAMP.hotspots) do
        self.HotLerp[hs.id] = LerpFT(0.18, self.HotLerp[hs.id] or 0, (hot == hs) and 1 or 0)
    end

    self.UIFade  = LerpFT(0.2, self.UIFade, busy and 0 or 1)
    self.SubFade = LerpFT(0.15, self.SubFade, self.InSubmenu and 1 or 0)

    if self.QuitStart then
        local f = math.Clamp((CurTime() - self.QuitStart) / 0.7, 0, 1)
        self.DisconnectBlackAlpha = 255 * f
    end
end

-- ---------------------------------------------------------------------------
-- рисование
-- ---------------------------------------------------------------------------
local function DrawGlow(cx, cy, w, h, col, a)
    if a <= 0.01 then return end
    surface.SetMaterial(glowMat)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * a)
    surface.DrawTexturedRect(cx - w * 0.5, cy - h * 0.5, w, h)
end

-- спрайт свечения с центром в точке картинки (ix, iy) на слое depth
local function GlowAt(L, ix, iy, depth, size, col, a)
    if a <= 0.005 then return end
    local x, y, sz = MapRect(L, {x = ix, y = iy, w = size, h = size}, depth)
    DrawGlow(x, y, sz, sz, col, math.min(a, 1))
end

local function DrawLayer(L, mat, depth, shiftX)
    local x, y, w, h = MapRect(L, {x = shiftX or 0, y = 0, w = CAMP.imgW, h = CAMP.imgH}, depth)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(mat)
    surface.DrawTexturedRect(x, y, w, h)
end

local function LayerDepth(i)
    return CAMP.layers[i] and CAMP.layers[i].depth or 1
end

function PANEL:DrawFarFX(L, t)
    local fx, d = CAMP.fx, LayerDepth(1)
    -- звёзды мерцают
    for i, st in ipairs(fx.stars or {}) do
        local tw = math.max(0, math.sin(t * (0.6 + (i % 7) * 0.17) + i * 1.93))
        GlowAt(L, st[1], st[2], d, 10 + (i % 3) * 4, color_white, tw * tw * tw * 0.85)
    end
    -- луна чуть дышит
    local m = fx.moon
    if m then GlowAt(L, m.x, m.y, d, m.size, m.color, 0.22 + 0.05 * math.sin(t * 0.7)) end
end

function PANEL:DrawNearFX(L, t)
    local fx, d = CAMP.fx, LayerDepth(2)
    -- тёплый свет у аватара
    local wm = fx.warm
    if wm then GlowAt(L, wm.x, wm.y, d, wm.size, wm.color, (wm.alpha or 0.1) * (0.85 + 0.15 * math.sin(t * 2.1))) end

    -- планшет: красная лампочка мигает и подсвечивает землю
    local tb = fx.tablet
    if tb then
        local on = (t % tb.blink_period) < tb.blink_on
        if on then
            local fade = math.sin(((t % tb.blink_period) / tb.blink_on) * math.pi)
            GlowAt(L, tb.red.x, tb.red.y + 20, d, 280, Color(220, 30, 30), 0.35 * fade)
            GlowAt(L, tb.red.x, tb.red.y, d, 36, Color(255, 60, 60), 0.95 * fade)
        end
        GlowAt(L, tb.green.x, tb.green.y, d, 26, Color(90, 255, 120), 0.25 + 0.05 * math.sin(t * 3))
        GlowAt(L, tb.screen.x, tb.screen.y, d, 110, Color(120, 200, 255), 0.10 + 0.04 * math.sin(t * 11) * math.sin(t * 2.3))
    end
end

function PANEL:DrawLampFX(L, t)
    local lp = CAMP.fx.lamp
    if not lp then return end
    -- как в видео: медленное неровное "дыхание" яркости (~2-3 сек), без быстрого мерцания
    local pulse = 0.13 * math.sin(t * 2.3) + 0.06 * math.sin(t * 1.07 + 1.3)
    GlowAt(L, lp.x, lp.y, LayerDepth(3), lp.size, lp.color, 0.40 + pulse)
end

function PANEL:Paint(w, h)
    local L = self.Layout
    local t = RealTime()

    if LayersOK() then
        DrawLayer(L, layerMats[1], LayerDepth(1))
        self:DrawFarFX(L, t)
        if cloudsOK then
            local c = CAMP.clouds
            local drift = math.sin(t * 2 * math.pi / c.period) * c.amp + math.sin(t * 2 * math.pi / (c.period * 2.7) + 1.3) * c.amp * 0.35
            -- в дождь облака темнеют
            local r = self.RainK or 0
            local v = 255 - 90 * r
            surface.SetDrawColor(v, v, v + 10 * r, 255)
            surface.SetMaterial(cloudMat)
            local x, y, w2, h2 = MapRect(L, {x = drift, y = 0, w = CAMP.imgW, h = CAMP.imgH}, c.depth)
            surface.DrawTexturedRect(x, y, w2, h2)
        end
        for i = 2, #layerMats do
            DrawLayer(L, layerMats[i], LayerDepth(i))
            if i == 2 then self:DrawNearFX(L, t) end
            if i == 3 then self:DrawLampFX(L, t) end
        end
    elseif bgMat and not bgMat:IsError() then
        -- нет слоёв - старый плоский фон, но тоже с параллаксом
        DrawLayer(L, bgMat, 1)
    else
        -- картинка не найдена: тёмный градиент, чтобы меню оставалось рабочим
        surface.SetDrawColor(18, 16, 40, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(60, 50, 120, 255)
        surface.SetTexture(gradD)
        surface.DrawTexturedRect(0, 0, w, h)
        draw.SimpleText("materials/vgui/rem_camp_*.png not found", "ZCamp_Hint", w * 0.5, h - 24,
            Color(200, 200, 200, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    -- мягкая подсветка зон (рисуется под моделью аватара)
    for _, hs in ipairs(CAMP.hotspots) do
        local x, y, rw, rh = MapRect(L, hs.rect, hs.depth)
        local lerp = self.HotLerp[hs.id] or 0
        local idle = (0.5 + 0.5 * math.sin(t * 1.7 + hs.rect.x * 0.01)) * 0.10
        DrawGlow(x + rw * 0.5, y + rh * 0.5, rw * 1.9, rh * 1.5, hs.glow, (idle + lerp * 0.45) * self.UIFade + lerp * 0.2)
    end

    -- виньетка
    surface.SetDrawColor(0, 0, 0, 90)
    surface.SetTexture(gradD)
    surface.DrawTexturedRect(0, h * 0.55, w, h * 0.45)

    if self.SubFade > 0.01 then
        -- ночь остаётся видна: только лёгкое затемнение (титрам - чуть сильнее)
        local a = self.InSubmenu == "credits" and 150 or 45
        surface.SetDrawColor(6, 10, 26, a * self.SubFade)
        surface.DrawRect(0, 0, w, h)
    end
end

function PANEL:PaintOver(w, h)
    self:DrawRain(w, h)
    local L = self.Layout

    for _, hs in ipairs(CAMP.hotspots) do
        local x, y, rw, rh = MapRect(L, hs.rect, hs.depth)
        local lerp = self.HotLerp[hs.id] or 0
        local a = self.UIFade

        if a > 0.02 then
            -- маркер-подсказка, пока курсор не наведён
            if lerp < 0.98 and hs.id ~= "avatar" then
                local mx, my = x + rw * 0.5, y + rh * 0.5
                if hs.id == "exit" then my = y + rh * 0.35 end
                local pulse = 0.5 + 0.5 * math.sin(CurTime() * 2.4 + x)
                surface.DrawCircle(mx, my, ScreenScale(2) + pulse * ScreenScale(1.5), 255, 255, 255, 120 * a * (1 - lerp))
            end

            if lerp > 0.02 then
                local flash = 0.5 + 0.5 * math.sin(CurTime() * 10)
                local col = Color(170 + flash * 60, 200 + flash * 45, 255, 255 * lerp * a) -- голубые подписи
                local out = Color(0, 0, 0, 255 * lerp * a)

                local tx, ty, ax, ay
                if hs.labelSide == "right" then
                    tx, ty = x + rw + ScreenScale(6), y + rh * 0.5
                    ax, ay = TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
                else
                    tx, ty = x + rw * 0.5, y - ScreenScale(4) - (1 - lerp) * ScreenScale(6)
                    if hs.id == "exit" then ty = y + rh * 0.12 end
                    ax, ay = TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM
                end

                draw.SimpleTextOutlined(hs.label, "ZCamp_Label", tx, ty, col, ax, ay, 1, out)
                if hs.hint then
                    draw.SimpleTextOutlined(hs.hint, "ZCamp_Hint", tx, ty + (ay == TEXT_ALIGN_BOTTOM and ScreenScale(2) or ScreenScale(12)),
                        Color(210, 210, 210, 200 * lerp * a), ax, TEXT_ALIGN_TOP, 1, out)
                end
            end
        end
    end

    if (self.DisconnectBlackAlpha or 0) > 0 then
        surface.SetDrawColor(0, 0, 0, self.DisconnectBlackAlpha)
        surface.DrawRect(0, 0, w, h)
    end
end

-- ---------------------------------------------------------------------------
-- действия
-- ---------------------------------------------------------------------------
function PANEL:OnMousePressed(code)
    if self.DisconnectCutscene or self.QuitStart or self.InSubmenu then return end
    if self:GetAlpha() < 200 then return end

    local hs = self:GetHotspotAt(gui.MouseX(), gui.MouseY())
    if not hs then return end

    if code == MOUSE_LEFT then
        UISound(SOUND_SELECT)
        if hs.action == "continue" then
            self:Close()
        elseif hs.action == "settings" then
            self:OpenSettings()
        elseif hs.action == "appearance" then
            self:OpenAppearance()
        elseif hs.action == "achievements" then
            self:OpenAchievements()
        elseif hs.action == "credits" then
            self:OpenCredits()
        elseif hs.action == "exit" then
            self:ExitGame()
        end
    elseif code == MOUSE_RIGHT and hs.actionRMB then
        UISound(SOUND_SELECT)
        if hs.actionRMB == "credits" then
            self:OpenCredits()
        elseif hs.actionRMB == "achievements" then
            self:OpenAchievements()
        end
    end
end

function PANEL:ClearSubPanel()
    if IsValid(self.panelparrent) then self.panelparrent:Remove() end
    self.panelparrent = vgui.Create("DPanel", self)
    self.panelparrent:SetPos(0, 0)
    self.panelparrent:SetSize(ScrW(), ScrH())
    self.panelparrent.Paint = function() end
    self.panelparrent:MoveToFront()
    return self.panelparrent
end

-- общая обёртка: прячем аватар, открываем страницу старого меню, даём кнопку BACK
function PANEL:OpenPage(kind, drawFunc)
    if self.InSubmenu then return end
    self.InSubmenu = kind

    if IsValid(self.previewHolder) then
        self.previewHolder:AlphaTo(0, 0.2, 0, function()
            if IsValid(self.previewHolder) and self.InSubmenu == kind then
                self.previewHolder:SetVisible(false)
            end
        end)
    end

    local pp = self:ClearSubPanel()
    if drawFunc then drawFunc(pp) end
    self:CreateBackButton(pp)
    return pp
end

function PANEL:OpenSettings()
    if self:OpenPage("settings", hg.DrawSettings) then
        self:SetMenuMusic(MusicPath(CAMP.music.settings))
    end
end

-- "обычная" музыка меню = трек, выбранный при открытии (вызывает и редактор внешности)
function PANEL:UseDefaultMenuMusic()
    self.MenuTrack = self.MenuTrack or PickMenuTrack()
    self:SetMenuMusic(self.MenuTrack)
end

function PANEL:OpenAchievements()
    self:OpenPage("achievements", hg.DrawAchievmentsMenu)
end

-- титры: текст едет снизу вверх поверх затемнённой сцены
function PANEL:OpenCredits()
    local menu = self
    local pp = self:OpenPage("credits")
    if not IsValid(pp) then return end
    self:SetMenuMusic(MusicPath(CAMP.music.credits))

    local cfg = CAMP.credits
    local startTime = RealTime()
    local fonts = {big = "ZCamp_CredBig", head = "ZCamp_CredHead"}
    local headColor = Color(130, 175, 255)

    local roll = vgui.Create("DPanel", pp)
    roll:SetPos(0, 0)
    roll:SetSize(ScrW(), ScrH())
    roll:SetCursor("hand")
    roll:MoveToBack()

    -- полная высота блока титров
    local function TotalHeight()
        local hgt = 0
        for _, ln in ipairs(cfg.lines) do
            surface.SetFont(fonts[ln[2]] or "ZCamp_Cred")
            local _, th = surface.GetTextSize(ln[1] ~= "" and ln[1] or "A")
            hgt = hgt + th * 1.35
        end
        return hgt
    end

    roll.Paint = function(this, w, h)
        local speed = (cfg.speed or 55) * (h / 1080)
        local y = h - (RealTime() - startTime) * speed
        local total = TotalHeight()

        for _, ln in ipairs(cfg.lines) do
            local font = fonts[ln[2]] or "ZCamp_Cred"
            surface.SetFont(font)
            local _, th = surface.GetTextSize(ln[1] ~= "" and ln[1] or "A")
            if ln[1] ~= "" and y > -th and y < h then
                -- затухание у краёв экрана
                local edge = math.min(y, h - y) / (h * 0.15)
                local a = math.Clamp(edge, 0, 1) * 255
                local col = ln[2] == "head" and headColor or Color(210, 225, 255)
                draw.SimpleTextOutlined(ln[1], font, w * 0.5, y, Color(col.r, col.g, col.b, a),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, a))
            end
            y = y + th * 1.35
        end

        draw.SimpleText("LMB / ESC - BACK", "ZCamp_Hint", w * 0.5, h - ScreenScale(6),
            Color(200, 200, 200, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

        -- титры доехали до конца - возвращаемся в сцену
        if y < 0 and not this.Done then
            this.Done = true
            timer.Simple(0.5, function()
                if IsValid(menu) and menu.InSubmenu == "credits" then menu:CloseSubmenu() end
            end)
        end
    end
    roll.OnMousePressed = function()
        if IsValid(menu) and menu.InSubmenu == "credits" then
            UISound(SOUND_SELECT)
            menu:CloseSubmenu()
        end
    end
end

function PANEL:OpenAppearance()
    if self.InSubmenu then return end
    self.InSubmenu = "appearance"
    self.SeqModel = nil

    -- редактор рассчитан на большое превью старого меню (340x920 в MenuUnit),
    -- в маленьком прямоугольнике сцены модель вылезала за рамки
    local holder = self.previewHolder
    if IsValid(holder) then
        local unit = math.min(ScrW(), ScrH()) / 1000
        local w, h = math.floor(340 * unit), math.floor(920 * unit)
        local x, y = ScrW() - w, math.floor(210 * unit)
        holder:Stop()
        holder:SetSize(w, h)
        holder:SetPos(x, y)
        holder.TargetX, holder.TargetY = x, y
        holder.ClosedY = ScrH()
    end
    local pm = self.previewModel
    if IsValid(pm) then
        pm.CamPosOverride, pm.FOVOverride, pm.LookAngOverride = nil, nil, nil
        pm.EntityAngleOverride, pm.SequenceNameOverride, pm.ActiveSequenceName = nil, nil, nil
    end

    local pp = self:ClearSubPanel()
    -- редактор сам берёт self.previewModel / self.previewHolder и крутит их вживую
    hg.CreateApperanceMenu(pp)
end

function PANEL:CreateBackButton(parent)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetSize(ScreenScale(70), ScreenScale(18))
    btn:SetPos(ScrW() - btn:GetWide() - ScreenScale(8), ScreenScale(8))
    btn:SetCursor("hand")
    btn.Paint = function(this, w, h)
        local hov = this:IsHovered()
        local flash = hov and (0.5 + 0.5 * math.sin(CurTime() * 10)) or 0
        local c = hov and Color(120 + flash * 100, 170 + flash * 70, 255) or Color(200, 215, 245)
        draw.SimpleTextOutlined("< BACK", "ZCamp_Back", w, h * 0.5, c,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 255))
    end
    btn.DoClick = function()
        UISound(SOUND_SELECT)
        self:CloseSubmenu()
    end
    btn:MoveToFront()
    return btn
end

function PANEL:CloseSubmenu()
    local kind = self.InSubmenu
    if not kind then return end

    if kind == "appearance" then
        -- редактор сам вернёт аватар и вызовет ResetCurrentPanel
        if IsValid(zpan) and zpan.ReturnToMenu then
            zpan:ReturnToMenu()
        else
            self:ReturnToScene()
        end
        return
    end

    local pp = self.panelparrent
    if IsValid(pp) then
        pp:AlphaTo(0, 0.2, 0, function()
            if IsValid(pp) then pp:Remove() end
        end)
    end
    self:ReturnToScene()
end

function PANEL:ReturnToScene()
    if self.InSubmenu and self.InSubmenu ~= "achievements" then
        self:UseDefaultMenuMusic()
    end
    self.InSubmenu = nil
    self.SeqModel = nil
    if IsValid(self.previewHolder) then
        self.previewHolder:SetVisible(true)
        self.previewHolder:AlphaTo(255, 0.2, 0)
    end
    self:ApplyCampPreview()
end

-- вызывается редактором внешности, когда он закрылся
function PANEL:ResetCurrentPanel()
    self:ReturnToScene()
end

function PANEL:ExitGame()
    if CAMP.exitMode == "quit" then
        self.InSubmenu = "quit"
        self.QuitStart = CurTime()
        self:UseDefaultMenuMusic()
        timer.Simple(0.8, function()
            RunConsoleCommand("quit")
        end)
        return
    end

    -- аватар в полный рост идёт вправо (в сторону мешка), экран гаснет, disconnect
    local pm = self.previewModel
    if IsValid(pm) and IsValid(self.previewHolder) then
        local a = CAMP.avatar
        local w, h = self.previewHolder:GetSize()
        pm.CamPosOverride = Vector(a.cam_dist, 0, a.exit_cam_z)
        pm.FOVOverride = VFovToFov(a.exit_vfov, w / math.max(h, 1))
    end
    self:PlayDisconnectCutscene()
end

-- ---------------------------------------------------------------------------
if ZMainMenuTbl then
    for k, v in pairs(ZMainMenuTbl) do
        if isfunction(v) and PANEL[k] == nil then
            PANEL[k] = v -- Close, OnRemove, PlayDisconnectCutscene, CreateAppearancePreview, музыка и т.д.
        end
    end
else
    ErrorNoHalt("[ZCampMenu] ZMainMenu is not registered yet - cl_menu_panel.lua must load first\n")
end

-- меню закрылось - звуки мира возвращаются
local baseOnRemove = PANEL.OnRemove
function PANEL:OnRemove()
    if baseOnRemove then baseOnRemove(self) end
    MuteWorld(false)
    if IsValid(self.RainSnd) then self.RainSnd:Stop() end
end

vgui.Register("ZCampMenu", PANEL, "ZFrame")

hook.Add("OnPauseMenuShow", "OpenMainMenu", function()
    local run = hook.Run("OnShowZCityPause")
    if run ~= nil then
        return run
    end

    if MainMenu and IsValid(MainMenu) then
        if MainMenu.DisconnectCutscene or MainMenu.QuitStart then
            return false
        end
        -- ESC внутри подменю = назад, а не закрыть всё меню
        if MainMenu.InSubmenu and MainMenu.CloseSubmenu then
            MainMenu:CloseSubmenu()
            return false
        end
        MainMenu:Close()
        MainMenu = nil
        return false
    end

    local useCamp = GetConVar("hg_menu_camp"):GetBool() and vgui.GetControlTable("ZCampMenu") ~= nil and ZMainMenuTbl ~= nil
    MainMenu = vgui.Create(useCamp and "ZCampMenu" or "ZMainMenu")
    MainMenu:MakePopup()
    return false
end)
