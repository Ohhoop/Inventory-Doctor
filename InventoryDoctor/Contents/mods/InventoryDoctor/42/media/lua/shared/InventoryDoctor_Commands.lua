require "InventoryDoctor_Core"
require "InventoryDoctor_Inventory"

InventoryDoctor.COMMAND_REQUEST_ZONE = "requestZone"
InventoryDoctor.COMMAND_DELETE_ITEM = "deleteItem"
InventoryDoctor.COMMAND_RESET_ITEM = "resetItem"
InventoryDoctor.COMMAND_ZONE = "zone"

local ITEM_ACTIONS = {
    [InventoryDoctor.COMMAND_DELETE_ITEM] = InventoryDoctor.deleteItem,
    [InventoryDoctor.COMMAND_RESET_ITEM] = InventoryDoctor.resetItem,
}

--- Returns true when the command acts on one item.
function InventoryDoctor.isItemCommand(command)
    return ITEM_ACTIONS[command] ~= nil
end

--- Returns true when the arguments carry whole zone center coordinates.
function InventoryDoctor.hasZoneCenter(args)
    return InventoryDoctor.isInteger(args.x) and InventoryDoctor.isInteger(args.y) and InventoryDoctor.isInteger(args.z)
end

--- Finds the item designated by the source and id of the arguments inside the zone they name and applies the command to it; returns the item type when it was found, nil otherwise.
function InventoryDoctor.runItemCommand(command, args)
    local action = ITEM_ACTIONS[command]
    if not action or not InventoryDoctor.hasZoneCenter(args) or not InventoryDoctor.isInteger(args.id) or type(args.source) ~= "table" then
        return nil
    end
    if not InventoryDoctor.isSourceInZone(args.source, args.x, args.y, args.z) then
        return nil
    end
    local resolved = InventoryDoctor.resolveSource(args.source)
    local item = resolved and InventoryDoctor.findItem(resolved, args.id)
    if not item then
        return nil
    end
    local fullType = item:getFullType()
    action(resolved, item)
    return fullType
end
