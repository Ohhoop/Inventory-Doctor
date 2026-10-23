require "ISUI/ISModalDialog"

InventoryDoctorConfirm = {}

local CONFIRM_WIDTH = 380
local CONFIRM_HEIGHT = 170

--- Runs the confirmed action when the player answered yes.
local function onAnswer(_target, button, onConfirmed)
    if button.internal == "YES" then
        onConfirmed()
    end
end

--- Asks the player to confirm the action described by the translated message for the entry, warning that a bag's contents or a liquid will be lost and that a worn or held item will be taken off; runs onConfirmed on yes.
function InventoryDoctorConfirm.show(playerNum, messageKey, entry, onConfirmed)
    local text = getText(messageKey, string.format("%s (%s)", entry.name, entry.item))
    if entry.row.holdsItems then
        text = text .. "\n" .. getText("UI_InventoryDoctor_ConfirmHoldsItems")
    end
    if entry.row.hasFluid then
        text = text .. "\n" .. getText("UI_InventoryDoctor_ConfirmFluid")
    end
    if entry.row.equipped then
        text = text .. "\n" .. getText("UI_InventoryDoctor_ConfirmEquipped")
    end
    local dialog = ISModalDialog:new(0, 0, CONFIRM_WIDTH, CONFIRM_HEIGHT, text, true, nil, onAnswer, playerNum, onConfirmed)
    dialog:initialise()
    dialog:centerOnScreen(playerNum)
    dialog:addToUIManager()
end
