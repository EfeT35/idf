local player = game.Players.LocalPlayer
local playerGui = player.PlayerGui

if playerGui:FindFirstChild("SABHub") then
    playerGui.SABHub:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SABHub"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- =====================================================================
-- FENETRE PRINCIPALE
-- =====================================================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 270)
main.Position = UDim2.new(0.5, -120, 0, 20)
main.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
main.BackgroundTransparency = 0.1
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(0, 200, 255)
mainStroke.Transparency = 0.7
mainStroke.Thickness = 1

-- Header
local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
header.BackgroundTransparency = 0.85
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
local dot = Instance.new("Frame", header)
dot.Size = UDim2.new(0, 7, 0, 7)
dot.Position = UDim2.new(0, 12, 0.5, -3)
dot.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
dot.BorderSizePixel = 0
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size = UDim2.new(1, -24, 1, 0)
titleLbl.Position = UDim2.new(0, 24, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "AA CODE TYPER"
titleLbl.TextColor3 = Color3.fromRGB(0, 220, 255)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- AUTO CODE bouton
local autoCodeBtn = Instance.new("TextButton", main)
autoCodeBtn.Size = UDim2.new(1, -20, 0, 28)
autoCodeBtn.Position = UDim2.new(0, 10, 0, 36)
autoCodeBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
autoCodeBtn.BackgroundTransparency = 0.85
autoCodeBtn.BorderSizePixel = 0
autoCodeBtn.Text = "AUTO CODE: OFF"
autoCodeBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
autoCodeBtn.Font = Enum.Font.GothamBold
autoCodeBtn.TextSize = 12
Instance.new("UICorner", autoCodeBtn).CornerRadius = UDim.new(0, 8)
local autoStroke = Instance.new("UIStroke", autoCodeBtn)
autoStroke.Color = Color3.fromRGB(0, 200, 255)
autoStroke.Transparency = 0.6
autoStroke.Thickness = 1

-- UPPER / LOWER
local upperBtn = Instance.new("TextButton", main)
upperBtn.Size = UDim2.new(0.5, -13, 0, 24)
upperBtn.Position = UDim2.new(0, 10, 0, 70)
upperBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
upperBtn.BackgroundTransparency = 0.75
upperBtn.BorderSizePixel = 0
upperBtn.Text = "UPPER"
upperBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
upperBtn.Font = Enum.Font.GothamBold
upperBtn.TextSize = 11
Instance.new("UICorner", upperBtn).CornerRadius = UDim.new(0, 6)
local upperStroke = Instance.new("UIStroke", upperBtn)
upperStroke.Color = Color3.fromRGB(0, 200, 255)
upperStroke.Transparency = 0.5
upperStroke.Thickness = 1

local lowerBtn = Instance.new("TextButton", main)
lowerBtn.Size = UDim2.new(0.5, -13, 0, 24)
lowerBtn.Position = UDim2.new(0.5, 3, 0, 70)
lowerBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
lowerBtn.BackgroundTransparency = 0.93
lowerBtn.BorderSizePixel = 0
lowerBtn.Text = "lower"
lowerBtn.TextColor3 = Color3.fromRGB(150, 150, 170)
lowerBtn.Font = Enum.Font.Gotham
lowerBtn.TextSize = 11
Instance.new("UICorner", lowerBtn).CornerRadius = UDim.new(0, 6)
local lowerStroke = Instance.new("UIStroke", lowerBtn)
lowerStroke.Color = Color3.fromRGB(100, 100, 120)
lowerStroke.Transparency = 0.7
lowerStroke.Thickness = 1

-- =====================================================================
-- SELECTEUR DE MOT (numéro du mot à soumettre)
-- =====================================================================
local wordSelLabel = Instance.new("TextLabel", main)
wordSelLabel.Size = UDim2.new(0, 100, 0, 20)
wordSelLabel.Position = UDim2.new(0, 10, 0, 100)
wordSelLabel.BackgroundTransparency = 1
wordSelLabel.Text = "MOT À SUBMIT :"
wordSelLabel.TextColor3 = Color3.fromRGB(120, 200, 230)
wordSelLabel.Font = Enum.Font.GothamBold
wordSelLabel.TextSize = 10
wordSelLabel.TextXAlignment = Enum.TextXAlignment.Left

local wordMinusBtn = Instance.new("TextButton", main)
wordMinusBtn.Size = UDim2.new(0, 26, 0, 20)
wordMinusBtn.Position = UDim2.new(0, 112, 0, 100)
wordMinusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
wordMinusBtn.BorderSizePixel = 0
wordMinusBtn.Text = "-"
wordMinusBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
wordMinusBtn.Font = Enum.Font.GothamBold
wordMinusBtn.TextSize = 14
Instance.new("UICorner", wordMinusBtn).CornerRadius = UDim.new(0, 4)

local wordNumLbl = Instance.new("TextLabel", main)
wordNumLbl.Size = UDim2.new(0, 30, 0, 20)
wordNumLbl.Position = UDim2.new(0, 142, 0, 100)
wordNumLbl.BackgroundTransparency = 1
wordNumLbl.Text = "1"
wordNumLbl.TextColor3 = Color3.fromRGB(255, 220, 80)
wordNumLbl.Font = Enum.Font.GothamBold
wordNumLbl.TextSize = 13
wordNumLbl.TextXAlignment = Enum.TextXAlignment.Center

local wordPlusBtn = Instance.new("TextButton", main)
wordPlusBtn.Size = UDim2.new(0, 26, 0, 20)
wordPlusBtn.Position = UDim2.new(0, 176, 0, 100)
wordPlusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
wordPlusBtn.BorderSizePixel = 0
wordPlusBtn.Text = "+"
wordPlusBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
wordPlusBtn.Font = Enum.Font.GothamBold
wordPlusBtn.TextSize = 14
Instance.new("UICorner", wordPlusBtn).CornerRadius = UDim.new(0, 4)

local wordAllBtn = Instance.new("TextButton", main)
wordAllBtn.Size = UDim2.new(0, 30, 0, 20)
wordAllBtn.Position = UDim2.new(0, 206, 0, 100)
wordAllBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 120)
wordAllBtn.BorderSizePixel = 0
wordAllBtn.Text = "ALL"
wordAllBtn.TextColor3 = Color3.fromRGB(150, 210, 255)
wordAllBtn.Font = Enum.Font.GothamBold
wordAllBtn.TextSize = 9
Instance.new("UICorner", wordAllBtn).CornerRadius = UDim.new(0, 4)

