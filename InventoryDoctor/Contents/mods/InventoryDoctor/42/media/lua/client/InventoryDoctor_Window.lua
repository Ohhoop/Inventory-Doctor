require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "InventoryDoctor_Core"
require "InventoryDoctor_Commands"
require "InventoryDoctor_Sources"
require "InventoryDoctor_ClientActions"
require "InventoryDoctor_Confirm"
require "InventoryDoctor_TableHeader"
require "InventoryDoctor_TileOutline"

local PADDING = 8
local CELL_PADDING = 6
local ICON_GAP = 6
local REFRESH_INTERVAL_MS = 1000
local TILE_CHANGE_MARGIN = 0.2
local WINDOW_HEIGHT = 360
local SCROLLBAR_ALLOWANCE = 20
local ELLIPSIS = "..."
local PATH_SEPARATOR = " > "
local TITLE = "Inventory Doctor"
local ALERT_MARK = "!"
local UNKNOWN_COLOR = { r = 1.0, g = 0.45, b = 0.45, a = 1.0 }
local DELETE_TEXTURE = "media/ui/InventoryDoctor/Delete.png"
local RESET_TEXTURE = "media/ui/InventoryDoctor/Reset.png"
local ALERT_TEXTURE = "media/ui/InventoryDoctor/Alert.png"
local MISSING_ICON_TEXTURE = "media/inventory/Question_On.png"

local RESET_ACTION = { command = InventoryDoctor.COMMAND_RESET_ITEM, confirmKey = "UI_InventoryDoctor_ConfirmReset", tooltipKey = "UI_InventoryDoctor_TooltipReset" }
local DELETE_ACTION = { command = InventoryDoctor.COMMAND_DELETE_ITEM, confirmKey = "UI_InventoryDoctor_ConfirmDelete", tooltipKey = "UI_InventoryDoctor_TooltipDelete" }

local COLUMN_DEFINITIONS = {
    { kind = "alert", field = "alert", label = ALERT_MARK, width = 26, centered = true },
    { kind = "text", field = "square", sortField = "squareSortKey", titleKey = "UI_InventoryDoctor_ColSquare", width = 90 },
    { kind = "text", field = "name", titleKey = "UI_InventoryDoctor_ColName", width = 190 },
    { kind = "text", field = "item", titleKey = "UI_InventoryDoctor_ColItem", width = 210 },
    { kind = "text", field = "condition", sortField = "conditionSortKey", titleKey = "UI_InventoryDoctor_ColCondition", width = 90 },
    { kind = "text", field = "weight", sortField = "weightSortKey", titleKey = "UI_InventoryDoctor_ColWeight", width = 80 },
    { kind = "text", field = "container", titleKey = "UI_InventoryDoctor_ColContainer", width = 220 },
    { kind = "actions", field = nil, titleKey = "UI_InventoryDoctor_ColActions", width = 70 },
}

--- Returns a fresh copy of the column definitions for one window, with translated titles or their fixed label.
local function createColumns()
    local columns = {}
    for _, definition in ipairs(COLUMN_DEFINITIONS) do
        local title = definition.titleKey and getText(definition.titleKey) or definition.label
        table.insert(columns, {
            kind = definition.kind,
            field = definition.field,
            sortField = definition.sortField,
            title = title,
            width = definition.width,
            minWidth = definition.width,
            centered = definition.centered,
            x = 0,
        })
    end
    return columns
end

--- Returns the total width of the column definitions.
local function getTableWidth()
    local width = 0
    for _, definition in ipairs(COLUMN_DEFINITIONS) do
        width = width + definition.width
    end
    return width
end

--- Shows or hides the native outline of the world element for the player.
local function setOutline(element, playerNum, isOutlined)
    if isOutlined then
        local color = InventoryDoctor.OUTLINE_COLOR
        element:setOutlineHighlightCol(playerNum, color.r, color.g, color.b, color.a)
    end
    element:setOutlineHighlight(playerNum, isOutlined)
    element:setOutlineHlAttached(playerNum, isOutlined)
end

