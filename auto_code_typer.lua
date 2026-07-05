if not game:IsLoaded() then game.Loaded:Wait() end

local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Players          = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Nettoyer ancienne instance
if playerGui:FindFirstChild("SwaveHub") then
    playerGui.SwaveHub:Destroy()
end

-- ============================================================
-- CONFIG
-- ============================================================
local ACCENT   = Color3.fromRGB(88, 166, 255)
local BG_DARK  = Color3.fromRGB(12, 14, 22)
local BG_ROW   = Color3.fromRGB(20, 24, 36)
local BG_BTN   = Color3.fromRGB(30, 35, 52)
local BG_ON    = Color3.fromRGB(49, 130, 255)
local TXT_DIM  = Color3.fromRGB(130, 140, 165)
local TXT_WHT  = Color3.fromRGB(220, 225, 235)
local tw       = TweenInfo.new(0.18, Enum.EasingStyle.Quad)

-- ============================================================
-- ÉTAT
-- ============================================================
local monitoring  = false
local autoWrite   = true
local autoSubmit  = true
local submitAfter = 3      -- soumettre la Nième notif
local caseMode    = "upper"-- "normal" | "upper" | "lower"
local connexions  = {}

local notifCounter   = 0
local lastNotifTime  = 0
local lastText       = ""

-- ============================================================
-- SCREEN GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "SwaveHub"
screenGui.ResetOnSpawn  = false
screenGui.IgnoreGuiInset = true
screenGui.Parent        = playerGui

local W, H = 330, 230

local main = Instance.new("Frame")
main.Size             = UDim2.new(0, W, 0, H)
main.Position         = UDim2.new(0.5, -W/2, 0, 20)
main.BackgroundColor3 = BG_DARK
main.BorderSizePixel  = 0
main.Active           = true
main.Parent           = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Thickness = 1.5
mainStroke.Color     = Color3.fromRGB(35, 42, 65)

-- ============================================================
-- HEADER
-- ============================================================
local header = Instance.new("Frame", main)
header.Size             = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = BG_ROW
header.BorderSizePixel  = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

-- coins inférieurs du header carrés
local headerBottom = Instance.new("Frame", header)
headerBottom.Size             = UDim2.new(1, 0, 0.5, 0)
headerBottom.Position         = UDim2.new(0, 0, 0.5, 0)
headerBottom.BackgroundColor3 = BG_ROW
headerBottom.BorderSizePixel  = 0

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(0, 160, 1, 0)
titleLbl.Position           = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "SwaveHub"
titleLbl.TextColor3         = TXT_WHT
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left

local serverLbl = Instance.new("TextLabel", header)
serverLbl.Size              = UDim2.new(0, 140, 1, 0)
serverLbl.Position          = UDim2.new(0, 95, 0, 0)
serverLbl.BackgroundTransparency = 1
serverLbl.Text              = ".gg/NEW5D2C4sC"
serverLbl.TextColor3        = TXT_DIM
serverLbl.Font              = Enum.Font.Gotham
serverLbl.TextSize          = 11
serverLbl.TextXAlignment    = Enum.TextXAlignment.Left

-- Boutons header (? - X)
local function makeHeaderBtn(txt, xOff, col)
    local b = Instance.new("TextButton", header)
    b.Size             = UDim2.new(0, 22, 0, 22)
    b.Position         = UDim2.new(1, xOff, 0.5, -11)
    b.BackgroundColor3 = BG_BTN
    b.BorderSizePixel  = 0
    b.Text             = txt
    b.TextColor3       = col or TXT_DIM
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 11
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end
local helpBtn  = makeHeaderBtn("?",  -72, TXT_DIM)
local minBtn   = makeHeaderBtn("−",  -46, TXT_DIM)
local closeBtn = makeHeaderBtn("X",  -20, Color3.fromRGB(231, 76, 60))

