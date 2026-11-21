-- Native AuraContainer approach from ClassicNameplatesPlus 1.0.14 (Wurmschwanz).
-- The client matches auras and controls icon visibility; Lua never reads them.
local DEBUFFS = {
    { key = "wisdom", name = "Judgement of Wisdom",
        ids = { [20186] = true, [20354] = true, [20355] = true } },
    { key = "crusader", name = "Judgement of the Crusader",
        ids = { [21183] = true, [20188] = true, [20300] = true, [20301] = true,
            [20302] = true, [20303] = true, [20304] = true, [20305] = true } },
}
local SIZE = 22
local GAP = 3
-- Non-self casts. This does not restrict the caster to party members.
local FILTER = "HARMFUL|!PLAYER|!CROWD_CONTROL"
local byPlate, byUnit = {}, {}
local lastError, reportedError

local function Settings()
    if type(WisdomTrackerDB) ~= "table" then WisdomTrackerDB = {} end
    for _, debuff in ipairs(DEBUFFS) do
        if type(WisdomTrackerDB[debuff.key]) ~= "boolean" then
            WisdomTrackerDB[debuff.key] = true
        end
    end
    if WisdomTrackerDB.position ~= "left" and WisdomTrackerDB.position ~= "right" then
        WisdomTrackerDB.position = "left"
    end
    return WisdomTrackerDB
end

local function Candidates(debuff)
    return { includeSpellIDs = Settings()[debuff.key] and debuff.ids or {} }
end

local function ReportError(message)
    lastError = message
    if not reportedError then
        reportedError = true
        print("|cffffcc00WisdomTracker:|r " .. message .. " Use /wisdomtracker for status.")
    end
end

