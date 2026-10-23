require "luautils"

InventoryDoctor = InventoryDoctor or {}

InventoryDoctor.COMMAND_MODULE = "InventoryDoctor"
InventoryDoctor.MOD_ID = "InventoryDoctor"

local DEV_SUFFIX = "-DEV"

InventoryDoctor.OUTLINE_COLOR = { r = 1.0, g = 0.9, b = 0.0, a = 1.0 }

--- Returns true when this copy of the mod is the development build.
function InventoryDoctor.isDevBuild()
    return luautils.stringEnds(InventoryDoctor.MOD_ID, DEV_SUFFIX)
end

--- Returns true when the value is a whole number.
function InventoryDoctor.isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

--- Returns true when the player holds the capability: always in solo, as validated by the server on the server, and from the player's role on a client.
local function hasCapability(player, capability)
    if not isClient() and not isServer() then
        return true
    end
    if not player then
        return false
    end
    if isServer() then
        return checkPermissions(player, capability)
    end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(capability)
end

--- Returns true when the player is allowed to list the items of an inventory.
function InventoryDoctor.canInspect(player)
    return hasCapability(player, Capability.InspectPlayerInventory)
end

--- Returns true when the player is allowed to delete items.
function InventoryDoctor.canDelete(player)
    return hasCapability(player, Capability.EditItem)
end

--- Returns the texture of the mod file at the given path relative to the mod version folder, loaded by its absolute path.
function InventoryDoctor.getModTexture(path)
    return getTexture(getModInfoByID(InventoryDoctor.MOD_ID):getVersionDir() .. "/" .. path)
end
