require "InventoryDoctor_Core"
require "InventoryDoctor_Sources"

local CHECKED_METHODS = { "getDisplayName", "getScriptItem", "getCategory" }

--- Returns a reader that calls a method of the item by name and returns its value, or nil when the call throws; hasFailed tells whether any call threw.
local function newReader(item)
    local reader = { hasFailed = false }
    function reader.read(methodName)
        local ok, value = pcall(function()
            return item[methodName](item)
        end)
        if not ok then
            reader.hasFailed = true
            return nil
        end
        return value
    end
    return reader
end

--- Returns true when the item holds a liquid, recording an error in the reader when the liquid cannot be read.
local function holdsFluid(reader)
    local fluid = reader.read("getFluidContainer")
    if not fluid then
        return false
    end
    local ok, empty = pcall(function()
        return fluid:isEmpty()
    end)
    if not ok then
        reader.hasFailed = true
        return false
    end
    return not empty
end

--- Returns true when one of the weights is negative.
local function isAnyNegative(weights)
    for _, weight in pairs(weights) do
        if weight < 0 then
            return true
        end
    end
    return false
end

--- Returns the weights of the item the game uses: its own weight, its weight with its contents and, for a bag, its weight once worn.
local function readWeights(reader, item)
    local weights = {
        reader.read("getActualWeight"),
        reader.read("getUnequippedWeight"),
    }
    if instanceof(item, "InventoryContainer") then
        table.insert(weights, reader.read("getEquippedWeight"))
    end
    return weights
end

--- Returns the plain description of an item, safe to send over the network: its source, id, type, the types of the bags holding it, its condition, its weight and whether one of its weights is negative, whether it is worn, held or attached, whether it holds items or a liquid, and whether reading it threw an error.
local function describeItem(item, sourceIndex, path, player, isFloorItem)
    local reader = newReader(item)
    local row = {
        source = sourceIndex,
        id = reader.read("getID"),
        fullType = reader.read("getFullType"),
        path = path,
        condition = reader.read("getCondition"),
        conditionMax = reader.read("getConditionMax"),
        equipped = player ~= nil and (player:isEquipped(item) or player:isAttachedItem(item)),
        holdsItems = false,
        isFloorItem = isFloorItem,
    }
    local weights = readWeights(reader, item)
    row.weight = weights[1]
    row.negativeWeight = isAnyNegative(weights)
    row.hasFluid = holdsFluid(reader)
    for _, methodName in ipairs(CHECKED_METHODS) do
        reader.read(methodName)
    end
    row.failed = reader.hasFailed
    return row
end

--- Returns a copy of the bag path with the given item type appended.
local function extendPath(path, fullType)
    local extended = {}
    for i, value in ipairs(path) do
        extended[i] = value
    end
    table.insert(extended, fullType or "?")
    return extended
end

local collectContainer

--- Appends the row of the item to rows, then the rows of its contents when it is a bag.
local function collectItem(item, sourceIndex, path, player, isFloorItem, rows)
    local row = describeItem(item, sourceIndex, path, player, isFloorItem)
    table.insert(rows, row)
    if instanceof(item, "InventoryContainer") then
        local inner = item:getInventory()
        row.holdsItems = not inner:isEmpty()
        collectContainer(inner, sourceIndex, extendPath(path, row.fullType), player, rows)
    end
end

--- Appends to rows the description of every item of the container and of the bags it holds, at any depth.
collectContainer = function(container, sourceIndex, path, player, rows)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        collectItem(items:get(i), sourceIndex, path, player, false, rows)
    end
end

--- Returns the source locators and the item descriptions of every container of the 3x3 zone centered on the given square.
function InventoryDoctor.scanZone(x, y, z)
    local sources = {}
    local rows = {}
    InventoryDoctor.forEachSource(x, y, z, function(source, container, player, floorItem)
        table.insert(sources, source)
        local sourceIndex = #sources
        if floorItem then
            collectItem(floorItem, sourceIndex, {}, nil, true, rows)
        else
            collectContainer(container, sourceIndex, {}, player, rows)
        end
    end)
    return sources, rows
end

--- Returns the item with the given id inside the resolved source, at any depth, or nil when there is none.
function InventoryDoctor.findItem(resolved, id)
    if resolved.floorObject and resolved.floorObject:getItem():getID() == id then
        return resolved.floorObject:getItem()
    end
    for _, container in ipairs(resolved.containers) do
        local item = container:getItemWithIDRecursiv(id)
        if item then
            return item
        end
    end
    return nil
end

--- Returns true when the item is the dropped item of the resolved source itself.
local function isFloorItem(resolved, item)
    return resolved.floorObject ~= nil and resolved.floorObject:getItem() == item
end

--- Takes the item off the player when it is worn or attached.
local function takeOff(player, item)
    if player:isEquippedClothing(item) then
        player:removeWornItem(item)
        if not isServer() then
            triggerEvent("OnClothingUpdated", player)
        end
    end
    if player:isAttachedItem(item) then
        player:removeAttachedItem(item)
    end
end

--- Removes the item from the resolved source, taking it off first when a player wears or carries it attached, and tells the clients in multiplayer; returns the container it was in, or nil for a dropped item.
local function removeItem(resolved, item)
    if isFloorItem(resolved, item) then
        resolved.square:transmitRemoveItemFromSquare(resolved.floorObject, false)
        return nil
    end
    if resolved.player then
        takeOff(resolved.player, item)
    end
    local container = item:getContainer()
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    return container
end

--- Deletes the item from the resolved source.
function InventoryDoctor.deleteItem(resolved, item)
    removeItem(resolved, item)
end

--- Replaces the item with a new item of the same type at the same place, losing its contents and liquid; returns false when no item of that type can be created.
function InventoryDoctor.resetItem(resolved, item)
    local fresh = instanceItem(item:getFullType())
    if not fresh then
        return false
    end
    if isFloorItem(resolved, item) then
        local object = resolved.floorObject
        resolved.square:AddWorldInventoryItem(fresh, object:getOffX(), object:getOffY(), object:getOffZ())
        removeItem(resolved, item)
        return true
    end
    local container = removeItem(resolved, item)
    container:AddItem(fresh)
    sendAddItemToContainer(container, fresh)
    return true
end
