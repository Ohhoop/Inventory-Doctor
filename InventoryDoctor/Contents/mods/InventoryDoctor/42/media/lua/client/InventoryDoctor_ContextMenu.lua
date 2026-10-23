require "InventoryDoctor_Core"
require "InventoryDoctor_Window"

local TITLE = "Inventory Doctor"
local MENU_ICON = "media/ui/InventoryDoctor/DoctorHealCross.png"

--- Opens the Inventory Doctor window following the player.
local function onOpenWindow(playerObj)
    InventoryDoctorWindow.open(playerObj)
end

--- Adds the Inventory Doctor option, with its red cross icon, to the world context menu for allowed players.
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    if not InventoryDoctor.canInspect(playerObj) then
        return
    end
    if test and ISWorldObjectContextMenu.Test then
        return true
    end
    local option = context:addOption(TITLE, playerObj, onOpenWindow)
    option.iconTexture = InventoryDoctor.getModTexture(MENU_ICON)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