local function IsSecret(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return true end
    if type(issecret) == "function" and issecret(value) then return true end
    return false
end

local function IsUnit(unit)
    return not IsSecret(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function InitializeButton(button)
    button:SetSize(SIZE, SIZE)
    button:EnableMouse(false)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetIcon(icon)
end

local function Position(entry)
    local frame = entry.plate.UnitFrame
    -- Anchor directly to the visible health bar, not the larger plate bounds.
    -- Early NAME_PLATE_CREATED events can arrive before the health bar exists.
    local anchor = frame and (frame.healthBar or frame.HealthBarsContainer or frame) or entry.plate
    local side = Settings().position
    if entry.anchor == anchor and entry.side == side then return end
    entry.container:ClearAllPoints()
    if side == "left" then
        entry.container:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
    else
        entry.container:SetPoint("LEFT", anchor, "RIGHT", GAP, 0)
    end
    entry.anchor, entry.side = anchor, side
end

local function Prepare(plate)
    if byPlate[plate] then return byPlate[plate] end
    local container
    local ok, err = pcall(function()
        container = CreateFrame("AuraContainer", nil, plate, "CustomAuraContainerTemplate")
        -- A renderable starting rectangle avoids empty initial layouts.
        container:SetSize(SIZE, SIZE)
        if container.SetFlowLayoutAnchorPoint then
            container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
        end
        for _, debuff in ipairs(DEBUFFS) do
            -- One group per spell family keeps one icon per judgement.
            container:AddAuraGroup(debuff.key, FILTER, {
                maxFrameCount = 1,
                candidateFilters = Candidates(debuff),
                initializeFrame = InitializeButton,
                layout = { elementWidth = SIZE, elementHeight = SIZE,
                    elementSpacing = GAP, groupSpacing = GAP, lineSpacing = 0 },
            })
        end
        container:Hide()
    end)
    if not ok then
        if container then pcall(container.Hide, container) end
        ReportError("Native judgement display unavailable: " .. tostring(err))
        return nil
    end
    local entry = { container = container, plate = plate }
    local positioned, positionError = pcall(Position, entry)
    if not positioned then
        ReportError("Could not position judgement display: " .. tostring(positionError))
        return nil
    end
    byPlate[plate] = entry
    return entry
end

local function Detach(unit)
    local entry = byUnit[unit]
    byUnit[unit] = nil
    if not entry or entry.unit ~= unit then return end
    entry.unit = nil
    -- Keep our own reference; plate lookup can fail after unit removal.
    pcall(entry.container.Hide, entry.container)
    local ok, err = pcall(entry.container.SetUnit, entry.container, nil)
    if not ok then ReportError("Could not release nameplate: " .. tostring(err)) end
end

local function Attach(unit)
    if not IsUnit(unit) then return end
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        ReportError("Nameplate API unavailable on this client.")
        return
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    if plate.IsForbidden then
        local readable, forbidden = pcall(plate.IsForbidden, plate)
        if not readable or IsSecret(forbidden) or forbidden then return end
    end
    if UnitCanAttack then
        local readable, attackable = pcall(UnitCanAttack, "player", unit)
        if readable and not IsSecret(attackable) and attackable == false then
            Detach(unit)
            return
        end
    end
    if byUnit[unit] and byUnit[unit].plate ~= plate then Detach(unit) end
    local entry = Prepare(plate)
    if not entry then return end
    if entry.settingsFailed then return end
    local positioned, positionError = pcall(Position, entry)
    if not positioned then
        ReportError("Could not position judgement display: " .. tostring(positionError))
        return
    end
    if entry.unit and entry.unit ~= unit then Detach(entry.unit) end
    local bound, err = pcall(entry.container.SetUnit, entry.container, unit)
    if not bound then
        pcall(entry.container.Hide, entry.container)
        ReportError("Could not bind Wisdom display: " .. tostring(err))
        return
    end
    entry.unit, byUnit[unit] = unit, entry
    local shown, showError = pcall(entry.container.Show, entry.container)
    if not shown then ReportError("Could not show Wisdom display: " .. tostring(showError)) end
end

local function Refresh()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if IsUnit(unit) then Attach(unit) end
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "UNIT_FACTION" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_CREATED" then
        if unit and not (InCombatLockdown and InCombatLockdown()) then Prepare(unit) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if IsUnit(unit) then Detach(unit) end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_FACTION" then
        Attach(unit)
    else
        Refresh()
    end
end)

SLASH_WISDOMTRACKER1 = "/wisdomtracker"
SLASH_WISDOMTRACKER2 = "/wt"
SlashCmdList.WISDOMTRACKER = function(message)
    local key, value = (message or ""):lower():match("^%s*(%S+)%s+(%S+)%s*$")
    if key == "position" and (value == "left" or value == "right") then
        if InCombatLockdown and InCombatLockdown() then
            print("WisdomTracker: change icon position outside combat.")
            return
        end
        Settings().position = value
        for _, entry in pairs(byPlate) do
            local ok, err = pcall(Position, entry)
            if not ok then
                ReportError("Position update failed; /reload to apply saved position: " .. tostring(err))
            end
        end
        print("WisdomTracker: icons anchored to the " .. value .. ".")
        return
    end
    local selected
    for _, debuff in ipairs(DEBUFFS) do
        if debuff.key == key then selected = debuff end
    end
    if selected and (value == "on" or value == "off") then
        if InCombatLockdown and InCombatLockdown() then
            print("WisdomTracker: change tracking settings outside combat.")
            return
        end
        Settings()[key] = value == "on"
        for _, entry in pairs(byPlate) do
            local ok, err = pcall(entry.container.SetAuraGroupCandidateFilters,
                entry.container, key, Candidates(selected))
            if not ok then
                -- Avoid stale selections if this client cannot update them.
                pcall(entry.container.Hide, entry.container)
                entry.settingsFailed = true
                ReportError("Filter update failed; /reload to apply saved settings: " .. tostring(err))
            elseif entry.settingsFailed then
                -- Another group may still need rebuilding after an earlier failure.
                pcall(entry.container.Hide, entry.container)
            end
        end
        print("WisdomTracker: " .. selected.name .. " " .. value .. ".")
        return
    end
    local count = 0
    for _ in pairs(byUnit) do count = count + 1 end
    print("|cffffcc00WisdomTracker 1.4:|r " .. count .. " nameplates bound.")
    print("Position: " .. Settings().position .. " - /wt position left|right")
    for _, debuff in ipairs(DEBUFFS) do
        print(debuff.name .. ": " .. (Settings()[debuff.key] and "on" or "off"))
    end
    print("/wt wisdom on|off - /wt crusader on|off (saved per character)")
    print("Tracks other players' judgements; party-only filtering is not enabled.")
    if lastError then print("Last error: " .. lastError) end
end
