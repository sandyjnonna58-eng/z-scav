hg.Abnormalties = hg.Abnormalties or {}
local PLUGIN = hg.Abnormalties

--\\
local convar_newbie = CreateClientConVar("abnormalties_newbie", "1", true, false, "Set to 1 if you want to see a hint again")

PLUGIN.MainColor = Color(150, 0, 0)
--//
-- abnormalties_help
--\\
net.Receive("Abnormalties(ShowTranslation)", function(len, ply)
	local abnormalty = {}
	local abnormalty_name = net.ReadString()
	local abnormalty_amt = net.ReadUInt(32)
	
	while abnormalty_name != "" and net.BytesLeft() > 0 do
		abnormalty[abnormalty_name] = abnormalty_amt
		abnormalty_name = net.ReadString()
		abnormalty_amt = net.ReadUInt(32)
	end
	
	if(convar_newbie:GetBool())then
		convar_newbie:SetBool(false)
		
		PLUGIN.ShowMessage("Вы наткнулись на нечто аномальное, введите abnormalties_help в консоли для справки")
	end
	
	PLUGIN.ShowTranslation(abnormalty)
end)

net.Receive("Abnormalties(ShowMessage)", function(len, ply)
	local msg = net.ReadString()
	
	PLUGIN.ShowMessage(msg)
end)
--//

--\\
function PLUGIN.ShowTranslation(abnormalty)
	-- Abnormalties_VGUI_Abnormalty = abnormalty
	-- Abnormalties_VGUI_AbnormaltyTimeEnd = CurTime() + 10
	local count = 0
	
	chat.AddText(PLUGIN.MainColor, "Кажется, я к чему-то прихожу...")
	
	for abnormalty_name, abnormalty_amt in pairs(abnormalty) do
		chat.AddText(PLUGIN.MainColor, abnormalty_name, " - " .. abnormalty_amt)
		
		count = count + 1
	end
	
	if(count > 1)then
		chat.AddText(PLUGIN.MainColor, "Но есть ещё что-то, что нужно исключить...")
	elseif(count == 1)then
		chat.AddText(PLUGIN.MainColor, "Вот оно... Я нашёл!")
		chat.AddText(PLUGIN.MainColor, "Теперь осталось повторять это снова и снова на одном месте...")
	elseif(count == 0)then
		chat.AddText(PLUGIN.MainColor, "Но... Бесполезно, нужно вложить смысл в слова...")
	end
end

function PLUGIN.ShowMessage(msg)
	chat.AddText(PLUGIN.MainColor, msg)
end
--//