-- ============================================================
-- HELPER : créer une ligne label + widget(s)
-- ============================================================
local function makeRow(yPos, labelText)
    local row = Instance.new("Frame", main)
    row.Size             = UDim2.new(1, -20, 0, 32)
    row.Position         = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = BG_ROW
    row.BorderSizePixel  = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size               = UDim2.new(0, 160, 1, 0)
    lbl.Position           = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text               = labelText
    lbl.TextColor3         = TXT_DIM
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = 12
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    return row
end

local function makeBtn(parent, txt, xOff, w, col)
    local b = Instance.new("TextButton", parent)
    b.Size             = UDim2.new(0, w or 52, 0, 22)
    b.Position         = UDim2.new(1, -(xOff or 60), 0.5, -11)
    b.BackgroundColor3 = col or BG_BTN
    b.BorderSizePixel  = 0
    b.Text             = txt
    b.TextColor3       = TXT_WHT
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 11
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

-- ============================================================
-- ROW 1 : Monitoring Active
-- ============================================================
local row1     = makeRow(44, "Monitoring Active:")
local startBtn = makeBtn(row1, "Start", 118, 52, Color3.fromRGB(49,130,255))
local stopBtn  = makeBtn(row1, "Stop",  60,  52, BG_BTN)

-- ============================================================
-- ROW 2 : Text Formatting
-- ============================================================
local row2      = makeRow(82, "Text Formatting:")
local btnNormal = makeBtn(row2, "Normal", 182, 56, BG_BTN)
local btnUpper  = makeBtn(row2, "UPPER",  120, 56, BG_ON)
local btnLower  = makeBtn(row2, "lower",   58, 56, BG_BTN)

-- ============================================================
-- ROW 3 : Auto-Write
-- ============================================================
local row3         = makeRow(120, "Auto-Write:")
local autoWriteBtn = makeBtn(row3, "ON", 62, 52, BG_ON)

-- ============================================================
-- ROW 4 : Auto-Submit
-- ============================================================
local row4           = makeRow(158, "Auto-Submit (Max Speed):")
local autoSubmitBtn  = makeBtn(row4, "ON", 62, 52, BG_ON)

-- ============================================================
-- ROW 5 : Submit after (#)
-- ============================================================
local row5    = makeRow(196, "Submit after (#):")

local subMinus = makeBtn(row5, "−", 106, 26, BG_BTN)
local subNumLbl = Instance.new("TextLabel", row5)
subNumLbl.Size               = UDim2.new(0, 26, 0, 22)
subNumLbl.Position           = UDim2.new(1, -78, 0.5, -11)
subNumLbl.BackgroundTransparency = 1
subNumLbl.Text               = tostring(submitAfter)
subNumLbl.TextColor3         = TXT_WHT
subNumLbl.Font               = Enum.Font.GothamBold
subNumLbl.TextSize           = 13
subNumLbl.TextXAlignment     = Enum.TextXAlignment.Center
local subPlus = makeBtn(row5, "+", 50, 26, BG_BTN)

-- ============================================================
-- STATUS BAR
-- ============================================================
local statusBar = Instance.new("Frame", main)
statusBar.Size             = UDim2.new(1, -20, 0, 22)
statusBar.Position         = UDim2.new(0, 10, 1, -28)
statusBar.BackgroundColor3 = BG_ROW
statusBar.BorderSizePixel  = 0
Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0, 6)

