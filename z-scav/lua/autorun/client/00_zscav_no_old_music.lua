--[[
    Z-SCAV: отключение старых треков Remorse / Z-City.

    Вместо них теперь играют треки Z-SCAV (sound/remorse/*): Dying, Death, Despair, Drowning,
    усталость, Is this the end, PainDrone, музыка меню/настроек/титров.

    Любой sound.PlayFile / surface.PlaySound по пути из списка ниже просто не играет
    (код, который его запрашивал, получает "нет звука" и продолжает работать).
    Вернуть трек: удалить его строку из списка. Вернуть всё: zscav_old_music 1
]]

local cv = CreateClientConVar("zscav_old_music", "0", true, false, "1 - вернуть старые треки Remorse/Z-City", 0, 1)

-- точные пути (без "sound/")
local BLOCK = {
    ["rem_dying1.mp3"]            = true, -- шум умирания (заменён Drowning / Is this the end)
    ["rem_dying2.mp3"]            = true,
    ["rem_deathstatefull.mp3"]    = true, -- таймер умирания (заменён Dying)
    ["zbattle/pain_beat.ogg"]     = true, -- музыка боли (заменена PainDrone)
    ["rem_mainmenu.mp3"]          = true, -- старая музыка меню
    ["zbattle/pharmacia.mp3"]     = true, -- музыка берсерка
    ["zbattle/deathsample.ogg"]   = true, -- смерть в берсерке (заменена Death)
    ["shitty/music/mi_deathcam.mp3"] = true, -- смерть под норадреналином (заменена Death)

    -- умирание / смерть
    ["rem_brutaldeath.mp3"]       = true, -- музыка экрана смерти (заменена Death)
    ["rem_heartstop.wav"]         = true, -- остановка сердца
    ["rem_heartstopuncon.wav"]    = true, -- остановка сердца без сознания (начало таймера)
    ["rem_cerebralanoxia.wav"]    = true, -- гул кислородного голодания мозга
    ["rem_fibrillation.mp3"]      = true, -- фибрилляция (заменена Is this the end)
    ["rem_youarebetteroffdead.mp3"] = true, -- мидазолам

    -- боль / психика (заменены PainDrone, Despair, приступом мыслей)
    ["rem_agony.ogg"]             = true,
    ["rem_excruciatingpain.ogg"]  = true,
    ["rem_pain.mp3"]              = true,
    ["rem_despair.mp3"]           = true,
    ["rem_panicattack.mp3"]       = true,
    ["rem_seizure.ogg"]           = true,
    ["rem_earsringaswounddeepens.ogg"] = true,
    ["rem_enditall.mp3"]          = true,
    ["rem_resisttheurges.mp3"]    = true,

    -- музыка раундов и режимов
    ["rem_track1.mp3"]            = true,
    ["rem_track2.mp3"]            = true,
    ["rem_tdm.mp3"]               = true,
    ["rem_dmround.mp3"]           = true,
    ["rem_newroundcommence.mp3"]  = true,
    ["rem_newroundreveal.wav"]    = true,
    ["rem_clearround.wav"]        = true,
}
-- целые папки (боевая динамическая музыка)
local BLOCK_PREFIX = {
    "zc_dyna_music/",
    "zcity_ost/",
    "realishgamemode/",
}
-- гардероб (rem_appearencemenu.mp3) оставлен

local function Normalize(path)
    path = string.lower(string.gsub(tostring(path or ""), "\\", "/"))
    path = string.gsub(path, "^sound/", "")
    return path
end

local function Blocked(path)
    if cv:GetBool() then return false end
    local p = Normalize(path)
    if BLOCK[p] then return true end
    for _, pre in ipairs(BLOCK_PREFIX) do
        if string.sub(p, 1, #pre) == pre then return true end
    end
    return false
end
ZSCAV_IsOldTrack = Blocked

local origPlayFile = sound.PlayFile
function sound.PlayFile(path, flags, callback, ...)
    if Blocked(path) then
        if callback then callback(nil, -1, "Z-SCAV: old track disabled") end
        return
    end
    return origPlayFile(path, flags, callback, ...)
end

local origPlaySound = surface.PlaySound
function surface.PlaySound(path, ...)
    if Blocked(path) then return end
    return origPlaySound(path, ...)
end

-- CreateSound: подменяем трек на "тишину", чтобы вызывающий код получил рабочий объект и не упал
local SILENT = "common/null.wav"
local origCreateSound = CreateSound
function CreateSound(ent, path, ...)
    if Blocked(path) then return origCreateSound(ent, SILENT, ...) end
    return origCreateSound(ent, path, ...)
end

local origSoundPlay = sound.Play
function sound.Play(path, ...)
    if Blocked(path) then return end
    return origSoundPlay(path, ...)
end

local origEmitSound = EmitSound
function EmitSound(path, ...)
    if Blocked(path) then return end
    return origEmitSound(path, ...)
end

-- звуки от сущностей (ent:EmitSound)
hook.Add("EntityEmitSound", "ZSCAV_NoOldMusic", function(data)
    if data and Blocked(data.SoundName) then return false end
end)
