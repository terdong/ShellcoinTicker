-- Core.lua
-- Addon Core Logic & Market Simulation for ShellcoinTicker (Vanilla WoW 1.12)

ShellcoinTicker = {
    -- State variables
    authenticCount = 0,
    counterfeitCount = 0,
    scanPending = true,
    lastEventMsg = "Market is stable. HODL!",
    
    -- List of funny simulated market events
    Events = {
        { msg = "Goblins of Gadgetzan announce Shellcoin integration! Price pumps!", min = 1.15, max = 1.40 },
        { msg = "Baron Revilgaz imposes a transaction fee in Booty Bay! Price dumps!", min = 0.65, max = 0.85 },
        { msg = "Rumors that Counterfeit Shellcoins are flooding the market! Panic selling!", min = 0.75, max = 0.90 },
        { msg = "A mysterious whale (probably a murloc) buys 10,000 Shellcoins!", min = 1.10, max = 1.30 },
        { msg = "The Great Gnomish Rugpull: Gnome developers disappear with the treasury!", min = 0.30, max = 0.60 },
        { msg = "Shellcoin is declared legal tender in Orgrimmar (temporary zoning rule).", min = 1.05, max = 1.15 },
        { msg = "Stormwind Guard confiscates bags containing Shellcoins under AML acts.", min = 0.85, max = 0.95 },
        { msg = "HODLers unite! A viral forum post urges players to NEVER sell.", min = 1.20, max = 1.50 },
        { msg = "A local farmer finds a stash of Shellcoins in a chest. Supply surges!", min = 0.80, max = 0.90 },
        { msg = "Celebrity Chef cooking show features Shellcoin soup. Demand rises!", min = 1.08, max = 1.25 }
    }
}

-- Initialize math random seed using epoch time
math.randomseed(time())

-- Utility: format price in copper to colored WoW currency string
function ShellcoinTicker:FormatMoney(copper)
    if not copper or copper <= 0 then
        return "0|cffeda55fc|r"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper - (g * 10000)) / 100)
    local c = math.floor(copper - (g * 10000) - (s * 100))
    
    local str = ""
    if g > 0 then
        str = str .. "|cffffd700" .. g .. "g|r "
    end
    if s > 0 or g > 0 then
        str = str .. "|cffc7c7c7" .. s .. "s|r "
    end
    if c > 0 or str == "" then
        str = str .. "|cffeda55f" .. c .. "c|r"
    end
    return str
end

-- Initialize database defaults
function ShellcoinTicker:InitializeDB()
    if not ShellcoinTickerDB then
        ShellcoinTickerDB = {}
    end
    if not ShellcoinTickerDB.price then
        ShellcoinTickerDB.price = 100000 -- 10g starting price
    end
    if not ShellcoinTickerDB.change then
        ShellcoinTickerDB.change = 0.0
    end
    if not ShellcoinTickerDB.history then
        ShellcoinTickerDB.history = { 100000 }
    end
    if ShellcoinTickerDB.isShown == nil then
        ShellcoinTickerDB.isShown = true
    end
end

-- Scan player bags for Shellcoin and Counterfeit Shellcoin
function ShellcoinTicker:ScanBags()
    local auth = 0
    local fake = 0
    
    -- In WoW 1.12, container slots are 0 (backpack) to 4 (bags)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local _, count = GetContainerItemInfo(bag, slot)
                if count and count > 0 then
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        -- Check for Counterfeit first since it contains the substring "Shellcoin"
                        if string.find(link, "Counterfeit Shellcoin") then
                            fake = fake + count
                        elseif string.find(link, "Shellcoin") then
                            auth = auth + count
                        end
                    end
                end
            end
        end
    end
    
    self.authenticCount = auth
    self.counterfeitCount = fake
end