local wordIndex = 1   -- 0 = soumettre tout le texte
local function updateWordDisplay()
    wordNumLbl.Text = wordIndex == 0 and "ALL" or tostring(wordIndex)
end

wordMinusBtn.MouseButton1Click:Connect(function()
    if wordIndex > 1 then wordIndex = wordIndex - 1
    else wordIndex = 0 end
    updateWordDisplay()
end)
wordPlusBtn.MouseButton1Click:Connect(function()
    if wordIndex == 0 then wordIndex = 1
    else wordIndex = wordIndex + 1 end
    updateWordDisplay()
end)
wordAllBtn.MouseButton1Click:Connect(function()
    wordIndex = 0
    updateWordDisplay()
end)

-- =====================================================================
-- LOG des codes reçus (sauvegardés, cliquables pour resoumettre)
-- =====================================================================
local logLabel = Instance.new("TextLabel", main)
logLabel.Size = UDim2.new(1, -20, 0, 14)
logLabel.Position = UDim2.new(0, 10, 0, 128)
logLabel.BackgroundTransparency = 1
logLabel.Text = "CODES REÇUS (clique pour resoumettre)"
logLabel.TextColor3 = Color3.fromRGB(120, 200, 230)
logLabel.Font = Enum.Font.GothamBold
logLabel.TextSize = 9
logLabel.TextXAlignment = Enum.TextXAlignment.Left

local logFrame = Instance.new("Frame", main)
logFrame.Size = UDim2.new(1, -20, 0, 118)
logFrame.Position = UDim2.new(0, 10, 0, 144)
logFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
logFrame.BackgroundTransparency = 0.95
logFrame.BorderSizePixel = 0
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 8)

local logScroll = Instance.new("ScrollingFrame", logFrame)
logScroll.Size = UDim2.new(1, -8, 1, -8)
logScroll.Position = UDim2.new(0, 4, 0, 4)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 3
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local logLayout = Instance.new("UIListLayout", logScroll)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)

local savedCodes = {}  -- liste des codes sauvegardés

