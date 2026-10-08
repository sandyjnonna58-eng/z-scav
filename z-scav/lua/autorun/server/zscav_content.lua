--[[
    Z-SCAV: чтобы игроки на сервере скачивали контент-пак (фон меню, звуки, музыку, картинки).

    Без этого клиенты НЕ получают картинки и звуки из контент-пака, и у них, например,
    нет фона главного меню.

    1) Загрузите z-scav-content в Workshop.
    2) Впишите его ID ниже (число из ссылки steamcommunity.com/sharedfiles/filedetails/?id=ЧИСЛО)
       или задайте в server.cfg:  zscav_content_workshop "ЧИСЛО"
]]

local CONTENT_ID = "" -- <- ID контент-пака Z-SCAV в Workshop

local cv = CreateConVar("zscav_content_workshop", CONTENT_ID, FCVAR_ARCHIVE, "Z-SCAV: Workshop ID контент-пака для скачивания клиентами")

local function Add()
    local id = string.Trim(cv:GetString() ~= "" and cv:GetString() or CONTENT_ID)
    if id ~= "" and tonumber(id) then
        resource.AddWorkshop(id)
        print("[Z-SCAV] клиенты будут скачивать контент-пак из Workshop: " .. id)
    else
        print("[Z-SCAV] ВНИМАНИЕ: не задан Workshop ID контент-пака (zscav_content_workshop) - у игроков может не быть фона меню и звуков")
    end
end

Add()
hook.Add("Initialize", "ZSCAV_ContentWorkshop", Add)
