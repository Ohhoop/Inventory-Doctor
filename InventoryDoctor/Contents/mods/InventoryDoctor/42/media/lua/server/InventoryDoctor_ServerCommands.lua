require "InventoryDoctor_Core"
require "InventoryDoctor_Commands"
require "InventoryDoctor_Inventory"

--- Logs that the command was refused to the player.
local function logDenied(player, command)
    print("InventoryDoctor: " .. tostring(command) .. " denied for " .. tostring(player and player:getUsername()))
end

--- Returns true when the zone center named by the arguments lies on the admin's square or next to it, on the admin's level.
local function isCenterNearAdmin(admin, args)
    if not InventoryDoctor.hasZoneCenter(args) then
        return false
    end
    local x, y, z = math.floor(admin:getX()), math.floor(admin:getY()), math.floor(admin:getZ())
    return args.z == z and math.abs(args.x - x) <= 1 and math.abs(args.y - y) <= 1
end

--- Sends to the admin the source locators and item descriptions of the zone centered on the given square.
local function reportZone(admin, args)
    local sources, rows = InventoryDoctor.scanZone(args.x, args.y, args.z)
    sendServerCommand(admin, InventoryDoctor.COMMAND_MODULE, InventoryDoctor.COMMAND_ZONE, {
        x = args.x,
        y = args.y,
        z = args.z,
        sources = sources,
        rows = rows,
    })
end

--- Sends the contents of the zone around an admin allowed to inspect inventories.
local function onRequestZone(admin, command, args)
    if not InventoryDoctor.canInspect(admin) or not isCenterNearAdmin(admin, args) then
        logDenied(admin, command)
        return
    end
    reportZone(admin, args)
end

--- Deletes or resets the requested item of the zone around an admin allowed to edit items, logs it, then sends the updated zone when the admin may inspect it.
local function onItemCommand(admin, command, args)
    if not InventoryDoctor.canDelete(admin) or not isCenterNearAdmin(admin, args) then
        logDenied(admin, command)
        return
    end
    local fullType = InventoryDoctor.runItemCommand(command, args)
    if fullType then
        print("InventoryDoctor: " .. admin:getUsername() .. " " .. command .. " " .. fullType .. " (id " .. tostring(args.id) .. ") at " .. args.source.x .. "," .. args.source.y .. "," .. args.source.z)
    end
    if InventoryDoctor.canInspect(admin) then
        reportZone(admin, args)
    end
end

--- Runs the requested Inventory Doctor command.
local function onClientCommand(module, command, player, args)
    if module ~= InventoryDoctor.COMMAND_MODULE or type(args) ~= "table" then
        return
    end
    if command == InventoryDoctor.COMMAND_REQUEST_ZONE then
        onRequestZone(player, command, args)
    elseif InventoryDoctor.isItemCommand(command) then
        onItemCommand(player, command, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