local function addSavedCode(code)
    -- pas de doublon
    for _, c in ipairs(savedCodes) do
        if c == code then return end
    end
    table.insert(savedCodes, code)

    local btn = Instance.new("TextButton", logScroll)
    btn.Size = UDim2.new(1, 0, 0, 20)
    btn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    btn.BackgroundTransparency = 0.88
    btn.BorderSizePixel = 0
    btn.Text = code
    btn.TextColor3 = Color3.fromRGB(0, 220, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 11
    btn.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    -- clique → resoumettre
    btn.MouseButton1Click:Connect(function()
        -- typeIntoCodeBox défini plus bas, utilisé via upvalue
        _G._SAB_Submit(code)
    end)

    task.defer(function()
        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end)
end

-- =====================================================================
-- LOGIQUE
-- =====================================================================
local autoCodeEnabled = false
local caseMode = "upper"

local function setCase(mode)
    caseMode = mode
    if mode == "upper" then
        upperBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        upperBtn.BackgroundTransparency = 0.75
        upperBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
        upperStroke.Transparency = 0.5
        lowerBtn.BackgroundTransparency = 0.93
        lowerBtn.TextColor3 = Color3.fromRGB(150, 150, 170)
        lowerStroke.Transparency = 0.7
    else
        lowerBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        lowerBtn.BackgroundTransparency = 0.75
        lowerBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
        lowerStroke.Transparency = 0.5
        upperBtn.BackgroundTransparency = 0.93
        upperBtn.TextColor3 = Color3.fromRGB(150, 150, 170)
        upperStroke.Transparency = 0.7
    end
end
upperBtn.MouseButton1Click:Connect(function() setCase("upper") end)
lowerBtn.MouseButton1Click:Connect(function() setCase("lower") end)

local function openCodesMenu()
    pcall(function()
        local codesBtn = playerGui.LeftCenter.LeftCenter.Buttons.Codes
        for _, conn in ipairs(getconnections(codesBtn.Activated)) do conn:Fire() end
    end)
end

local function isCodesOpen()
    local codesGui = playerGui:FindFirstChild("Codes")
    if codesGui then
        local inner = codesGui:FindFirstChild("Codes")
        if inner then return inner.Visible end
        return codesGui.Enabled
    end
    return false
end

local function findCodeBox()
    -- cherche le TextBox dans n'importe quel GUI Codes ouvert
    for _, gui in ipairs(playerGui:GetChildren()) do
        local box = gui:FindFirstChildWhichIsA("TextBox", true)
        if box then return box end
    end
    return nil
end

local function findSubmitBtn(codeBox)
    -- cherche le bouton Submit proche du TextBox
    local parent = codeBox.Parent
    while parent and parent ~= playerGui do
        for _, d in ipairs(parent:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and d ~= codeBox then
                local t = d.Text:lower()
                if t:find("submit") or t:find("redeem") or t:find("valider") or t:find("confirm") then
                    return d
                end
            end
        end
        parent = parent.Parent
    end
    return nil
end

local function typeIntoCodeBox(rawText)
    local formatted = caseMode == "upper" and rawText:upper() or rawText:lower()

    local codeBox = findCodeBox()
    if not codeBox then print("[SAB] TextBox introuvable") return formatted end

    codeBox:CaptureFocus()
    codeBox.Text = formatted
    task.wait(0.15)

    -- chercher et cliquer Submit
    local submitted = false
    local submitBtn = findSubmitBtn(codeBox)
    if submitBtn then
        pcall(function()
            for _, conn in ipairs(getconnections(submitBtn.Activated)) do
                conn:Fire(); submitted = true; break
            end
        end)
        if not submitted then
            submitBtn:Fire("MouseButton1Click")
            submitted = true
        end
    end

    if not submitted then codeBox:ReleaseFocus(true) end

    print("SUBMITTED:", formatted)
    return formatted
end

-- expose pour les boutons "resoumettre"
_G._SAB_Submit = function(text)
    if not isCodesOpen() then openCodesMenu() task.wait(0.3) end
    typeIntoCodeBox(text)
end

autoCodeBtn.MouseButton1Click:Connect(function()
    autoCodeEnabled = not autoCodeEnabled
    if autoCodeEnabled then
        autoCodeBtn.Text = "AUTO CODE: ON"
        autoCodeBtn.TextColor3 = Color3.fromRGB(80, 255, 160)
        autoStroke.Color = Color3.fromRGB(80, 255, 160)
        task.spawn(function()
            while autoCodeEnabled do
                if not isCodesOpen() then openCodesMenu() end
                task.wait(0.5)
            end
        end)
    else
        autoCodeEnabled = false
        autoCodeBtn.Text = "AUTO CODE: OFF"
        autoCodeBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
        autoStroke.Color = Color3.fromRGB(0, 200, 255)
    end
end)

-- =====================================================================
-- RIDDLE TABLE
-- =====================================================================
local riddleTable = {
    { keywords = {"mutation", "favourite"}, answer = "Candy24Sammy" },
    { keywords = {"admin", "wars"},         answer = "" },
    { keywords = {"2nd mutation"},          answer = "" },
    { keywords = {"favourite", "brainrot"}, answer = "" },
    { keywords = {"facts", "owner"},        answer = "" },
}

local function findRiddleAnswer(text)
    local lowerText = text:lower()
    for _, entry in ipairs(riddleTable) do
        if entry.answer ~= "" then
            local allFound = true
            for _, kw in ipairs(entry.keywords) do
                if not lowerText:find(kw:lower(), 1, true) then allFound = false break end
            end
            if allFound then return entry.answer end
        end
    end
    return nil
end

-- =====================================================================
-- HANDLER NOTIFICATION — choisit le bon mot selon wordIndex
-- =====================================================================
local lastHandled = ""
local lastHandledTime = 0

local function handleNotificationText(text)
    if text == "" then return end
    local now = tick()
    if text == lastHandled and (now - lastHandledTime) < 3 then return end
    lastHandled = text
    lastHandledTime = now

    if not autoCodeEnabled then return end

    -- vérifier riddle d'abord
    local riddleAnswer = findRiddleAnswer(text)
    local toSubmit

    if riddleAnswer then
        toSubmit = riddleAnswer
    else
        if wordIndex == 0 then
            -- soumettre tout le texte
            toSubmit = text
        else
            -- extraire le Nième mot
            local words = {}
            for w in text:gmatch("%S+") do table.insert(words, w) end
            toSubmit = words[wordIndex]
        end
    end

    if not toSubmit or toSubmit == "" then return end

    -- sauvegarder
    addSavedCode(toSubmit)

    -- ouvrir et soumettre
    if not isCodesOpen() then openCodesMenu() task.wait(0.3) end
    typeIntoCodeBox(toSubmit)
end

local handledInstances = {}

playerGui.DescendantAdded:Connect(function(v)
    if v:IsA("TextLabel") and v.Name == "Template" and v:FindFirstAncestor("TopNotification") then
        if handledInstances[v] then return end
        handledInstances[v] = true

        -- attendre que le texte soit non-vide
        task.spawn(function()
            local waited = 0
            while v.Parent and (v.Text == "" or v.Text == nil) and waited < 2 do
                task.wait(0.1)
                waited = waited + 0.1
            end
            if v.Text and v.Text ~= "" then
                handleNotificationText(v.Text)
            end
            -- nettoyer après
            task.wait(5)
            handledInstances[v] = nil
        end)
    end
end)

-- =====================================================================
-- FENETRE RIDDLE SOLVER
-- =====================================================================
local riddleWin = Instance.new("Frame", screenGui)
riddleWin.Name = "RiddleSolver"
riddleWin.Size = UDim2.new(0, 240, 0, 168)
riddleWin.Position = UDim2.new(0.5, -120, 0, 310)
riddleWin.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
riddleWin.BackgroundTransparency = 0.1
riddleWin.BorderSizePixel = 0
riddleWin.Active = true
riddleWin.Draggable = true
Instance.new("UICorner", riddleWin).CornerRadius = UDim.new(0, 14)
local riddleStroke = Instance.new("UIStroke", riddleWin)
riddleStroke.Color = Color3.fromRGB(255, 170, 60)
riddleStroke.Transparency = 0.6
riddleStroke.Thickness = 1

local riddleHeader = Instance.new("Frame", riddleWin)
riddleHeader.Size = UDim2.new(1, 0, 0, 30)
riddleHeader.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
riddleHeader.BackgroundTransparency = 0.85
riddleHeader.BorderSizePixel = 0
Instance.new("UICorner", riddleHeader).CornerRadius = UDim.new(0, 14)
local riddleDot = Instance.new("Frame", riddleHeader)
riddleDot.Size = UDim2.new(0, 7, 0, 7)
riddleDot.Position = UDim2.new(0, 12, 0.5, -3)
riddleDot.BackgroundColor3 = Color3.fromRGB(255, 190, 90)
riddleDot.BorderSizePixel = 0
Instance.new("UICorner", riddleDot).CornerRadius = UDim.new(1, 0)
local riddleTitleLbl = Instance.new("TextLabel", riddleHeader)
riddleTitleLbl.Size = UDim2.new(1, -24, 1, 0)
riddleTitleLbl.Position = UDim2.new(0, 24, 0, 0)
riddleTitleLbl.BackgroundTransparency = 1
riddleTitleLbl.Text = "RIDDLE SOLVER"
riddleTitleLbl.TextColor3 = Color3.fromRGB(255, 190, 90)
riddleTitleLbl.Font = Enum.Font.GothamBold
riddleTitleLbl.TextSize = 11
riddleTitleLbl.TextXAlignment = Enum.TextXAlignment.Left

local riddleInputFrame = Instance.new("Frame", riddleWin)
riddleInputFrame.Size = UDim2.new(1, -20, 0, 56)
riddleInputFrame.Position = UDim2.new(0, 10, 0, 38)
riddleInputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
riddleInputFrame.BackgroundTransparency = 0.95
riddleInputFrame.BorderSizePixel = 0
Instance.new("UICorner", riddleInputFrame).CornerRadius = UDim.new(0, 8)

local riddleInputBox = Instance.new("TextBox", riddleInputFrame)
riddleInputBox.Size = UDim2.new(1, -12, 1, -8)
riddleInputBox.Position = UDim2.new(0, 6, 0, 4)
riddleInputBox.BackgroundTransparency = 1
riddleInputBox.PlaceholderText = "Paste riddle text here..."
riddleInputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
riddleInputBox.Text = ""
riddleInputBox.TextColor3 = Color3.fromRGB(230, 230, 235)
riddleInputBox.Font = Enum.Font.Gotham
riddleInputBox.TextSize = 12
riddleInputBox.TextWrapped = true
riddleInputBox.MultiLine = true
riddleInputBox.ClearTextOnFocus = false
riddleInputBox.TextXAlignment = Enum.TextXAlignment.Left
riddleInputBox.TextYAlignment = Enum.TextYAlignment.Top

local riddleResultLabel = Instance.new("TextLabel", riddleWin)
riddleResultLabel.Size = UDim2.new(1, -20, 0, 16)
riddleResultLabel.Position = UDim2.new(0, 10, 0, 98)
riddleResultLabel.BackgroundTransparency = 1
riddleResultLabel.Text = "Answer will appear here"
riddleResultLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
riddleResultLabel.Font = Enum.Font.GothamBold
riddleResultLabel.TextSize = 11
riddleResultLabel.TextWrapped = true
riddleResultLabel.TextXAlignment = Enum.TextXAlignment.Left

local solveBtn = Instance.new("TextButton", riddleWin)
solveBtn.Size = UDim2.new(0.6, -13, 0, 26)
solveBtn.Position = UDim2.new(0, 10, 0, 130)
solveBtn.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
solveBtn.BackgroundTransparency = 0.75
solveBtn.BorderSizePixel = 0
solveBtn.Text = "SOLVE & SUBMIT"
solveBtn.TextColor3 = Color3.fromRGB(255, 200, 110)
solveBtn.Font = Enum.Font.GothamBold
solveBtn.TextSize = 11
Instance.new("UICorner", solveBtn).CornerRadius = UDim.new(0, 6)

local clearBtn = Instance.new("TextButton", riddleWin)
clearBtn.Size = UDim2.new(0.4, -7, 0, 26)
clearBtn.Position = UDim2.new(0.6, 10, 0, 130)
clearBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.BackgroundTransparency = 0.93
clearBtn.BorderSizePixel = 0
clearBtn.Text = "CLEAR"
clearBtn.TextColor3 = Color3.fromRGB(150, 150, 170)
clearBtn.Font = Enum.Font.Gotham
clearBtn.TextSize = 11
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 6)

solveBtn.MouseButton1Click:Connect(function()
    local txt = riddleInputBox.Text
    if not txt or txt:gsub("%s","") == "" then
        riddleResultLabel.Text = "Type or paste a riddle first"
        riddleResultLabel.TextColor3 = Color3.fromRGB(255,170,60)
        return
    end
    local answer = findRiddleAnswer(txt)
    if answer then
        _G._SAB_Submit(answer)
        addSavedCode(answer)
        riddleResultLabel.Text = "Submitted: " .. answer
        riddleResultLabel.TextColor3 = Color3.fromRGB(80,255,160)
    else
        riddleResultLabel.Text = "No match in riddle table"
        riddleResultLabel.TextColor3 = Color3.fromRGB(255,100,100)
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    riddleInputBox.Text = ""
    riddleResultLabel.Text = "Answer will appear here"
    riddleResultLabel.TextColor3 = Color3.fromRGB(150,150,170)
end)
