--[[
    Z-SCAV: клиентская часть "позывов" из оригинального Remorse отключена
    (серверная часть - заглушка в sv_suicideurges.lua).
    Сетевые сообщения принимаются впустую, чтобы не было ошибок.
]]
net.Receive("rem_suicide_attempt", function() end)
net.Receive("rem_selfharm_end", function() end)
net.Receive("rem_urges_end", function() end)
