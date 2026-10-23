require "InventoryDoctor_Core"

InventoryDoctor.SOURCE_PLAYER = "player"
InventoryDoctor.SOURCE_OBJECT = "object"
InventoryDoctor.SOURCE_FLOOR = "floor"
InventoryDoctor.SOURCE_CORPSE = "corpse"
InventoryDoctor.SOURCE_VEHICLE = "vehicle"

--- Returns the sprite name of the object, or an empty string when it has none.
local function getSpriteName(object)
    local sprite = object:getSprite()
    return sprite and sprite:getName() or ""
end

--- Returns a key identifying the corpse by its outfit and by whether it was a zombie.
local function getCorpseKey(body)
    return "corpse:" .. tostring(body:getOutfitName()) .. ":" .. tostring(body:isZombie())
end

--- Returns the element at the given index of the list, or nil when the index is outside the list.
local function elementAt(list, index)
    if not InventoryDoctor.isInteger(index) or index < 0 or index >= list:size() then
        return nil
    end
    return list:get(index)
end

--- Returns a new source locator of the given kind on the square.
local function newSource(kind, square)
    return { kind = kind, x = square:getX(), y = square:getY(), z = square:getZ() }
end

--- Calls visit with the locator and the container of every player standing on the square.
local function visitPlayers(square, visit)
    local moving = square:getMovingObjects()
    for i = 0, moving:size() - 1 do
        local player = moving:get(i)
        if instanceof(player, "IsoPlayer") then
            local source = newSource(InventoryDoctor.SOURCE_PLAYER, square)
            source.key = player:getUsername()
            visit(source, player:getInventory(), player)
        end
    end
end

--- Calls visit with the locator and the container of every container of the objects of the square, dropped items excepted.
local function visitObjects(square, visit)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if not instanceof(object, "IsoWorldInventoryObject") then
            for c = 0, object:getContainerCount() - 1 do
                local container = object:getContainerByIndex(c)
                local source = newSource(InventoryDoctor.SOURCE_OBJECT, square)
                source.index = i
                source.key = getSpriteName(object)
                source.containerIndex = c
                source.containerType = container:getType()
                visit(source, container, nil)
            end
        end
    end
end

--- Calls visit with the locator of every item dropped on the square, without container.
local function visitFloor(square, visit)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item then
            local source = newSource(InventoryDoctor.SOURCE_FLOOR, square)
            source.index = i
            source.key = item:getID()
            visit(source, nil, nil, item)
        end
    end
end

--- Calls visit with the locator and the container of every corpse of the square.
local function visitCorpses(square, visit)
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        local container = body:getContainer()
        if container then
            local source = newSource(InventoryDoctor.SOURCE_CORPSE, square)
            source.index = i
            source.key = getCorpseKey(body)
            source.containerType = container:getType()
            visit(source, container, nil)
        end
    end
end

--- Calls visit with the locator and the container of every part of the vehicle covering the square that holds items, once per vehicle.
local function visitVehicle(square, visit, seenVehicles)
    local vehicle = square:getVehicleContainer()
    if not vehicle or seenVehicles[vehicle:getId()] then
        return
    end
    seenVehicles[vehicle:getId()] = true
    for p = 0, vehicle:getPartCount() - 1 do
        local container = vehicle:getPartByIndex(p):getItemContainer()
        if container then
            local source = newSource(InventoryDoctor.SOURCE_VEHICLE, square)
            source.key = vehicle:getId()
            source.partIndex = p
            source.containerType = container:getType()
            visit(source, container, nil)
        end
    end
end

--- Returns the loaded squares of the 3x3 zone centered on the given square.
function InventoryDoctor.getZoneSquares(x, y, z)
    local cell = getCell()
    local squares = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            if square then
                table.insert(squares, square)
            end
        end
    end
    return squares
end

