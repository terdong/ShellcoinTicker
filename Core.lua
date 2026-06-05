-- Core.lua
-- Addon Core Logic & Market Simulation for ShellcoinTicker (Vanilla WoW 1.12)

ShellcoinTicker = {
    -- State variables
    authenticCount = 0,
    bagsCount = 0,
    bankCount = 0,
    isBankOpen = false,
    scanPending = true,
    speedrunMode = false,
    lastEventMsg = "Market is stable. HODL!",
    isSilentSync = false,

    -- List of funny simulated market events
    Events = {
        { msg = "Goblins of Gadgetzan announce Shellcoin integration! Price pumps!",        min = 1.15, max = 1.40 },
        { msg = "Baron Revilgaz imposes a transaction fee in Booty Bay! Price dumps!",      min = 0.65, max = 0.85 },
        { msg = "Rumors of a massive sell-off flood the market! Panic selling!",            min = 0.75, max = 0.90 },
        { msg = "A mysterious whale (probably a murloc) buys 10,000 Shellcoins!",           min = 1.10, max = 1.30 },
        { msg = "The Great Gnomish Rugpull: Gnome developers disappear with the treasury!", min = 0.30, max = 0.60 },
        { msg = "Shellcoin is declared legal tender in Orgrimmar (temporary zoning rule).", min = 1.05, max = 1.15 },
        { msg = "Stormwind Guard confiscates bags containing Shellcoins under AML acts.",   min = 0.85, max = 0.95 },
        { msg = "HODLers unite! A viral forum post urges players to NEVER sell.",           min = 1.20, max = 1.50 },
        { msg = "A local farmer finds a stash of Shellcoins in a chest. Supply surges!",    min = 0.80, max = 0.90 },
        { msg = "Celebrity Chef cooking show features Shellcoin soup. Demand rises!",       min = 1.08, max = 1.25 }
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

    local realm = GetRealmName()
    local charKey = UnitName("player")

    -- Detect if there is old flat data to migrate
    if rawget(ShellcoinTickerDB, "price") ~= nil or rawget(ShellcoinTickerDB, "characters") ~= nil then
        if not rawget(ShellcoinTickerDB, realm) then
            rawset(ShellcoinTickerDB, realm, {})
        end
        local currentDB = rawget(ShellcoinTickerDB, realm)

        currentDB.price = rawget(ShellcoinTickerDB, "price") or currentDB.price or 0
        currentDB.change = rawget(ShellcoinTickerDB, "change") or currentDB.change or 0.0
        currentDB.history = rawget(ShellcoinTickerDB, "history") or currentDB.history
        currentDB.transactions = rawget(ShellcoinTickerDB, "transactions") or currentDB.transactions
        currentDB.isShown = rawget(ShellcoinTickerDB, "isShown")
        currentDB.mockMode = rawget(ShellcoinTickerDB, "mockMode")
        currentDB.selectedTimeframe = rawget(ShellcoinTickerDB, "selectedTimeframe")

        -- Migrate characters to their respective realms
        local oldChars = rawget(ShellcoinTickerDB, "characters")
        if oldChars then
            for oldKey, charData in pairs(oldChars) do
                local _, _, name, rName = string.find(oldKey, "^(.-)%s*-%s*(.+)$")
                name = name or oldKey
                rName = rName or realm

                if not rawget(ShellcoinTickerDB, rName) then
                    rawset(ShellcoinTickerDB, rName, {})
                end
                local rDB = rawget(ShellcoinTickerDB, rName)
                if not rDB.characters then
                    rDB.characters = {}
                end
                rDB.characters[name] = charData
            end
        end

        -- Clean up flat keys from global table
        rawset(ShellcoinTickerDB, "price", nil)
        rawset(ShellcoinTickerDB, "change", nil)
        rawset(ShellcoinTickerDB, "history", nil)
        rawset(ShellcoinTickerDB, "transactions", nil)
        rawset(ShellcoinTickerDB, "isShown", nil)
        rawset(ShellcoinTickerDB, "mockMode", nil)
        rawset(ShellcoinTickerDB, "selectedTimeframe", nil)
        rawset(ShellcoinTickerDB, "characters", nil)
    end

    -- Ensure current realm subtable exists
    if not rawget(ShellcoinTickerDB, realm) then
        rawset(ShellcoinTickerDB, realm, {})
    end

    -- Setup metatable redirection to current realm
    local mt = {
        __index = function(t, key)
            local r = GetRealmName()
            if not r or r == "" then return nil end
            local rTable = rawget(t, r)
            if not rTable then
                rTable = {}
                rawset(t, r, rTable)
            end
            return rTable[key]
        end,
        __newindex = function(t, key, val)
            local r = GetRealmName()
            if not r or r == "" then return end
            local rTable = rawget(t, r)
            if not rTable then
                rTable = {}
                rawset(t, r, rTable)
            end
            rTable[key] = val
        end
    }
    setmetatable(ShellcoinTickerDB, mt)

    -- Initialize defaults for the active realm
    if not ShellcoinTickerDB.price then
        ShellcoinTickerDB.price = 0
    end
    if not ShellcoinTickerDB.change then
        ShellcoinTickerDB.change = 0.0
    end

    -- Migrate history to time-price table format if needed
    if ShellcoinTickerDB.history then
        local firstEntry = ShellcoinTickerDB.history[1]
        if firstEntry and type(firstEntry) ~= "table" then
            local migrated = {}
            local now = time()
            for i = 1, table.getn(ShellcoinTickerDB.history) do
                table.insert(migrated, { time = now - (15 - i) * 15, price = ShellcoinTickerDB.history[i] })
            end
            ShellcoinTickerDB.history = migrated
        end
    else
        ShellcoinTickerDB.history = { { time = time(), price = 0 } }
    end

    if not ShellcoinTickerDB.transactions then
        ShellcoinTickerDB.transactions = {}
    end
    if ShellcoinTickerDB.isShown == nil then
        ShellcoinTickerDB.isShown = true
    end
    if ShellcoinTickerDB.mockMode == nil then
        ShellcoinTickerDB.mockMode = false
    end
    if not ShellcoinTickerDB.selectedTimeframe or ShellcoinTickerDB.selectedTimeframe == "10m" then
        ShellcoinTickerDB.selectedTimeframe = "1h"
    end
    if not ShellcoinTickerDB.characters then
        ShellcoinTickerDB.characters = {}
    end
    if not ShellcoinTickerDB.characters[charKey] then
        ShellcoinTickerDB.characters[charKey] = { bags = 0, bank = 0 }
    end
    if not ShellcoinTickerDB.graphMode then
        ShellcoinTickerDB.graphMode = "area"
    end
    if ShellcoinTickerDB.hudScale == nil then
        ShellcoinTickerDB.hudScale = 1.0
    end
    if ShellcoinTickerDB.minimapAngle == nil then
        ShellcoinTickerDB.minimapAngle = 45
    end
    if ShellcoinTickerDB.showMinimapButton == nil then
        ShellcoinTickerDB.showMinimapButton = true
    end
    if ShellcoinTickerDB.showFinancials == nil then
        ShellcoinTickerDB.showFinancials = true
    end
    if ShellcoinTickerDB.showPriceTrend == nil then
        ShellcoinTickerDB.showPriceTrend = true
    end
    if ShellcoinTickerDB.showTimeframe == nil then
        ShellcoinTickerDB.showTimeframe = true
    end
    if ShellcoinTickerDB.showChart == nil then
        ShellcoinTickerDB.showChart = true
    end
    if ShellcoinTickerDB.showHoldings == nil then
        ShellcoinTickerDB.showHoldings = true
    end
    if ShellcoinTickerDB.showFeed == nil then
        ShellcoinTickerDB.showFeed = true
    end
    if ShellcoinTickerDB.syncInterval == nil then
        ShellcoinTickerDB.syncInterval = 600
    end
end

-- Scan player bags and bank for Shellcoin
function ShellcoinTicker:ScanBags()
    local charKey = UnitName("player")
    if not ShellcoinTickerDB.characters then
        ShellcoinTickerDB.characters = {}
    end
    if not ShellcoinTickerDB.characters[charKey] then
        ShellcoinTickerDB.characters[charKey] = { bags = 0, bank = 0 }
    end

    local oldAuth = self.authenticCount or 0
    local bagsTotal = 0

    -- In WoW 1.12, container slots are 0 (backpack) to 4 (bags)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local _, count = GetContainerItemInfo(bag, slot)
                if count and count > 0 then
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        -- Check for Shellcoin, but exclude counterfeit
                        if string.find(link, "Shellcoin", 1, true) and not string.find(link, "Counterfeit Shellcoin", 1, true) then
                            bagsTotal = bagsTotal + count
                        end
                    end
                end
            end
        end
    end

    ShellcoinTickerDB.characters[charKey].bags = bagsTotal
    self.bagsCount = bagsTotal

    -- Only scan the bank if the bank frame is open
    if self.isBankOpen then
        local bankTotal = 0

        -- Bank main container is -1
        local slots = GetContainerNumSlots(-1)
        if slots and slots > 0 then
            for slot = 1, slots do
                local _, count = GetContainerItemInfo(-1, slot)
                if count and count > 0 then
                    local link = GetContainerItemLink(-1, slot)
                    if link then
                        if string.find(link, "Shellcoin", 1, true) and not string.find(link, "Counterfeit Shellcoin", 1, true) then
                            bankTotal = bankTotal + count
                        end
                    end
                end
            end
        end

        -- Bank bag containers are 5 to 10
        for bag = 5, 10 do
            local slots = GetContainerNumSlots(bag)
            if slots and slots > 0 then
                for slot = 1, slots do
                    local _, count = GetContainerItemInfo(bag, slot)
                    if count and count > 0 then
                        local link = GetContainerItemLink(bag, slot)
                        if link then
                            if string.find(link, "Shellcoin", 1, true) and not string.find(link, "Counterfeit Shellcoin", 1, true) then
                                bankTotal = bankTotal + count
                            end
                        end
                    end
                end
            end
        end

        ShellcoinTickerDB.characters[charKey].bank = bankTotal
        self.bankCount = bankTotal
    else
        self.bankCount = ShellcoinTickerDB.characters[charKey].bank or 0
    end

    local newAuth = self.bagsCount + self.bankCount
    self.authenticCount = newAuth

    local firstScan = (not self.firstScanDone)
    self.firstScanDone = true

    -- Track transactions automatically on changes after the first scan
    if not firstScan and newAuth ~= oldAuth then
        local diff = newAuth - oldAuth
        self:AddTransaction(diff, ShellcoinTickerDB.price)
    end
end

-- Simulates one step of the Shellcoin market price
function ShellcoinTicker:UpdateSimulation()
    -- Skip simulation if mock mode is disabled (i.e. server sync mode is active)
    if not ShellcoinTickerDB or not ShellcoinTickerDB.mockMode then return end

    local currentPrice = ShellcoinTickerDB.price
    -- Seed price if it is 0 so the simulation can start fluctuating
    if currentPrice <= 0 then
        currentPrice = 100000
    end
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

    self:UpdateHistoryAndChange(currentPrice)

    -- Update UI
    if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
        ShellcoinTicker.UI:UpdateDisplay()
    end
end

-- Add a transaction to the history
function ShellcoinTicker:AddTransaction(quantity, unitPrice)
    if not ShellcoinTickerDB then return end
    if not ShellcoinTickerDB.transactions then
        ShellcoinTickerDB.transactions = {}
    end

    local tx = {
        timestamp = time(),
        quantity = quantity,
        price = unitPrice
    }
    table.insert(ShellcoinTickerDB.transactions, tx)

    local action = quantity > 0 and "bought" or "sold"
    local absQty = math.abs(quantity)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Recorded transaction: " ..
        action .. " " .. absQty .. " SHELL at " .. self:FormatMoney(unitPrice) .. " each.|r")

    -- Refresh UI
    if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
        ShellcoinTicker.UI:UpdateDisplay()
    end
end

-- Calculate current profit/loss using running average cost basis
function ShellcoinTicker:CalculateProfitLoss()
    local transactions = ShellcoinTickerDB and ShellcoinTickerDB.transactions or {}
    local holdings = 0
    local costBasis = 0

    for i = 1, table.getn(transactions) do
        local tx = transactions[i]
        local qty = tx.quantity
        local price = tx.price

        if qty > 0 then
            local newHoldings = holdings + qty
            costBasis = ((holdings * costBasis) + (qty * price)) / newHoldings
            holdings = newHoldings
        elseif qty < 0 then
            holdings = math.max(0, holdings + qty)
        end
    end

    local currentHoldings = self.authenticCount or 0
    local totalInvested = currentHoldings * costBasis
    local currentMarketValue = currentHoldings * ShellcoinTickerDB.price
    local profitLoss = currentMarketValue - totalInvested

    local profitLossPercent = 0
    if totalInvested > 0 then
        profitLossPercent = (profitLoss / totalInvested) * 100
    end

    return totalInvested, profitLoss, profitLossPercent, costBasis
end

-- Update price history and compute change percentage
function ShellcoinTicker:UpdateHistoryAndChange(price)
    local oldPrice = ShellcoinTickerDB.price or price
    local changePct = 0
    if oldPrice > 0 then
        changePct = (price - oldPrice) / oldPrice
    end
    ShellcoinTickerDB.change = changePct
    ShellcoinTickerDB.price = price

    if not ShellcoinTickerDB.history then
        ShellcoinTickerDB.history = {}
    end

    local numEntries = table.getn(ShellcoinTickerDB.history)
    local lastEntry = numEntries > 0 and ShellcoinTickerDB.history[numEntries]

    local shouldInsert = true
    if lastEntry and type(lastEntry) == "table" then
        local lastPrice = lastEntry.price or 0
        local lastTime = lastEntry.time or 0
        if price == lastPrice then
            -- If price is identical, only record if at least 10 minutes (600s) have passed in mock mode.
            -- In live server sync mode, we only record the FIRST identical price to show a flat trend segment ('-'),
            -- and suppress subsequent identical prices to avoid spamming the history.
            if ShellcoinTickerDB.mockMode then
                if time() - lastTime < 600 then
                    shouldInsert = false
                end
            else
                local secondLastEntry = numEntries > 1 and ShellcoinTickerDB.history[numEntries - 1]
                if secondLastEntry and type(secondLastEntry) == "table" and secondLastEntry.price == lastPrice then
                    shouldInsert = false
                end
            end
        elseif (time() - lastTime < 60) then
            -- Limit history updates to at most once per 60 seconds to prevent file bloat in both modes
            shouldInsert = false
        end
    end

    if shouldInsert then
        -- Insert new time-price entry
        table.insert(ShellcoinTickerDB.history, { time = time(), price = price })

        -- Prune entries older than 1 year (31,536,000 seconds)
        local cutoff = time() - 31536000
        local pruned = {}
        for i = 1, table.getn(ShellcoinTickerDB.history) do
            local entry = ShellcoinTickerDB.history[i]
            if entry and type(entry) == "table" and entry.time and entry.time >= cutoff then
                table.insert(pruned, entry)
            end
        end
        ShellcoinTickerDB.history = pruned
    end
end

-- Process incoming chat messages to sync with server prices
function ShellcoinTicker:ProcessChatMessage(msg)
    if not msg then return end

    -- Performance optimization: Early exit if "shellcoin" is not in the message.
    -- This prevents executing string.upper() and generating garbage for every single chat message.
    if not string.find(msg, "[Ss][Hh][Ee][Ll][Ll][Cc][Oo][Ii][Nn]") then return end

    local msgUpper = string.upper(msg)

    local isBuy = string.find(msgUpper, "SHELLCOIN BUY PRICE", 1, true)
    local isSell = string.find(msgUpper, "SHELLCOIN SELL PRICE", 1, true)
    local isBroadcast = string.find(msgUpper, "SHELLCOIN PRICE HAS", 1, true)

    if isBuy or isSell or isBroadcast then
        local _, _, goldStr = string.find(msgUpper, "(%d+)G")
        local _, _, silverStr = string.find(msgUpper, "(%d+)S")
        local _, _, copperStr = string.find(msgUpper, "(%d+)C")

        local gold = tonumber(goldStr) or 0
        local silver = tonumber(silverStr) or 0
        local copper = tonumber(copperStr) or 0
        local price = gold * 10000 + silver * 100 + copper

        if price > 0 then
            -- Disable mock mode automatically when server price is detected
            if ShellcoinTickerDB.mockMode then
                ShellcoinTickerDB.mockMode = false
                ShellcoinTicker.speedrunMode = false
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00ShellcoinTicker: Live server price detected. Mock simulation and Speedrun modes disabled.|r")
            end

            if isBuy then
                ShellcoinTickerDB.buyPrice = price
            elseif isSell then
                ShellcoinTickerDB.sellPrice = price
                self:UpdateHistoryAndChange(price)
            elseif isBroadcast then
                -- General price update broadcast (clear specific buy/sell so UI falls back)
                ShellcoinTickerDB.buyPrice = nil
                ShellcoinTickerDB.sellPrice = nil
                self:UpdateHistoryAndChange(price)
            end

            -- Refresh UI
            if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
                ShellcoinTicker.UI:UpdateDisplay()
            end
        end
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

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00ShellcoinTicker loaded! Type /sct or /shellcointicker to toggle the HUD.|r")
    elseif event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        ShellcoinTicker.scanPending = true
    elseif event == "BANKFRAME_OPENED" then
        ShellcoinTicker.isBankOpen = true
        ShellcoinTicker.scanPending = true
    elseif event == "BANKFRAME_CLOSED" then
        ShellcoinTicker.isBankOpen = false
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if arg1 == 81118 then
            if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateMinimapIcon then
                ShellcoinTicker.UI:UpdateMinimapIcon()
            end
        end
    elseif string.find(event or "", "^CHAT_MSG") then
        ShellcoinTicker:ProcessChatMessage(arg1)
    end
end

-- Create hidden frame to handle event registration
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("CHAT_MSG_SAY")
eventFrame:RegisterEvent("CHAT_MSG_YELL")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
eventFrame:SetScript("OnEvent", OnEvent)

-- Parse money string like "99g 99s 99c" or raw copper numbers
function ShellcoinTicker:ParseMoneyString(str)
    if not str or str == "" then return nil end

    -- If it is a pure number, treat it as copper
    if tonumber(str) then
        return tonumber(str)
    end

    local strUpper = string.upper(str)
    local _, _, goldStr = string.find(strUpper, "(%d+)%s*G")
    local _, _, silverStr = string.find(strUpper, "(%d+)%s*S")
    local _, _, copperStr = string.find(strUpper, "(%d+)%s*C")

    local gold = tonumber(goldStr) or 0
    local silver = tonumber(silverStr) or 0
    local copper = tonumber(copperStr) or 0

    if gold == 0 and silver == 0 and copper == 0 then
        return nil
    end

    return gold * 10000 + silver * 100 + copper
end

-- Full reset of addon data and settings
function ShellcoinTicker:ResetAll()
    ShellcoinTicker.speedrunMode = false

    -- Full wipe of the saved variables table
    if ShellcoinTickerDB then
        for k, v in pairs(ShellcoinTickerDB) do
            ShellcoinTickerDB[k] = nil
        end
    end

    -- Re-initialize defaults
    ShellcoinTicker:InitializeDB()

    -- Reset session state variables
    ShellcoinTicker.bagsCount = 0
    ShellcoinTicker.bankCount = 0
    ShellcoinTicker.authenticCount = 0
    ShellcoinTicker.lastEventMsg = "Addon fully reset by user."

    -- Perform an immediate scan of bags to get current count, then mark scan complete
    ShellcoinTicker:ScanBags()
    ShellcoinTicker.scanPending = false

    if ShellcoinTicker.UI then
        if ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:SetScale(1.0)
            if ShellcoinTickerDB.isShown then
                ShellcoinTicker.UI.frame:Show()
            else
                ShellcoinTicker.UI.frame:Hide()
            end
        end
        ShellcoinTicker.UI:UpdateMinimapButton()
        if ShellcoinTicker.UI.RefreshOptionsUI then
            ShellcoinTicker.UI:RefreshOptionsUI()
        end
        ShellcoinTicker.UI:UpdateDisplay()
        ShellcoinTicker.UI:UpdateTimeframeButtonHighlights()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Full reset completed!|r")
end

-- Setup slash commands
SLASH_SHELLCOINTICKER1 = "/shellcointicker"
SLASH_SHELLCOINTICKER2 = "/sct"
SlashCmdList["SHELLCOINTICKER"] = function(msg)
    local _, _, cmd, args = string.find(msg or "", "^(%S*)%s*(.*)$")
    cmd = string.lower(cmd or "")

    if cmd == "buy" or cmd == "sell" then
        local _, _, qtyStr, moneyStr = string.find(args or "", "^(%d+)%s*(.*)$")
        local qty = tonumber(qtyStr)
        local price = ShellcoinTickerDB.price
        local validPrice = true

        if moneyStr and moneyStr ~= "" then
            local parsedPrice = ShellcoinTicker:ParseMoneyString(moneyStr)
            if parsedPrice then
                price = parsedPrice
            else
                validPrice = false
            end
        end

        if qty and qty > 0 and validPrice then
            if cmd == "sell" then
                qty = -qty
            end
            ShellcoinTicker:AddTransaction(qty, price)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ShellcoinTicker: Usage: /sct buy/sell <quantity> [price]|r")
            DEFAULT_CHAT_FRAME:AddMessage(
                "  e.g., |cff00ff00/sct buy 5 12g 50s|r or |cff00ff00/sct buy 10 99g 99s 99c|r")
        end
    elseif cmd == "clear" then
        ShellcoinTickerDB.transactions = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Transaction history cleared!|r")
        if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
            ShellcoinTicker.UI:UpdateDisplay()
        end
    elseif cmd == "show" then
        ShellcoinTickerDB.isShown = true
        if ShellcoinTicker.UI and ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:Show()
        end
    elseif cmd == "hide" then
        ShellcoinTickerDB.isShown = false
        if ShellcoinTicker.UI and ShellcoinTicker.UI.frame then
            ShellcoinTicker.UI.frame:Hide()
        end
    elseif cmd == "graph" then
        if ShellcoinTickerDB.graphMode == "candle" then
            ShellcoinTickerDB.graphMode = "area"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Graph style set to AREA CHART.|r")
        else
            ShellcoinTickerDB.graphMode = "candle"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Graph style set to CANDLESTICK CHART.|r")
        end
        if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
            ShellcoinTicker.UI:UpdateDisplay()
        end
    elseif cmd == "reset" then
        ShellcoinTicker:ResetAll()
    elseif cmd == "options" or cmd == "config" then
        if ShellcoinTicker.UI and ShellcoinTicker.UI.ToggleOptionsFrame then
            ShellcoinTicker.UI:ToggleOptionsFrame()
        end
    elseif cmd == "mock" then
        local subCmd = string.lower(args or "")
        local _, _, subClean = string.find(subCmd, "^%s*([%w]*)%s*$")
        subClean = subClean or ""

        if subClean == "on" or subClean == "enable" then
            ShellcoinTicker:ConfirmMockAction(function()
                ShellcoinTickerDB.mockMode = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00ShellcoinTicker: Mock simulation mode is now ENABLED. Price will fluctuate locally.|r")
                if ShellcoinTickerDB.price == 0 then
                    ShellcoinTickerDB.price = 100000
                    ShellcoinTickerDB.history = { { time = time(), price = 100000 } }
                end
                ShellcoinTicker:UpdateSimulation()
            end)
        elseif subClean == "off" or subClean == "disable" then
            ShellcoinTickerDB.mockMode = false
            ShellcoinTicker.speedrunMode = false
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ff00ShellcoinTicker: Mock simulation and Speedrun modes are now DISABLED. Live server price sync is active.|r")
        elseif subClean == "status" then
            local statusStr = ShellcoinTickerDB.mockMode and "|cff00ff00ENABLED|r" or
                "|cffff0000DISABLED (Live server mode)|r"
            DEFAULT_CHAT_FRAME:AddMessage("ShellcoinTicker: Mock simulation mode is currently " .. statusStr)
        elseif subClean == "fill" or subClean == "history" then
            ShellcoinTicker:ConfirmMockAction(function()
                -- Generate mock history data spanning 30 days, distributed across all timeframes
                local times = {}
                local now = time()

                -- 1. 10 points in the last 1 hour (6m intervals)
                for i = 10, 1, -1 do
                    table.insert(times, now - i * 360)
                end

                -- 2. 20 points in the last 1 day (1h intervals)
                for i = 24, 2, -1 do
                    table.insert(times, now - i * 3600)
                end

                -- 3. 42 points in the last 1 week (4h intervals)
                for i = 42, 2, -1 do
                    table.insert(times, now - i * 14400)
                end

                -- 4. 110 points in the last 30 days (6h intervals)
                for i = 120, 5, -1 do
                    table.insert(times, now - i * 21600)
                end

                -- 5. 100 points in the last 1 year (3.5-day intervals)
                for i = 100, 10, -1 do
                    table.insert(times, now - i * 302400)
                end

                table.insert(times, now)
                table.sort(times)

                local price = 100000 -- 10g base price
                ShellcoinTickerDB.history = {}
                for i = 1, table.getn(times) do
                    -- Price fluctuation -10% to +10.5% (gives a realistic organic walk)
                    local change = -0.10 + (math.random() * 0.205)
                    price = math.max(100, math.floor(price * (1.0 + change)))
                    table.insert(ShellcoinTickerDB.history, { time = times[i], price = price })
                end

                local numH = table.getn(ShellcoinTickerDB.history)
                ShellcoinTickerDB.price = ShellcoinTickerDB.history[numH].price
                local prevPrice = numH > 1 and ShellcoinTickerDB.history[numH - 1].price or price
                ShellcoinTickerDB.change = (prevPrice > 0) and ((ShellcoinTickerDB.price - prevPrice) / prevPrice) or 0.0

                ShellcoinTicker.lastEventMsg = "Mock history populated with " .. numH .. " points across all timeframes."

                -- Refresh UI
                if ShellcoinTicker.UI and ShellcoinTicker.UI.UpdateDisplay then
                    ShellcoinTicker.UI:UpdateDisplay()
                end
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00ShellcoinTicker: Mock history successfully populated with data for all timeframes!|r")
            end)
        elseif subClean == "speedrun" or subClean == "fast" then
            if not ShellcoinTicker.speedrunMode then
                ShellcoinTicker:ConfirmMockAction(function()
                    ShellcoinTicker.speedrunMode = true
                    ShellcoinTickerDB.mockMode = true
                    ShellcoinTickerDB.history = {}
                    ShellcoinTicker.virtualTime = time() - 2592000 -- 30 days ago
                    ShellcoinTickerDB.price = 100000               -- 10g base price
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff00ff00ShellcoinTicker: Speedrun mock mode ENABLED. Simulating 30 days of data at 10m intervals, updating every 1 second.|r")
                end)
            else
                ShellcoinTicker.speedrunMode = false
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ShellcoinTicker: Speedrun mock mode DISABLED.|r")
            end
        elseif subClean == "" then
            -- Toggle behavior if no argument passed
            if not ShellcoinTickerDB.mockMode then
                ShellcoinTicker:ConfirmMockAction(function()
                    ShellcoinTickerDB.mockMode = true
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff00ff00ShellcoinTicker: Mock simulation mode has been toggled to |cff00ff00ENABLED. Price will fluctuate locally.|r")
                    if ShellcoinTickerDB.price == 0 then
                        ShellcoinTickerDB.price = 100000
                        ShellcoinTickerDB.history = { { time = time(), price = 100000 } }
                    end
                    ShellcoinTicker:UpdateSimulation()
                end)
            else
                ShellcoinTickerDB.mockMode = false
                ShellcoinTicker.speedrunMode = false
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00ShellcoinTicker: Mock simulation and Speedrun modes are now DISABLED. Live server price sync is active.|r")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ShellcoinTicker: Usage: /sct mock [on/off/status/fill/speedrun]|r")
        end
    elseif cmd == "help" or cmd == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd700🐢 Shellcoin Ticker Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct|r or |cff00ff00/sct help|r - Show command list")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct options|r - Open options window")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct show|r - Show the HUD frame")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct hide|r - Hide the HUD frame")
        DEFAULT_CHAT_FRAME:AddMessage(
            "  |cff00ff00/sct buy <qty> [price]|r - Record a buy transaction (price in copper)")
        DEFAULT_CHAT_FRAME:AddMessage(
            "  |cff00ff00/sct sell <qty> [price]|r - Record a sell transaction (price in copper)")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct clear|r - Clear transaction history (resets cost basis)")
        DEFAULT_CHAT_FRAME:AddMessage(
            "  |cff00ff00/sct reset|r - Full reset of price, history, transactions, and simulation lock")
        DEFAULT_CHAT_FRAME:AddMessage(
            "  |cff00ff00/sct mock [on/off/status/fill/speedrun]|r - Toggle mock, fill, or start 30-day fast-forward")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/sct graph|r - Toggle graph style (Area / Candlestick)")
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff0000ShellcoinTicker: Unknown command. Type '/sct help' to view help details.|r")
    end
