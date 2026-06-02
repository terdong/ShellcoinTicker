-- UI.lua
-- HUD Layout, Frame Creation, and Updates for ShellcoinTicker (Vanilla WoW 1.12)

ShellcoinTicker.UI = {
    frame = nil,
    priceText = nil,
    trendText = nil,
    holdingsText = nil,
    valueText = nil,
    newsText = nil
}

function ShellcoinTicker.UI:CreateMainFrame()
    if self.frame then return end
    
    -- Main container frame
    local frame = CreateFrame("Frame", "ShellcoinTickerFrame", UIParent)
    frame:SetWidth(260)
    frame:SetHeight(150)
    
    -- Set position from SavedVariables or default to center
    if ShellcoinTickerDB and ShellcoinTickerDB.x and ShellcoinTickerDB.y then
        frame:SetPoint(ShellcoinTickerDB.point or "CENTER", UIParent, ShellcoinTickerDB.point or "CENTER", ShellcoinTickerDB.x, ShellcoinTickerDB.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    -- Frame settings
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    
    -- Sleek background backdrop configuration
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85) -- semi-transparent pitch black
    frame:SetBackdropBorderColor(0.8, 0.6, 0.0, 0.8) -- luxurious gold border
    
    -- Dragging functionality (using 1.12 'this' global reference inside scripts)
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = this:GetPoint()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.point = point
            ShellcoinTickerDB.x = xOfs
            ShellcoinTickerDB.y = yOfs
        end
    end)
    
    -- Title label
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -8)
    titleText:SetText("|cffffd700🐢 Shellcoin Ticker (SHELL)|r")
    
    -- Close button (uses standard Blizzard UI assets)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.isShown = false
        end
        frame:Hide()
    end)
    
    -- Price Display
    local priceText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    priceText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -26)
    self.priceText = priceText
    
    -- Sparkline/Trend Indicator
    local trendText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trendText:SetPoint("TOPLEFT", priceText, "BOTTOMLEFT", 0, -4)
    self.trendText = trendText
    
    -- Sleek separator line
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(236)
    line:SetPoint("TOPLEFT", trendText, "BOTTOMLEFT", 0, -6)
    line:SetTexture(0.8, 0.6, 0.0, 0.3) -- transparent golden divider line
    
    -- Holdings Counter
    local holdingsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holdingsText:SetPoint("TOPLEFT", trendText, "BOTTOMLEFT", 0, -14)
    self.holdingsText = holdingsText
    
    -- Holdings Net Value
    local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("TOPLEFT", holdingsText, "BOTTOMLEFT", 0, -4)
    self.valueText = valueText
    
    -- News Feed Label
    local newsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newsText:SetPoint("TOPLEFT", valueText, "BOTTOMLEFT", 0, -8)
    newsText:SetWidth(236)
    newsText:SetHeight(24)
    newsText:SetJustifyH("LEFT")
    newsText:SetJustifyV("TOP")
    self.newsText = newsText
    
    self.frame = frame
    
    -- Setup OnUpdate script for time accumulators (efficiently updates price and scans bags)
    local timeSinceSimUpdate = 0
    local timeSinceBagScan = 0
    
    frame:SetScript("OnUpdate", function()
        local elapsed = arg1 -- 1.12 passes elapsed time in global arg1
        if not elapsed then return end
        
        -- Throttled inventory scan
        timeSinceBagScan = timeSinceBagScan + elapsed
        if timeSinceBagScan >= 1.0 then
            timeSinceBagScan = 0
            if ShellcoinTicker.scanPending then
                ShellcoinTicker:ScanBags()
                ShellcoinTicker.scanPending = false
                ShellcoinTicker.UI:UpdateDisplay()
            end
        end
        
        -- Throttled price fluctuation update (every 15 seconds)
        timeSinceSimUpdate = timeSinceSimUpdate + elapsed
        if timeSinceSimUpdate >= 15.0 then
            timeSinceSimUpdate = 0
            ShellcoinTicker:UpdateSimulation()
        end
    end)
    
    -- Apply initial visibility
    if ShellcoinTickerDB and ShellcoinTickerDB.isShown == false then
        frame:Hide()
    else
        frame:Show()
    end
    
    -- Initial update
    self:UpdateDisplay()
end

function ShellcoinTicker.UI:UpdateDisplay()
    if not self.frame or not ShellcoinTickerDB then return end
    
    local price = ShellcoinTickerDB.price or 100000
    local change = ShellcoinTickerDB.change or 0
    
    -- Format price and change
    local priceStr = ShellcoinTicker:FormatMoney(price)
    local changeSign = "+"
    local changeColor = "|cff00ff00" -- green
    if change < 0 then
        changeSign = ""
        changeColor = "|cffff0000" -- red
    elseif change == 0 then
        changeColor = "|cff888888" -- gray
    end
    
    local changeStr = changeColor .. changeSign .. string.format("%.1f%%", change * 100) .. "|r"
    self.priceText:SetText("Price: " .. priceStr .. " (" .. changeStr .. ")")
    
    -- Build trend sparkline using safe characters
    local trendStr = "Trend: "
    local history = ShellcoinTickerDB.history
    if history and table.getn(history) > 1 then
        for i = 2, table.getn(history) do
            local prev = history[i-1]
            local curr = history[i]
            if curr > prev then
                trendStr = trendStr .. " |cff00ff00^|r"
            elseif curr < prev then
                trendStr = trendStr .. " |cffff0000v|r"
            else
                trendStr = trendStr .. " |cff888888-|r"
            end
        end
    else
        trendStr = trendStr .. "|cff888888No data|r"
    end
    self.trendText:SetText(trendStr)
    
    -- Format holdings
    local auth = ShellcoinTicker.authenticCount or 0
    local fake = ShellcoinTicker.counterfeitCount or 0
    self.holdingsText:SetText("HODL: |cffffffff" .. auth .. "|r Auth | |cff9d9d9d" .. fake .. "|r Counterfeit")
    
    -- Calculate total value (only authentic counts, counterfeit is worthless grey junk)
    local totalValue = auth * price
    local totalValueStr = ShellcoinTicker:FormatMoney(totalValue)
    if fake > 0 then
        totalValueStr = totalValueStr .. " (|cff9d9d9d" .. fake .. " fake worthless|r)"
    end
    self.valueText:SetText("Net Worth: " .. totalValueStr)
    
    -- Update news feed
    self.newsText:SetText("|cffffd700Feed:|r " .. (ShellcoinTicker.lastEventMsg or "HODL!"))
end