local statusLbl = Instance.new("TextLabel", statusBar)
statusLbl.Size               = UDim2.new(1, -10, 1, 0)
statusLbl.Position           = UDim2.new(0, 8, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text               = "Status: En attente..."
statusLbl.TextColor3         = TXT_DIM
statusLbl.Font               = Enum.Font.Gotham
statusLbl.TextSize           = 10
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left

local function setStatus(txt, col)
    statusLbl.Text       = "Status: " .. txt
    statusLbl.TextColor3 = col or TXT_DIM
end

-- ============================================================
-- DRAG
-- ============================================================
do
    local dragging, dragStart, startPos, dragInput
    header.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = inp.Position; startPos = main.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    header.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then dragInput = inp end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if inp == dragInput and dragging then
            local d = inp.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                      startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ============================================================
-- HELPERS UI
-- ============================================================
local function setToggle(btn, state)
    TweenService:Create(btn, tw, {
        BackgroundColor3 = state and BG_ON or BG_BTN
    }):Play()
    btn.Text = state and "ON" or "OFF"
end

local function setFormatBtn(mode)
    caseMode = mode
    TweenService:Create(btnNormal, tw, {BackgroundColor3 = mode=="normal" and BG_ON or BG_BTN}):Play()
    TweenService:Create(btnUpper,  tw, {BackgroundColor3 = mode=="upper"  and BG_ON or BG_BTN}):Play()
    TweenService:Create(btnLower,  tw, {BackgroundColor3 = mode=="lower"  and BG_ON or BG_BTN}):Play()
end

local function setMonitoring(state)
    monitoring = state
    TweenService:Create(startBtn, tw, {BackgroundColor3 = state and BG_ON or BG_BTN}):Play()
    TweenService:Create(stopBtn,  tw, {BackgroundColor3 = state and BG_BTN or Color3.fromRGB(180,40,40)}):Play()
    setStatus(state and "Monitoring actif" or "Monitoring arrêté",
              state and Color3.fromRGB(80,200,120) or TXT_DIM)
end

-- ============================================================
-- LOGIQUE : trouver le code box du jeu
-- ============================================================
local function findCodeBox()
    local ok, box = pcall(function() return playerGui.Codes.Codes.CodeRedeem.TextBox end)
    if ok and box and box:IsA("TextBox") then return box end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui.Name == "SwaveHub" then continue end
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextBox") then
                local n  = d.Name:lower()
                local p  = d.Parent and d.Parent.Name:lower() or ""
                local ph = (d.PlaceholderText or ""):lower()
                if n:find("code") or p:find("code") or p:find("redeem") or ph:find("code") or ph:find("ici") then
                    return d
                end
            end
        end
    end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui.Name == "SwaveHub" then continue end
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextBox") and d.Visible then return d end
        end
    end
    return nil
end

local function openCodesMenu()
    pcall(function()
        local codesBtn = playerGui.LeftCenter.LeftCenter.Buttons.Codes
        for _, c in ipairs(getconnections(codesBtn.Activated)) do c:Fire() end
    end)
end

local function isCodesOpen()
    local g = playerGui:FindFirstChild("Codes")
    if g then
        local inner = g:FindFirstChild("Codes")
        if inner then return inner.Visible end
        return g.Enabled
    end
    return false
end

local function waitForCodeBox()
    local deadline = tick() + 3
    local box
    repeat box = findCodeBox(); if not box then task.wait(0.1) end
    until box or tick() > deadline
    return box
end

local function formatText(raw)
    if caseMode == "upper"  then return raw:upper() end
    if caseMode == "lower"  then return raw:lower() end
    return raw
end

-- Écrit seulement (depuis la liste sauvegardée)
local function typeOnly(rawText)
    local txt = formatText(rawText)
    if not isCodesOpen() then openCodesMenu(); task.wait(0.5) end
    local box = waitForCodeBox()
    if not box then setStatus("Box introuvable", Color3.fromRGB(231,76,60)); return end
    box.Text = txt
    box:CaptureFocus()
    setStatus("Écrit: " .. txt, Color3.fromRGB(255,220,80))
end

-- Écrit ET soumet
local function typeAndSubmit(rawText)
    local txt = formatText(rawText)
    if not isCodesOpen() then openCodesMenu(); task.wait(0.5) end
    local box = waitForCodeBox()
    if not box then setStatus("Box introuvable", Color3.fromRGB(231,76,60)); return end

    box.Text = txt
    box:CaptureFocus()
    task.wait(0.1)

    if autoSubmit then
        local submitted = false
        pcall(function()
            local codesGui = playerGui:FindFirstChild("Codes")
            if not codesGui then return end
            for _, d in ipairs(codesGui:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
                    local n = d.Name:lower()
                    if n:find("submit") or n:find("redeem") or n:find("confirm") then
                        for _, c in ipairs(getconnections(d.Activated)) do c:Fire(); submitted = true; break end
                    end
                end
                if submitted then break end
            end
        end)
        if not submitted then box:ReleaseFocus(true); submitted = true end
        setStatus("Submitted: " .. txt .. (submitted and " ✓" or ""), Color3.fromRGB(80,200,120))
    else
        setStatus("Écrit: " .. txt .. " (submit OFF)", Color3.fromRGB(255,220,80))
    end
end

-- ============================================================
-- LOGIQUE : détection des notifications
-- ============================================================
local savedCodes = {}

local function addSavedCode(code)
    for _, c in ipairs(savedCodes) do if c == code then return end end
    table.insert(savedCodes, code)
end

local function handleNotif(text)
    if not monitoring or text == "" then return end
    if text == lastText then return end
    lastText = text

    local now = tick()
    if (now - lastNotifTime) > 3 then notifCounter = 0 end
    lastNotifTime = now
    notifCounter  = notifCounter + 1

    addSavedCode(text)
    setStatus("Notif #" .. notifCounter .. ": " .. text:sub(1,28), TXT_DIM)

    if notifCounter ~= submitAfter then return end

    if autoWrite then
        typeAndSubmit(text)
    end
end

local function connectDescendant(obj)
    if obj:IsA("TextLabel") or obj:IsA("TextBox") then
        local c = obj:GetPropertyChangedSignal("Text"):Connect(function()
            handleNotif(obj.Text)
        end)
        table.insert(connexions, c)
        if obj.Text ~= "" then handleNotif(obj.Text) end
    end
end

-- Brancher sur TopNotification
local topNotif = playerGui:FindFirstChild("TopNotification")
if topNotif then
    for _, d in ipairs(topNotif:GetDescendants()) do connectDescendant(d) end
    local c = topNotif.DescendantAdded:Connect(connectDescendant)
    table.insert(connexions, c)
end

-- Fallback : DescendantAdded sur playerGui (Template labels)
local pgConn = playerGui.DescendantAdded:Connect(function(v)
    if v:IsA("TextLabel") and v.Name == "Template" and v:FindFirstAncestor("TopNotification") then
        task.defer(function()
            handleNotif(v.Text)
            local c = v:GetPropertyChangedSignal("Text"):Connect(function() handleNotif(v.Text) end)
            table.insert(connexions, c)
        end)
    end
end)
table.insert(connexions, pgConn)

-- ============================================================
-- BOUTONS UI
-- ============================================================
startBtn.MouseButton1Click:Connect(function() setMonitoring(true) end)
stopBtn.MouseButton1Click:Connect(function()  setMonitoring(false) end)

btnNormal.MouseButton1Click:Connect(function() setFormatBtn("normal") end)
btnUpper.MouseButton1Click:Connect(function()  setFormatBtn("upper") end)
btnLower.MouseButton1Click:Connect(function()  setFormatBtn("lower") end)

autoWriteBtn.MouseButton1Click:Connect(function()
    autoWrite = not autoWrite
    setToggle(autoWriteBtn, autoWrite)
end)

autoSubmitBtn.MouseButton1Click:Connect(function()
    autoSubmit = not autoSubmit
    setToggle(autoSubmitBtn, autoSubmit)
end)

subMinus.MouseButton1Click:Connect(function()
    if submitAfter > 1 then submitAfter = submitAfter - 1 end
    subNumLbl.Text = tostring(submitAfter)
end)
subPlus.MouseButton1Click:Connect(function()
    submitAfter = submitAfter + 1
    subNumLbl.Text = tostring(submitAfter)
end)

-- Fermeture
closeBtn.MouseButton1Click:Connect(function()
    monitoring = false
    for _, c in ipairs(connexions) do pcall(function() c:Disconnect() end) end
    TweenService:Create(main, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
    task.wait(0.22)
    screenGui:Destroy()
end)

-- Minimiser
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local targetH = minimized and 36 or H
    TweenService:Create(main, tw, {Size = UDim2.new(0, W, 0, targetH)}):Play()
end)

-- ============================================================
print("[SwaveHub] Prêt — clique Start pour activer")
