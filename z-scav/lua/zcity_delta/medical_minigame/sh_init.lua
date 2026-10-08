if SERVER then
    util.AddNetworkString("hg_medical_minigame_start")
    util.AddNetworkString("hg_medical_minigame_progress")
    util.AddNetworkString("hg_medical_minigame_finish")
    util.AddNetworkString("hg_medical_minigame_cancel")
    util.AddNetworkString("hg_medical_minigame_request_amputation")
end

hg.MedicalMinigame = hg.MedicalMinigame or {}
hg.MedicalMinigame.RequiredTurns = 7.5
