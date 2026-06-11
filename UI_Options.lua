-- UI_Options.lua
-- Options UI and Popup Management for ShellcoinTicker (Vanilla WoW 1.12)

StaticPopupDialogs["SHELLCOINTICKER_CONFIRM_CLEAR"] = {
    text = "Are you sure you want to clear your transaction history?\nThis will reset your cost basis.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        ShellcoinTickerDB.transactions = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Transaction history cleared!|r")
        if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
            ShellcoinTicker.UI:UpdateDisplay()
        end
        if ShellcoinTicker.UI.RefreshOptionsUI then
            ShellcoinTicker.UI:RefreshOptionsUI()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["SHELLCOINTICKER_CONFIRM_RESET"] = {
    text = "Are you sure you want to perform a full reset?\nThis will wipe all prices, history, transactions, and settings.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        ShellcoinTicker:ResetAll()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function ShellcoinTicker.UI:ToggleOptionsFrame()
    if not self.optionsFrame then
        self:CreateOptionsFrame()
    end
    if self.optionsFrame:IsShown() then
        self.optionsFrame:Hide()
    else
        self.optionsFrame:Show()
    end
end

function ShellcoinTicker.UI:CreateOptionsFrame()
    if self.optionsFrame then return end
    
    -- Main Container (480 width, 260 height for clean two-column layout)
    local f = CreateFrame("Frame", "ShellcoinTickerOptionsFrame", UIParent)
    f:Hide()
    f:SetWidth(480)
    f:SetHeight(300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- Backdrop (premium dark gray / neon theme)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0.65, 1, 0.8)
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Shellcoin Ticker Options")
    title:SetTextColor(0, 0.65, 1)
    
    -- Close Button (X)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)
    
    -- Helper to create checkboxes with custom xOffset
    local function CreateCheckButton(name, text, xOffset, yOffset, onClick)
        local cb = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", xOffset, yOffset)
        cb:SetWidth(24)
        cb:SetHeight(24)
        
        local fs = getglobal(cb:GetName() .. "Text")
        if fs then
            fs:SetText(text)
            fs:SetTextColor(0.8, 0.8, 0.8)
        else
            fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetText(text)
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        end
        
        cb:SetScript("OnClick", onClick)
        return cb
    end
    
    -- LEFT COLUMN (General Settings)
    
    -- 1. HUD Toggle Checkbox
    CreateCheckButton("ShellcoinTickerOptionsFrameHUDToggle", "Show HUD Frame", 16, -36, function()
        ShellcoinTickerDB.isShown = this:GetChecked() and true or false
        if ShellcoinTickerDB.isShown then
            ShellcoinTicker.UI.frame:Show()
        else
            ShellcoinTicker.UI.frame:Hide()
        end
    end)
    
    -- 2. Minimap Toggle Checkbox
    CreateCheckButton("ShellcoinTickerOptionsFrameMinimapToggle", "Show Minimap Button", 16, -64, function()
        ShellcoinTickerDB.showMinimapButton = this:GetChecked() and true or false
        ShellcoinTicker.UI:UpdateMinimapButton()
    end)
    
    -- 3. Graph Style selection
    local graphLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -96)
    graphLabel:SetText("Graph Style:")
    graphLabel:SetTextColor(1, 0.82, 0)
    
    local function CreateStyleButton(text, mode, xOfs)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(75)
        btn:SetHeight(20)
        btn:SetPoint("LEFT", graphLabel, "RIGHT", xOfs, 0)
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            ShellcoinTickerDB.graphMode = mode
            ShellcoinTicker.UI:UpdateDisplay()
            ShellcoinTicker.UI:RefreshOptionsUI()
        end)
        return btn
    end
    
    local areaBtn = CreateStyleButton("Area", "area", 10)
    local candleBtn = CreateStyleButton("Candle", "candle", 90)
    
    f.areaBtn = areaBtn
    f.candleBtn = candleBtn
    
    -- 4. Scale Slider
    local scaleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -128)
    scaleLabel:SetText("HUD Scale (0.50 - 1.50):")
    scaleLabel:SetTextColor(1, 0.82, 0)
    
    local slider = CreateFrame("Slider", "ShellcoinTickerOptionsFrameScaleSlider", f, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -8)
    slider:SetWidth(170)
    slider:SetHeight(16)
    slider:SetMinMaxValues(0.5, 1.5)
    slider:SetValueStep(0.05)
    
    getglobal(slider:GetName() .. "Low"):SetText("0.5")
    getglobal(slider:GetName() .. "High"):SetText("1.5")
    
    local eb = CreateFrame("EditBox", "ShellcoinTickerOptionsFrameScaleEditBox", f, "InputBoxTemplate")
    eb:SetPoint("LEFT", slider, "RIGHT", 25, 0)
    eb:SetWidth(45)
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(4)
    
    slider:SetScript("OnValueChanged", function()
        local val = math.floor(this:GetValue() * 100 + 0.5) / 100
        ShellcoinTickerDB.hudScale = val
        if ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:SetScale(val)
        end
        local currentText = eb:GetText()
        local valStr = string.format("%.2f", val)
        if currentText ~= valStr then
            eb:SetText(valStr)
        end
    end)
    
    eb:SetScript("OnEnterPressed", function()
        local val = tonumber(this:GetText())
        if val then
            val = math.max(0.5, math.min(1.5, val))
            ShellcoinTickerDB.hudScale = val
            if ShellcoinTicker.UI.frame then
                ShellcoinTicker.UI.frame:SetScale(val)
            end
            slider:SetValue(val)
            this:SetText(string.format("%.2f", val))
        else
            this:SetText(string.format("%.2f", ShellcoinTickerDB.hudScale or 1.0))
        end
        this:ClearFocus()
    end)
    
    eb:SetScript("OnEscapePressed", function()
        this:SetText(string.format("%.2f", ShellcoinTickerDB.hudScale or 1.0))
        this:ClearFocus()
    end)
    
    -- 5. Auto Price Sync selection
    local syncLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -190)
    syncLabel:SetText("Auto Sync:")
    syncLabel:SetTextColor(1, 0.82, 0)
    
    local function CreateSyncButton(text, interval, parent, anchorTo, xOfs)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(40)
        btn:SetHeight(20)
        btn:SetPoint("LEFT", parent, anchorTo, xOfs, 0)
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            ShellcoinTickerDB.syncInterval = interval
            ShellcoinTicker.UI:RefreshOptionsUI()
        end)
        return btn
    end
    
    f.syncOffBtn = CreateSyncButton("Off", 0, syncLabel, "RIGHT", 8)
    f.sync10mBtn = CreateSyncButton("10M", 600, f.syncOffBtn, "RIGHT", 5)
    f.sync30mBtn = CreateSyncButton("30M", 1800, f.sync10mBtn, "RIGHT", 5)
    f.sync1hBtn = CreateSyncButton("1H", 3600, f.sync30mBtn, "RIGHT", 5)
    
    -- RIGHT COLUMN (HUD Component Visibility Settings)
    local hudVisibilityTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hudVisibilityTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 280, -36)
    hudVisibilityTitle:SetText("HUD Component Visibility")
    hudVisibilityTitle:SetTextColor(0, 0.65, 1)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowFinancials", "Financials (Invested & P/L)", 280, -60, function()
        ShellcoinTickerDB.showFinancials = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowPriceTrend", "Price & Trend Sparkline", 280, -84, function()
        ShellcoinTickerDB.showPriceTrend = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowTimeframe", "Timeframe Buttons", 280, -108, function()
        ShellcoinTickerDB.showTimeframe = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowChart", "Graph Chart", 280, -132, function()
        ShellcoinTickerDB.showChart = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowHoldings", "Holdings & Net Worth", 280, -156, function()
        ShellcoinTickerDB.showHoldings = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    CreateCheckButton("ShellcoinTickerOptionsFrameShowFeed", "News Feed", 280, -180, function()
        ShellcoinTickerDB.showFeed = this:GetChecked() and true or false
        ShellcoinTicker.UI:LayoutHUD()
        ShellcoinTicker.UI:UpdateDisplay()
    end)
    
    -- BOTTOM Action Buttons
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetWidth(120)
    clearBtn:SetHeight(22)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    clearBtn:SetText("Clear History")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("SHELLCOINTICKER_CONFIRM_CLEAR")
    end)
    
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetWidth(120)
    resetBtn:SetHeight(22)
    resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    resetBtn:SetText("Reset Addon")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("SHELLCOINTICKER_CONFIRM_RESET")
    end)
    
    -- Update fields on show
    f:SetScript("OnShow", function()
        ShellcoinTicker.UI:RefreshOptionsUI()
    end)
    
    self.optionsFrame = f
    self:RefreshOptionsUI()