-- Simulates one step of the Shellcoin market price
function ShellcoinTicker:UpdateSimulation()
    if not ShellcoinTickerDB then return end
    
    local currentPrice = ShellcoinTickerDB.price
    local changePct = 0
    local eventMsg = nil
    
    -- 10% chance of a special market event
    if math.random(1, 100) <= 10 then
        local eventIndex = math.random(1, table.getn(self.Events))
        local event = self.Events[eventIndex]
        
        -- Multiplier range
        local multiplier = event.min + (math.random() * (event.max - event.min))
        changePct = multiplier - 1.0
        currentPrice = math.floor(currentPrice * multiplier)
        eventMsg = event.msg
    else
        -- Regular fluctuation (-5% to +6% to give a slight positive drift)
        local change = -0.05 + (math.random() * 0.11)
        changePct = change
        currentPrice = math.floor(currentPrice * (1.0 + change))
    end
    
    -- Ensure price doesn't fall to 0 (minimum 1 copper)
    if currentPrice < 1 then
        currentPrice = 1
    end
    
    -- Calculate 24h change representation
    ShellcoinTickerDB.change = changePct
    ShellcoinTickerDB.price = currentPrice
    
    -- Update news feed message
    if eventMsg then
        self.lastEventMsg = eventMsg
    else
        self.lastEventMsg = "Price updated. HODL! (Change: " .. string.format("%.1f%%", changePct * 100) .. ")"
    end
    
    -- Manage historical data (keep last 6 prices)
    if not ShellcoinTickerDB.history then
        ShellcoinTickerDB.history = {}
    end
    
    table.insert(ShellcoinTickerDB.history, currentPrice)
    if table.getn(ShellcoinTickerDB.history) > 6 then
        table.remove(ShellcoinTickerDB.history, 1)
    end
    
    -- Update UI
    if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
        ShellcoinTicker.UI:UpdateDisplay()
    end
end

-- Event Handler function
local function OnEvent()
    if event == "ADDON_LOADED" and arg1 == "ShellcoinTicker" then
        ShellcoinTicker:InitializeDB()
        
        -- Set up UI
        if ShellcoinTicker.UI and ShellcoinTicker.UI.CreateMainFrame then
            ShellcoinTicker.UI:CreateMainFrame()
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker loaded! Type /sct or /shellcoin to toggle the HUD.|r")
    elseif event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        ShellcoinTicker.scanPending = true
    end
end

-- Create hidden frame to handle event registration
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", OnEvent)

-- Setup slash commands
SLASH_SHELLCOINTICKER1 = "/shellcoin"
SLASH_SHELLCOINTICKER2 = "/sct"
SlashCmdList["SHELLCOINTICKER"] = function(msg)
    if msg == "show" then
        ShellcoinTickerDB.isShown = true
        if ShellcoinTicker.UI and ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:Show()
        end
    elseif msg == "hide" then
        ShellcoinTickerDB.isShown = false
        if ShellcoinTicker.UI and ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:Hide()
        end
    elseif msg == "reset" then
        ShellcoinTickerDB.price = 100000
        ShellcoinTickerDB.change = 0.0
        ShellcoinTickerDB.history = { 100000 }
        ShellcoinTicker.lastEventMsg = "Simulation reset by user."
        ShellcoinTicker:UpdateSimulation()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Price and simulation history reset!|r")
    elseif msg == "mock" then
        -- Force a market event
        local eventIndex = math.random(1, table.getn(ShellcoinTicker.Events))
        local event = ShellcoinTicker.Events[eventIndex]
        local multiplier = event.min + (math.random() * (event.max - event.min))
        ShellcoinTickerDB.change = multiplier - 1.0
        ShellcoinTickerDB.price = math.max(1, math.floor(ShellcoinTickerDB.price * multiplier))
        ShellcoinTicker.lastEventMsg = "[MOCK EVENT] " .. event.msg
        
        table.insert(ShellcoinTickerDB.history, ShellcoinTickerDB.price)
        if table.getn(ShellcoinTickerDB.history) > 6 then
            table.remove(ShellcoinTickerDB.history, 1)
        end
        
        if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
            ShellcoinTicker.UI:UpdateDisplay()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Forced market event triggered!|r")
    else
        -- Toggle show/hide by default
        if ShellcoinTicker.UI and ShellcoinTicker.UI.frame then
            if ShellcoinTicker.UI.frame:IsShown() then
                ShellcoinTickerDB.isShown = false
                ShellcoinTicker.UI.frame:Hide()
            else
                ShellcoinTickerDB.isShown = true
                ShellcoinTicker.UI.frame:Show()
            end
        end
    end
end