end

-- Hook ChatFrame_OnEvent to suppress the .shellcoin command and its price responses
local original_ChatFrame_OnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(event)
    if event == "CHAT_MSG_SYSTEM" then
        if arg1 and ShellcoinTicker.isSilentSync then
            local msgUpper = string.upper(arg1)
            if string.find(msgUpper, "SHELLCOIN SELL PRICE", 1, true) then
                ShellcoinTicker.isSilentSync = false
                return
            end
            if string.find(msgUpper, "SHELLCOIN BUY PRICE", 1, true) then
                return
            end
        end
    end
    if original_ChatFrame_OnEvent then
        original_ChatFrame_OnEvent(event)
    end
end

-- Define Static Popup Dialog for Mock Mode Warning
StaticPopupDialogs["SCT_MOCK_CONFIRM"] = {
    text = "WARNING: Enabling Mock Mode or generating mock history may modify or lose your accumulated historical data. Do you want to proceed?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        if ShellcoinTicker.pendingMockAction then
            ShellcoinTicker.pendingMockAction()
            ShellcoinTicker.pendingMockAction = nil
        end
    end,
    OnCancel = function()
        ShellcoinTicker.pendingMockAction = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function ShellcoinTicker:ConfirmMockAction(actionFunc)
    self.pendingMockAction = actionFunc
    StaticPopup_Show("SCT_MOCK_CONFIRM")
end
