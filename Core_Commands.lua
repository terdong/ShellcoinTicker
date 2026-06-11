-- Core_Commands.lua
-- Slash Commands and Hook Handlers for ShellcoinTicker (Vanilla WoW 1.12)

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
        StaticPopup_Show("SHELLCOINTICKER_CONFIRM_CLEAR")
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
        StaticPopup_Show("SHELLCOINTICKER_CONFIRM_RESET")
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

                -- 5. 120 points in the last 1.2 years (3.5-day intervals)
                for i = 120, 10, -1 do
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
    text =
    "WARNING: Enabling Mock Mode or generating mock history may modify or lose your accumulated historical data. Do you want to proceed?",
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

-- Hook Gossip option selection to capture NPC transaction price and intent
local original_SelectGossipOption = SelectGossipOption
SelectGossipOption = function(index)
    if GetGossipOptions then
        local opts = { GetGossipOptions() }
        local numOpts = table.getn(opts) / 2
        if index >= 1 and index <= numOpts then
            local text = opts[(index - 1) * 2 + 1]
            if text then
                local textLower = string.lower(text)
                local isBuy = string.find(textLower, "buy for", 1, true)
                local isSell = string.find(textLower, "sell for", 1, true)
                if isBuy or isSell then
                    local price = ShellcoinTicker:ParseMoneyString(text)
                    if price and price > 0 then
                        ShellcoinTicker.pendingGossipTx = {
                            type = isBuy and "buy" or "sell",
                            price = price,
                            time = time()
                        }
                    end
                end
            end
        end
    end
    if original_SelectGossipOption then
        original_SelectGossipOption(index)
    end
end

-- Hook DeleteCursorItem to detect when the player destroys Shellcoin
local original_DeleteCursorItem = DeleteCursorItem
DeleteCursorItem = function()
    local isShellcoinDelete = false
    local numDialogs = STATICPOPUP_NUMDIALOGS or 4
    for i = 1, numDialogs do
        local frameName = "StaticPopup" .. i
        local frame = getglobal(frameName)
        if frame and frame:IsShown() and (frame.which == "DELETE_ITEM" or frame.which == "DELETE_GOOD_ITEM") then
            local textFrame = getglobal(frameName .. "Text")
            local text = textFrame and textFrame:GetText() or ""
            if string.find(text, "Shellcoin", 1, true) and not string.find(text, "Counterfeit Shellcoin", 1, true) then
                isShellcoinDelete = true
            end
        end
    end

    if isShellcoinDelete then
        ShellcoinTicker.pendingDelete = true
    end

    if original_DeleteCursorItem then
        original_DeleteCursorItem()
    end
end
