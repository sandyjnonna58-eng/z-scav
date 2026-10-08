--[[
    REM: "позывы" из оригинального Remorse отключены вместе со старой депрессией.
    Депрессия теперь - sv_depression.lua (на основе настроения, без вреда себе).
    Сетевые сообщения оставлены, чтобы клиентский код не выдавал ошибок.
]]

util.AddNetworkString("rem_urges_press")
util.AddNetworkString("rem_urges_end")
net.Receive("rem_urges_press", function() end)

hg.StartSuicideUrge = function() end