--- Calls visit(source, container, player, floorItem) for every player, furniture container, dropped item, corpse and vehicle part of the 3x3 zone centered on the given square.
function InventoryDoctor.forEachSource(x, y, z, visit)
    local seenVehicles = {}
    for _, square in ipairs(InventoryDoctor.getZoneSquares(x, y, z)) do
        visitPlayers(square, visit)
        visitObjects(square, visit)
        visitFloor(square, visit)
        visitCorpses(square, visit)
        visitVehicle(square, visit, seenVehicles)
    end
end

--- Returns true when the square of the source lies in the 3x3 zone centered on the given square.
function InventoryDoctor.isSourceInZone(source, x, y, z)
    if not InventoryDoctor.isInteger(source.x) or not InventoryDoctor.isInteger(source.y) or not InventoryDoctor.isInteger(source.z) then
        return false
    end
    return source.z == z and math.abs(source.x - x) <= 1 and math.abs(source.y - y) <= 1
end

--- Returns the player of the square with the source's username.
local function resolvePlayer(square, source)
    local moving = square:getMovingObjects()
    for i = 0, moving:size() - 1 do
        local player = moving:get(i)
        if instanceof(player, "IsoPlayer") and player:getUsername() == source.key then
            return { owner = player, player = player, containers = { player:getInventory() } }
        end
    end
    return nil
end

--- Returns the container of the square's object designated by the source when the object still carries the same sprite.
local function resolveObject(square, source)
    local object = elementAt(square:getObjects(), source.index)
    if not object or getSpriteName(object) ~= source.key or not InventoryDoctor.isInteger(source.containerIndex) then
        return nil
    end
    local container = source.containerIndex < object:getContainerCount() and object:getContainerByIndex(source.containerIndex)
    if not container then
        return nil
    end
    return { owner = object, containers = { container } }
end

--- Returns the dropped item of the square designated by the source when it still has the same id, with its contents when it is a bag.
local function resolveFloor(square, source)
    local object = elementAt(square:getWorldObjects(), source.index)
    local item = object and object:getItem()
    if not item or item:getID() ~= source.key then
        return nil
    end
    local containers = {}
    if instanceof(item, "InventoryContainer") then
        table.insert(containers, item:getInventory())
    end
    return { owner = object, floorObject = object, square = square, containers = containers }
end

--- Returns the container of the square's corpse designated by the source when it still has the same outfit.
local function resolveCorpse(square, source)
    local body = elementAt(square:getDeadBodys(), source.index)
    if not body or getCorpseKey(body) ~= source.key or not body:getContainer() then
        return nil
    end
    return { owner = body, containers = { body:getContainer() } }
end

--- Returns the container of the vehicle part designated by the source when the vehicle covering the square still has the same id.
local function resolveVehicle(square, source)
    local vehicle = square:getVehicleContainer()
    if not vehicle or vehicle:getId() ~= source.key or not InventoryDoctor.isInteger(source.partIndex) then
        return nil
    end
    if source.partIndex < 0 or source.partIndex >= vehicle:getPartCount() then
        return nil
    end
    local container = vehicle:getPartByIndex(source.partIndex):getItemContainer()
    if not container then
        return nil
    end
    return { owner = vehicle, containers = { container } }
end

local RESOLVERS = {
    [InventoryDoctor.SOURCE_PLAYER] = resolvePlayer,
    [InventoryDoctor.SOURCE_OBJECT] = resolveObject,
    [InventoryDoctor.SOURCE_FLOOR] = resolveFloor,
    [InventoryDoctor.SOURCE_CORPSE] = resolveCorpse,
    [InventoryDoctor.SOURCE_VEHICLE] = resolveVehicle,
}

--- Returns what the source locator designates on this machine: the world element to outline, its containers, and the player or dropped item it is; nil when the locator is invalid or the element is gone.
function InventoryDoctor.resolveSource(source)
    if type(source) ~= "table" or not InventoryDoctor.isInteger(source.x) or not InventoryDoctor.isInteger(source.y) or not InventoryDoctor.isInteger(source.z) then
        return nil
    end
    local resolver = RESOLVERS[source.kind]
    local square = resolver and getCell():getGridSquare(source.x, source.y, source.z)
    if not square then
        return nil
    end
    return resolver(square, source)
end