--- Returns the text shortened with an ellipsis so that it fits in the given width.
local function fitText(font, text, width)
    local manager = getTextManager()
    if manager:MeasureStringX(font, text) <= width then
        return text
    end
    local low, high = 0, #text
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if manager:MeasureStringX(font, string.sub(text, 1, middle) .. ELLIPSIS) <= width then
            low = middle
        else
            high = middle - 1
        end
    end
    return string.sub(text, 1, low) .. ELLIPSIS
end

InventoryDoctorItemList = ISScrollingListBox:derive("InventoryDoctorItemList")

--- Returns the text of the field of the row fitted to the width, computing it again only when the width changed.
function InventoryDoctorItemList:getFittedText(entry, field, width)
    local cached = entry.fitted[field]
    if not cached or cached.width ~= width then
        cached = { width = width, text = fitText(self.font, entry[field], width) }
        entry.fitted[field] = cached
    end
    return cached.text
end

--- Returns the size of the row icons.
function InventoryDoctorItemList:getIconSize()
    return self.itemheight - 4
end

--- Returns the left position of the reset icon and of the delete icon inside the given actions column.
function InventoryDoctorItemList:getActionIconsX(column)
    local resetX = column.x + CELL_PADDING
    local deleteX = resetX + self:getIconSize() + ICON_GAP
    return resetX, deleteX
end

--- Draws the text of the column field in the cell, in red when the cell carries a warning.
local function drawTextCell(list, entry, column, y, height)
    local color = entry.warnings[column.field] and UNKNOWN_COLOR or list.textColor
    local text = list:getFittedText(entry, column.field, column.width - CELL_PADDING * 2)
    list:drawText(text, column.x + CELL_PADDING, y + (height - list.fontHgt) / 2, color.r, color.g, color.b, color.a, list.font)
end

--- Draws the alert icon centered in the cell when the row is flagged.
local function drawAlertCell(list, entry, column, y, height)
    if entry.alert == "" then
        return
    end
    local size = list:getIconSize()
    list:drawTextureScaled(list.alertTexture, column.x + (column.width - size) / 2, y + (height - size) / 2, size, size, 1, 1, 1, 1)
end

--- Draws the reset and delete icons when the row can be edited.
local function drawActionsCell(list, entry, column, y, height)
    if not entry.canEdit then
        return
    end
    local size = list:getIconSize()
    local iconY = y + (height - size) / 2
    local resetX, deleteX = list:getActionIconsX(column)
    list:drawTextureScaled(list.resetTexture, resetX, iconY, size, size, 1, 1, 1, 1)
    list:drawTextureScaled(list.deleteTexture, deleteX, iconY, size, size, 1, 1, 1, 1)
end

--- Returns the alert explanation of the row, or nil when it is not flagged.
local function alertTooltip(_list, entry)
    return entry.alertTooltip
end

--- Returns the action of the row whose icon lies under the mouse, or nil when the mouse is over no available icon.
local function actionAt(list, entry, column, mouseX)
    if not entry.canEdit then
        return nil
    end
    local size = list:getIconSize()
    local resetX, deleteX = list:getActionIconsX(column)
    if mouseX >= deleteX and mouseX < deleteX + size then
        return DELETE_ACTION
    end
    if mouseX >= resetX and mouseX < resetX + size then
        return RESET_ACTION
    end
    return nil
end

--- Returns the translated description of the action whose icon lies under the mouse, or nil when there is none.
local function actionsTooltip(list, entry, column, mouseX)
    local action = actionAt(list, entry, column, mouseX)
    return action and getText(action.tooltipKey)
end

--- Asks for confirmation of the action whose icon lies under the mouse; returns true when an icon was clicked.
local function clickActionsCell(list, entry, column, mouseX)
    local action = actionAt(list, entry, column, mouseX)
    if not action then
        return false
    end
    list.parent:confirmAction(action, entry)
    return true
end

local COLUMN_KINDS = {
    text = { draw = drawTextCell },
    alert = { draw = drawAlertCell, tooltip = alertTooltip },
    actions = { draw = drawActionsCell, click = clickActionsCell, tooltip = actionsTooltip },
}