end

function ShellcoinTicker.UI:RefreshOptionsUI()
    local f = self.optionsFrame
    if not f then return end
    
    -- Checkboxes
    local hudToggle = getglobal("ShellcoinTickerOptionsFrameHUDToggle")
    local minimapToggle = getglobal("ShellcoinTickerOptionsFrameMinimapToggle")
    
    if hudToggle then hudToggle:SetChecked(ShellcoinTickerDB.isShown and 1 or nil) end
    if minimapToggle then minimapToggle:SetChecked(ShellcoinTickerDB.showMinimapButton and 1 or nil) end
    
    -- 6 visibility toggles
    local showFinToggle = getglobal("ShellcoinTickerOptionsFrameShowFinancials")
    local showPriceToggle = getglobal("ShellcoinTickerOptionsFrameShowPriceTrend")
    local showTFToggle = getglobal("ShellcoinTickerOptionsFrameShowTimeframe")
    local showChartToggle = getglobal("ShellcoinTickerOptionsFrameShowChart")
    local showHoldToggle = getglobal("ShellcoinTickerOptionsFrameShowHoldings")
    local showFeedToggle = getglobal("ShellcoinTickerOptionsFrameShowFeed")
    
    if showFinToggle then showFinToggle:SetChecked((ShellcoinTickerDB.showFinancials ~= false) and 1 or nil) end
    if showPriceToggle then showPriceToggle:SetChecked((ShellcoinTickerDB.showPriceTrend ~= false) and 1 or nil) end
    if showTFToggle then showTFToggle:SetChecked((ShellcoinTickerDB.showTimeframe ~= false) and 1 or nil) end
    if showChartToggle then showChartToggle:SetChecked((ShellcoinTickerDB.showChart ~= false) and 1 or nil) end
    if showHoldToggle then showHoldToggle:SetChecked((ShellcoinTickerDB.showHoldings ~= false) and 1 or nil) end
    if showFeedToggle then showFeedToggle:SetChecked((ShellcoinTickerDB.showFeed ~= false) and 1 or nil) end
    
    -- Graph Style Lock Highlight
    if ShellcoinTickerDB.graphMode == "candle" then
        if f.candleBtn then f.candleBtn:LockHighlight() end
        if f.areaBtn then f.areaBtn:UnlockHighlight() end
    else
        if f.areaBtn then f.areaBtn:LockHighlight() end
        if f.candleBtn then f.candleBtn:UnlockHighlight() end
    end
    
    -- Sync Interval Lock Highlight
    local interval = ShellcoinTickerDB.syncInterval or 600
    if f.syncOffBtn then f.syncOffBtn:UnlockHighlight() end
    if f.sync10mBtn then f.sync10mBtn:UnlockHighlight() end
    if f.sync30mBtn then f.sync30mBtn:UnlockHighlight() end
    if f.sync1hBtn then f.sync1hBtn:UnlockHighlight() end
    
    if interval == 0 then
        if f.syncOffBtn then f.syncOffBtn:LockHighlight() end
    elseif interval == 600 then
        if f.sync10mBtn then f.sync10mBtn:LockHighlight() end
    elseif interval == 1800 then
        if f.sync30mBtn then f.sync30mBtn:LockHighlight() end
    elseif interval == 3600 then
        if f.sync1hBtn then f.sync1hBtn:LockHighlight() end
    end
    
    -- Slider & EditBox
    local scale = ShellcoinTickerDB.hudScale or 1.0
    local slider = getglobal("ShellcoinTickerOptionsFrameScaleSlider")
    local eb = getglobal("ShellcoinTickerOptionsFrameScaleEditBox")
    
    if slider then slider:SetValue(scale) end
    if eb then eb:SetText(string.format("%.2f", scale)) end
end
