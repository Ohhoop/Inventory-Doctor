require "InventoryDoctor_Core"
require "InventoryDoctor_Commands"
require "InventoryDoctor_Inventory"

InventoryDoctorClientActions = {}

local listeners = {}

--- Registers a listener whose onZone(x, y, z, sources, rows) receives every zone description.
function InventoryDoctorClientActions.addListener(listener)
    listeners[listener] = true
end

--- Unregisters the listener.
function InventoryDoctorClientActions.removeListener(listener)
    listeners[listener] = nil
end

--- Passes the zone description to every listener.
local function notify(x, y, z, sources, rows)
    for listener in pairs(listeners) do
        listener:onZone(x, y, z, sources, rows)
    end
end

--- Scans the zone centered on the given square locally and passes it to the listeners.
local function scanLocally(x, y, z)
    local sources, rows = InventoryDoctor.scanZone(x, y, z)
    notify(x, y, z, sources, rows)
end

--- Asks for the contents of the zone centered on the given square: from the server in multiplayer, scanned locally in solo.
function InventoryDoctorClientActions.requestZone(playerObj, x, y, z)
    if isClient() then
        sendClientCommand(playerObj, InventoryDoctor.COMMAND_MODULE, InventoryDoctor.COMMAND_REQUEST_ZONE, { x = x, y = y, z = z })
        return
    end
    scanLocally(x, y, z)
end

--- Deletes or resets the item with the given id of the source, in the zone centered on the given square: through the server in multiplayer, locally in solo.
function InventoryDoctorClientActions.requestItemCommand(playerObj, command, x, y, z, source, id)
    local args = { x = x, y = y, z = z, source = source, id = id }
    if isClient() then
        sendClientCommand(playerObj, InventoryDoctor.COMMAND_MODULE, command, args)
        return
    end
    InventoryDoctor.runItemCommand(command, args)
    scanLocally(x, y, z)
end

--- Passes the zone descriptions sent by the server to the listeners.
local function onServerCommand(module, command, args)
    if module ~= InventoryDoctor.COMMAND_MODULE or command ~= InventoryDoctor.COMMAND_ZONE or type(args) ~= "table" then
        return
    end
    if InventoryDoctor.hasZoneCenter(args) and type(args.sources) == "table" and type(args.rows) == "table" then
        notify(args.x, args.y, args.z, args.sources, args.rows)
    end
end

Events.OnServerCommand.Add(onServerCommand)