--- Draws one table row: its background, then every cell with the renderer of its column kind and the column borders.
function InventoryDoctorItemList:doDrawItem(y, item, alt)
    local scrollY = self:getYScroll()
    if (y + scrollY + item.height < 0) or (y + scrollY >= self.height) then
        return y + item.height
    end
    local width = self:getWidth()
    if self.selected == item.index then
        self:drawSelection(0, y, width, item.height - 1)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, width, item.height - 1)
    end
    self:drawRectBorder(0, y, width, item.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    for _, column in ipairs(self.tableColumns) do
        COLUMN_KINDS[column.kind].draw(self, item.item, column, y, item.height)
        self:drawRect(column.x + column.width - 1, y, 1, item.height, 0.3, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    end
    return y + item.height
end

--- Lets the column under the mouse handle the click, otherwise selects the row.
function InventoryDoctorItemList:onMouseDown(x, y)
    local item = self.items[self:rowAt(x, y)]
    local _, column = InventoryDoctorTableHeader.findColumnAt(self.tableColumns, x)
    local click = column and COLUMN_KINDS[column.kind].click
    if item and click and click(self, item.item, column, x) then
        return
    end
    ISScrollingListBox.onMouseDown(self, x, y)
end

--- Outlines the world element holding the item under the mouse and removes the outline from the previously outlined one.
function InventoryDoctorItemList:prerender()
    ISScrollingListBox.prerender(self)
    local hovered = nil
    if self:isMouseOver() and not self:isMouseOverScrollBar() then
        local row = self.items[self.mouseoverselected]
        hovered = row and row.item
    end
    if hovered == self.hoveredEntry then
        return
    end
    self.hoveredEntry = hovered
    self:clearOutline()
    local resolved = hovered and hovered.source and InventoryDoctor.resolveSource(hovered.source)
    if resolved then
        setOutline(resolved.owner, self.playerNum, true)
        self.outlinedElement = resolved.owner
    end
end

--- Shows as a tooltip the text that the column under the mouse gives for the hovered row, when its kind provides one.
function InventoryDoctorItemList:updateTooltip()
    if self.tooltipItem then
        self.tooltipItem.tooltip = nil
        self.tooltipItem = nil
    end
    local mouseX = self:getMouseX()
    local _, column = InventoryDoctorTableHeader.findColumnAt(self.tableColumns, mouseX)
    local tooltipOf = column and COLUMN_KINDS[column.kind].tooltip
    local item = tooltipOf and self.items[self:rowAt(mouseX, self:getMouseY())]
    if item then
        item.tooltip = tooltipOf(self, item.item, column, mouseX)
        self.tooltipItem = item
    end
    ISScrollingListBox.updateTooltip(self)
end

--- Removes the outline from the currently outlined world element.
function InventoryDoctorItemList:clearOutline()
    if self.outlinedElement then
        setOutline(self.outlinedElement, self.playerNum, false)
        self.outlinedElement = nil
    end
end

--- Creates the item table for the player, laid out along the given columns.
function InventoryDoctorItemList:new(x, y, width, height, playerObj, columns)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.tableColumns = columns
    o.playerNum = playerObj:getPlayerNum()
    o.drawBorder = true
    o.deleteTexture = InventoryDoctor.getModTexture(DELETE_TEXTURE)
    o.resetTexture = InventoryDoctor.getModTexture(RESET_TEXTURE)
    o.alertTexture = InventoryDoctor.getModTexture(ALERT_TEXTURE)
    return o
end

InventoryDoctorWindow = ISCollapsableWindow:derive("InventoryDoctorWindow")

--- Returns the translated display name of the item type, or the type itself when no item script has it.
local function itemName(fullType)
    local script = fullType and getScriptManager():FindItem(fullType)
    return script and script:getDisplayName() or tostring(fullType)
end

--- Returns true when the item type has no script or its script has no icon of its own.
local function isIconMissing(fullType)
    local script = fullType and getScriptManager():FindItem(fullType)
    local texture = script and script:getNormalTexture()
    return texture == nil or texture == getTexture(MISSING_ICON_TEXTURE)
end

local SOURCE_LABELS = {
    [InventoryDoctor.SOURCE_PLAYER] = function(source)
        return tostring(source.key)
    end,
    [InventoryDoctor.SOURCE_OBJECT] = function(source)
        return getText("IGUI_ContainerTitle_" .. tostring(source.containerType))
    end,
    [InventoryDoctor.SOURCE_FLOOR] = function(_source)
        return getText("IGUI_ContainerTitle_floor")
    end,
    [InventoryDoctor.SOURCE_CORPSE] = function(source)
        return getText("IGUI_ContainerTitle_" .. tostring(source.containerType))
    end,
    [InventoryDoctor.SOURCE_VEHICLE] = function(source)
        return getText("IGUI_VehiclePart" .. tostring(source.containerType))
    end,
}

--- Returns the translated name of the top container of the source.
local function sourceLabel(source)
    local label = source and SOURCE_LABELS[source.kind]
    return label and label(source) or "?"
end

--- Returns the container path of the row: the top container followed by the names of the bags holding the item.
local function containerPath(source, row)
    local parts = { sourceLabel(source) }
    if type(row.path) == "table" then
        for _, fullType in ipairs(row.path) do
            table.insert(parts, itemName(fullType))
        end
    end
    return table.concat(parts, PATH_SEPARATOR)
end

--- Marks the given cell of the row as a warning and records the translation key explaining why.
local function addWarning(entry, field, reasonKey)
    entry.warnings[field] = true
    table.insert(entry.alertReasons, reasonKey)
end

--- Marks the row with a red alert when it has warnings, and builds the tooltip listing their explanations one per line.
local function applyAlert(entry)
    if #entry.alertReasons == 0 then
        return
    end
    entry.alert = ALERT_MARK
    local lines = {}
    for _, reasonKey in ipairs(entry.alertReasons) do
        table.insert(lines, getText(reasonKey))
    end
    entry.alertTooltip = table.concat(lines, " <LINE> ")
end

--- Returns the condition of the row as current over maximum, or a dash when it could not be read.
local function formatCondition(row)
    if not row.condition or not row.conditionMax then
        return "-"
    end
    return string.format("%d / %d", row.condition, row.conditionMax)
end

--- Returns the weight of the row with two decimals, or a dash when it could not be read.
local function formatWeight(row)
    if not row.weight then
        return "-"
    end
    return string.format("%.2f", row.weight)
end

--- Returns the number the row sorts by for the given value, placing rows whose value could not be read first.
local function numericSortKey(value)
    if type(value) ~= "number" then
        return -math.huge
    end
    return value
end

--- Returns the table row for an item description of the given source, flagging a condition below 0, a negative weight, an item without icon and an item that threw errors, editable when allowed and the item has an id.
local function buildEntry(row, source, canEdit)
    local entry = {
        row = row,
        source = source,
        square = source and string.format("%d, %d", source.x, source.y) or "-",
        squareSortKey = source and string.format("%09d %09d", source.x, source.y) or "",
        container = containerPath(source, row),
        name = itemName(row.fullType),
        item = tostring(row.fullType),
        condition = formatCondition(row),
        conditionSortKey = numericSortKey(row.condition),
        weight = formatWeight(row),
        weightSortKey = numericSortKey(row.weight),
        canEdit = canEdit and source ~= nil and InventoryDoctor.isInteger(row.id),
        alert = "",
        alertReasons = {},
        warnings = {},
        fitted = {},
    }
    if type(row.condition) == "number" and row.condition < 0 then
        addWarning(entry, "condition", "UI_InventoryDoctor_AlertNegativeCondition")
    end
    if row.negativeWeight then
        addWarning(entry, "weight", "UI_InventoryDoctor_AlertNegativeWeight")
    end
    if isIconMissing(row.fullType) then
        addWarning(entry, "name", "UI_InventoryDoctor_AlertIcon")
    end
    if row.failed then
        addWarning(entry, "item", "UI_InventoryDoctor_AlertErrors")
    end
    applyAlert(entry)
    return entry
end

--- Builds a fake flagged row on the zone center, carrying every alert, with no source and no action.
local function buildTestEntry(x, y)
    local entry = buildEntry({
        fullType = "InventoryDoctor.Test",
        condition = -1,
        conditionMax = 10,
        weight = -1,
        negativeWeight = true,
        failed = true,
    }, nil, false)
    entry.square = string.format("%d, %d", x, y)
    entry.container = "InventoryDoctorTest"
    entry.name = "Inventory Doctor test"
    return entry
end

--- Returns a text summing up every field of the zone description, equal for two identical zones.
local function signatureOf(sources, rows)
    local parts = {}
    for _, source in ipairs(sources) do
        table.insert(parts, table.concat({ tostring(source.kind), tostring(source.x), tostring(source.y), tostring(source.index), tostring(source.key), tostring(source.containerIndex), tostring(source.partIndex) }, "|"))
    end
    for _, row in ipairs(rows) do
        local path = type(row.path) == "table" and table.concat(row.path, ">") or ""
        table.insert(parts, table.concat({
            tostring(row.source), tostring(row.id), tostring(row.fullType), path, tostring(row.condition), tostring(row.conditionMax),
            tostring(row.failed), tostring(row.equipped), tostring(row.holdsItems), tostring(row.hasFluid),
            tostring(row.weight), tostring(row.negativeWeight),
        }, "|"))
    end
    return table.concat(parts, "\n")
end

--- Returns the key the entry sorts by for the field: the number itself for a numeric field, the lowercase text otherwise.
local function sortKeyOf(entry, field)
    local value = entry[field]
    if type(value) == "number" then
        return value
    end
    return string.lower(tostring(value))
end

--- Sorts the rows by the value of the given field, in the given direction, keeping the scan order between equal rows.
local function sortEntries(entries, field, ascending)
    if not field then
        return
    end
    for i, entry in ipairs(entries) do
        entry.order = i
        entry.sortKey = sortKeyOf(entry, field)
    end
    table.sort(entries, function(a, b)
        if a.sortKey == b.sortKey then
            return a.order < b.order
        end
        if ascending then
            return a.sortKey < b.sortKey
        end
        return a.sortKey > b.sortKey
    end)
end

--- Returns true when the position has left the tile starting at the given coordinate by more than the change margin.
local function hasLeftTile(position, tileStart)
    return position < tileStart - TILE_CHANGE_MARGIN or position >= tileStart + 1 + TILE_CHANGE_MARGIN
end

--- Returns true when the player has clearly moved onto another square since the zone was centered, ignoring small moves around a square border.
function InventoryDoctorWindow:hasPlayerChangedTile()
    local player = self.playerObj
    if math.floor(player:getZ()) ~= self.centerZ then
        return true
    end
    return hasLeftTile(player:getX(), self.centerX) or hasLeftTile(player:getY(), self.centerY)
end

--- Centers the scanned zone on the square the player stands on and moves the zone outline onto it, creating the outline the first time.
function InventoryDoctorWindow:centerOnPlayer()
    local player = self.playerObj
    self.centerX, self.centerY, self.centerZ = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local x, y = self.centerX - 1, self.centerY - 1
    if self.zoneOutline then
        self.zoneOutline:setArea(x, y, self.centerZ, 3, 3)
    else
        self.zoneOutline = InventoryDoctorTileOutline.create(player:getPlayerNum(), x, y, self.centerZ, 3, 3)
    end
end

--- Asks for the contents of the zone now.
function InventoryDoctorWindow:requestZone()
    self.nextRequestMs = getTimestampMs() + REFRESH_INTERVAL_MS
    InventoryDoctorClientActions.requestZone(self.playerObj, self.centerX, self.centerY, self.centerZ)
end

--- Rebuilds the table from the zone description when it is the current zone and its contents changed.
function InventoryDoctorWindow:onZone(x, y, z, sources, rows)
    if x ~= self.centerX or y ~= self.centerY or z ~= self.centerZ then
        return
    end
    local signature = signatureOf(sources, rows)
    if signature == self.signature then
        return
    end
    self.signature = signature
    local canEdit = InventoryDoctor.canDelete(self.playerObj)
    self.entries = {}
    for _, row in ipairs(rows) do
        table.insert(self.entries, buildEntry(row, sources[row.source], canEdit))
    end
    self:showEntries()
end

--- Shows the rows sorted as the header asks, with the test row first in the development build.
function InventoryDoctorWindow:showEntries()
    self.list:clearOutline()
    self.list.hoveredEntry = nil
    self.list:clear()
    local entries = {}
    for i, entry in ipairs(self.entries) do
        entries[i] = entry
    end
    local field, ascending = self.header:getSort()
    sortEntries(entries, field, ascending)
    if InventoryDoctor.isDevBuild() then
        table.insert(entries, 1, buildTestEntry(self.centerX, self.centerY))
    end
    for _, entry in ipairs(entries) do
        self.list:addItem("", entry)
    end
end

--- Asks the player to confirm the action on the row, then requests it for the item of the current zone.
function InventoryDoctorWindow:confirmAction(action, entry)
    InventoryDoctorConfirm.show(self.playerObj:getPlayerNum(), action.confirmKey, entry, function()
        InventoryDoctorClientActions.requestItemCommand(self.playerObj, action.command, self.centerX, self.centerY, self.centerZ, entry.source, entry.row.id)
    end)
end

--- Recenters the zone and asks for its contents as soon as the player moves onto another square, and asks for them again at a regular interval.
function InventoryDoctorWindow:prerender()
    ISCollapsableWindow.prerender(self)
    if self:hasPlayerChangedTile() then
        self:centerOnPlayer()
        self.signature = nil
        self.entries = {}
        self:showEntries()
        self:requestZone()
        return
    end
    if getTimestampMs() >= self.nextRequestMs then
        self:requestZone()
    end
end

--- Keeps the window permanently expanded without collapse or pin buttons, then creates the sortable and resizable table header, the item table and the zone outline, and asks for the contents of the zone.
function InventoryDoctorWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.pin = true
    self.collapseButton:setVisible(false)
    self.pinButton:setVisible(false)
    local columns = createColumns()
    local headerHeight = getTextManager():getFontHeight(UIFont.Small) + 6
    local headerTop = self:titleBarHeight() + PADDING
    self.header = InventoryDoctorTableHeader:new(PADDING, headerTop, self.width - PADDING * 2, headerHeight, columns, function()
        self:showEntries()
    end)
    self.header:initialise()
    self.header:setAnchorRight(true)
    self:addChild(self.header)
    local top = headerTop + headerHeight
    self.list = InventoryDoctorItemList:new(PADDING, top, self.width - PADDING * 2, self.height - top - PADDING, self.playerObj, columns)
    self.list:initialise()
    self.list:instantiate()
    self.list:setFont(UIFont.Small, 2)
    self.list:setAnchorRight(true)
    self.list:setAnchorBottom(true)
    self:addChild(self.list)
    InventoryDoctorClientActions.addListener(self)
    self:centerOnPlayer()
    self:showEntries()
    self:requestZone()
end

--- Stops listening for zone descriptions, removes the element and zone outlines and any open tooltip, then closes the window.
function InventoryDoctorWindow:close()
    InventoryDoctorClientActions.removeListener(self)
    self.list:clearOutline()
    if self.list.tooltipUI then
        self.list.tooltipUI:removeFromUIManager()
    end
    self.zoneOutline:remove()
    self:setVisible(false)
    self:removeFromUIManager()
end

--- Creates the window following the player.
function InventoryDoctorWindow:new(playerObj)
    local o = ISCollapsableWindow.new(self, 0, 0, getTableWidth() + PADDING * 2 + SCROLLBAR_ALLOWANCE, WINDOW_HEIGHT)
    o.playerObj = playerObj
    o.entries = {}
    o.signature = nil
    o.nextRequestMs = 0
    o:setTitle(TITLE)
    o:setResizable(true)
    return o
end

--- Opens the window following the player, centered on the player's screen.
function InventoryDoctorWindow.open(playerObj)
    local window = InventoryDoctorWindow:new(playerObj)
    window:initialise()
    window:centerOnScreen(playerObj:getPlayerNum())
    window:addToUIManager()
end
