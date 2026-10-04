--[[ Bobaaboba Script v3.0 (Roblox Studio testing)
Setup: LocalScript in StarterPlayer > StarterPlayerScripts.
Open/close the menu with the "B" logo or the M key.
Aimbot works while the right mouse button is held. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Camera = workspace.CurrentCamera
local LP = Players.LocalPlayer

local Settings = {
	Aimbot = false,
	ESP = false,
	InfiniteJump = false,
	Fly = false,
	Triggerbot = false,
	FOV = false,
	Hitboxes = false,
	Attach = false,
	Invisible = false,
	FOVSize = 150,
	HitboxSize = 10,
	Target = nil, -- selected player (spectate / attach)
}

-- All connections, so they can be disconnected on unload
local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local OriginalHitboxes = {}
local OriginalTransparency = {}
local attachWeld = nil

local HL_NAME = "BB_ESP_Highlight"
local TAG_NAME = "BB_ESP_Tag"

local function getHumanoid(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Spectate -----------------------------------------------------
local function stopSpectate()
	Settings.Target = nil
	local hum = getHumanoid(LP.Character)
	if hum then
		Camera.CameraSubject = hum
	end
end

local function startSpectate(player)
	Settings.Target = player
	local hum = getHumanoid(player.Character)
	if hum then
		Camera.CameraSubject = hum
	end
end

-- ESP: red outline Highlight (no fill) + white "Name HP: 57" tag --
local function clearESP()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			for _, name in ipairs({ HL_NAME, TAG_NAME }) do
				local obj = char:FindFirstChild(name)
				if obj then
					obj:Destroy()
				end
			end
		end
	end
end

local function updateESP()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= LP and p.Character
		local hum = char and getHumanoid(char)
		local head = char and char:FindFirstChild("Head")
		if char and hum and head then
			if not char:FindFirstChild(HL_NAME) then
				local hl = Instance.new("Highlight")
				hl.Name = HL_NAME
				hl.Adornee = char
				hl.FillTransparency = 1 -- no fill
				hl.OutlineColor = Color3.fromRGB(255, 0, 0)
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = char
			end

			local tag = char:FindFirstChild(TAG_NAME)
			if not tag then
				tag = Instance.new("BillboardGui")
				tag.Name = TAG_NAME
				tag.Adornee = head
				tag.Size = UDim2.new(0, 200, 0, 24)
				tag.StudsOffset = Vector3.new(0, 2.5, 0)
				tag.AlwaysOnTop = true
				tag.Parent = char

				local label = Instance.new("TextLabel")
				label.Name = "Label"
				label.Size = UDim2.new(1, 0, 1, 0)
				label.BackgroundTransparency = 1
				label.TextColor3 = Color3.fromRGB(255, 255, 255)
				label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
				label.TextStrokeTransparency = 0
				label.TextSize = 14
				label.Font = Enum.Font.GothamBold
				label.Parent = tag
			end
			tag.Label.Text = string.format("%s HP: %d", p.Name, math.floor(hum.Health + 0.5))
		end
	end
end

-- Hitboxes -----------------------------------------------------
local function updateHitboxes()
	local s = Settings.HitboxSize
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			if not OriginalHitboxes[hrp] then
				OriginalHitboxes[hrp] = {
					Size = hrp.Size,
					Transparency = hrp.Transparency,
					CanCollide = hrp.CanCollide,
				}
			end
			hrp.Size = Vector3.new(s, s, s)
			hrp.Transparency = 0.5
			hrp.CanCollide = false
		end
	end
end

local function restoreHitboxes()
	for hrp, data in pairs(OriginalHitboxes) do
		if hrp.Parent then
			hrp.Size = data.Size
			hrp.Transparency = data.Transparency
			hrp.CanCollide = data.CanCollide
		end
	end
	table.clear(OriginalHitboxes)
end

-- Invisibility -------------------------------------------------
local function setInvisible(state)
	local char = LP.Character
	if not char then
		return
	end
	for _, v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") or v:IsA("Decal") then
			if state then
				if OriginalTransparency[v] == nil then
					OriginalTransparency[v] = v.Transparency
				end
				v.Transparency = 1
			elseif OriginalTransparency[v] ~= nil then
				v.Transparency = OriginalTransparency[v]
				OriginalTransparency[v] = nil
			end
		end
	end
end

-- Attach: welds your character to the target with a WeldConstraint
local function detach()
	if attachWeld then
		attachWeld:Destroy()
		attachWeld = nil
	end
end

local function updateAttach()
	local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	local target = Settings.Target
	local targetHrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")

	if not (Settings.Attach and myHrp and targetHrp) then
		detach()
		return
	end

	-- Re-create the weld if the characters changed (respawn etc.)
	if attachWeld and (not attachWeld.Parent or attachWeld.Part0 ~= myHrp or attachWeld.Part1 ~= targetHrp) then
		detach()
	end

	if not attachWeld then
		-- Move behind the target first, then weld: the weld keeps this relative offset
		myHrp.CFrame = targetHrp.CFrame * CFrame.new(0, 0, 3)
		local weld = Instance.new("WeldConstraint")
		weld.Name = "BB_AttachWeld"
		weld.Part0 = myHrp
		weld.Part1 = targetHrp
		weld.Parent = myHrp
		attachWeld = weld
	end
end

-- Closest player to the cursor inside radius (pixels)
local function getClosestTarget(radius)
	local mouse = UserInputService:GetMouseLocation()
	local bestPart, bestDist = nil, radius
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local hum = getHumanoid(p.Character)
			local part = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and part then
				local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
				if onScreen then
					local d = (Vector2.new(pos.X, pos.Y) - mouse).Magnitude
					if d < bestDist then
						bestPart, bestDist = part, d
					end
				end
			end
		end
	end
	return bestPart
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Bobaaboba"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LP:WaitForChild("PlayerGui")

-- Separate GUI for the FOV circle (IgnoreGuiInset so it matches the cursor position)
local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "BobaabobaOverlay"
OverlayGui.ResetOnSpawn = false
OverlayGui.IgnoreGuiInset = true
OverlayGui.Parent = LP.PlayerGui

local FOVCircle = Instance.new("Frame")
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.BackgroundTransparency = 1
FOVCircle.Visible = false
FOVCircle.Parent = OverlayGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircle

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 2
FOVStroke.Color = Color3.fromRGB(0, 255, 0)
FOVStroke.Parent = FOVCircle

-- Main window ---------------------------------------------------
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 350, 0, 500)
MainFrame.Position = UDim2.new(0.5, -175, 0.5, -250)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 35)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 15)
UICorner.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 15)
TitleCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "Bobaaboba Script"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 14
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 10)
CloseCorner.Parent = CloseBtn

-- Collapsed state: small square "B" logo -------------------------
local Logo = Instance.new("TextButton")
Logo.Name = "Logo"
Logo.Size = UDim2.new(0, 50, 0, 50)
Logo.Position = UDim2.new(0, 20, 0.5, -25)
Logo.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
Logo.Text = "B"
Logo.TextColor3 = Color3.fromRGB(255, 255, 255)
Logo.TextSize = 28
Logo.Font = Enum.Font.GothamBold
Logo.AutoButtonColor = true
Logo.Parent = ScreenGui

local LogoCorner = Instance.new("UICorner")
LogoCorner.CornerRadius = UDim.new(0.25, 0) -- 0.25 Scale
LogoCorner.Parent = Logo

local LogoStroke = Instance.new("UIStroke")
LogoStroke.Thickness = 2
LogoStroke.Color = Color3.fromRGB(0, 200, 255)
LogoStroke.Parent = Logo

local function setMenuOpen(open)
	MainFrame.Visible = open
	Logo.Visible = not open
end

connect(Logo.MouseButton1Click, function()
	setMenuOpen(true)
end)

connect(CloseBtn.MouseButton1Click, function()
	setMenuOpen(false) -- collapses back to the "B" logo
end)

-- Window dragging
local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

connect(TitleBar.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = MainFrame.Position
	end
end)

connect(TitleBar.InputChanged, function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		dragInput = input
	end
end)

connect(UserInputService.InputChanged, function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		MainFrame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

connect(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

-- Scrolling list of controls
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, 0, 1, -50)
ScrollFrame.Position = UDim2.new(0, 0, 0, 45)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 5
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = MainFrame

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 8)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = ScrollFrame

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 5)
ListPadding.PaddingBottom = UDim.new(0, 5)
ListPadding.Parent = ScrollFrame

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function CreateButton(text, callback, color)
	local base = color or Color3.fromRGB(40, 40, 80)
	local hover = color or Color3.fromRGB(60, 60, 120)

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(0.9, 0, 0, 35)
	Button.BackgroundColor3 = base
	Button.Text = text
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.TextSize = 14
	Button.Font = Enum.Font.Gotham
	Button.LayoutOrder = nextOrder()
	Button.Parent = ScrollFrame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 10)
	Corner.Parent = Button

	connect(Button.MouseEnter, function()
		TweenService:Create(Button, TweenInfo.new(0.2), { BackgroundColor3 = hover }):Play()
	end)
	connect(Button.MouseLeave, function()
		TweenService:Create(Button, TweenInfo.new(0.2), { BackgroundColor3 = base }):Play()
	end)
	connect(Button.MouseButton1Click, callback)
	return Button
end

-- onOff runs when the toggle is switched off (cleanup)
local function CreateToggle(text, setting, onOff)
	local Toggle = Instance.new("TextButton")
	Toggle.Size = UDim2.new(0.9, 0, 0, 35)
	Toggle.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
	Toggle.Text = text .. " [OFF]"
	Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	Toggle.TextSize = 14
	Toggle.Font = Enum.Font.Gotham
	Toggle.LayoutOrder = nextOrder()
	Toggle.Parent = ScrollFrame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 10)
	Corner.Parent = Toggle

	connect(Toggle.MouseButton1Click, function()
		Settings[setting] = not Settings[setting]
		Toggle.Text = text .. (Settings[setting] and " [ON]" or " [OFF]")
		Toggle.BackgroundColor3 = Settings[setting] and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(40, 40, 80)
		if not Settings[setting] and onOff then
			onOff()
		end
	end)
	return Toggle
end

local function CreateSlider(text, setting, min, max, default)
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(0.9, 0, 0, 50)
	Frame.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
	Frame.LayoutOrder = nextOrder()
	Frame.Parent = ScrollFrame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 10)
	Corner.Parent = Frame

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 20)
	Label.BackgroundTransparency = 1
	Label.Text = text .. ": " .. default
	Label.TextColor3 = Color3.fromRGB(255, 255, 255)
	Label.TextSize = 12
	Label.Font = Enum.Font.Gotham
	Label.Parent = Frame

	local Slider = Instance.new("TextButton")
	Slider.Size = UDim2.new(0.9, 0, 0, 15)
	Slider.Position = UDim2.new(0.05, 0, 0, 25)
	Slider.BackgroundColor3 = Color3.fromRGB(100, 100, 150)
	Slider.Text = ""
	Slider.AutoButtonColor = false
	Slider.Parent = Frame

	local SliderCorner = Instance.new("UICorner")
	SliderCorner.CornerRadius = UDim.new(0, 7)
	SliderCorner.Parent = Slider

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
	Fill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
	Fill.BorderSizePixel = 0
	Fill.Parent = Slider

	local FillCorner = Instance.new("UICorner")
	FillCorner.CornerRadius = UDim.new(0, 7)
	FillCorner.Parent = Fill

	Settings[setting] = default

	local sliding = false
	local function update(x)
		local a = math.clamp((x - Slider.AbsolutePosition.X) / Slider.AbsoluteSize.X, 0, 1)
		local value = math.floor(min + (max - min) * a)
		Settings[setting] = value
		Fill.Size = UDim2.new(a, 0, 1, 0)
		Label.Text = text .. ": " .. value
	end

	connect(Slider.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = true
			update(input.Position.X)
		end
	end)

	-- Global listeners so the slider keeps working when the cursor leaves it
	connect(UserInputService.InputChanged, function(input)
		if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
			update(input.Position.X)
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = false
		end
	end)
end

-- Player picker (spectate / attach target) ----------------------
local ListGui = nil

local function ClosePlayerList()
	if ListGui then
		ListGui:Destroy()
		ListGui = nil
	end
end

local function OpenPlayerList()
	ClosePlayerList() -- never open two lists at once

	ListGui = Instance.new("ScreenGui")
	ListGui.Name = "BobaabobaPlayerList"
	ListGui.ResetOnSpawn = false
	ListGui.Parent = LP.PlayerGui

	local ListFrame = Instance.new("Frame")
	ListFrame.Size = UDim2.new(0, 200, 0, 300)
	ListFrame.Position = UDim2.new(0.5, -100, 0.5, -150)
	ListFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 35)
	ListFrame.BorderSizePixel = 0
	ListFrame.Parent = ListGui

	local ListCorner = Instance.new("UICorner")
	ListCorner.CornerRadius = UDim.new(0, 10)
	ListCorner.Parent = ListFrame

	local ListTitle = Instance.new("TextLabel")
	ListTitle.Size = UDim2.new(1, 0, 0, 30)
	ListTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
	ListTitle.Text = "Select player"
	ListTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	ListTitle.TextSize = 14
	ListTitle.Font = Enum.Font.GothamBold
	ListTitle.Parent = ListFrame

	local ListCorner2 = Instance.new("UICorner")
	ListCorner2.CornerRadius = UDim.new(0, 10)
	ListCorner2.Parent = ListTitle

	-- Close button (created after the title, so it is drawn on top of it)
	local ListClose = Instance.new("TextButton")
	ListClose.Size = UDim2.new(0, 24, 0, 24)
	ListClose.Position = UDim2.new(1, -28, 0, 3)
	ListClose.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	ListClose.Text = "X"
	ListClose.TextColor3 = Color3.fromRGB(255, 255, 255)
	ListClose.TextSize = 12
	ListClose.Font = Enum.Font.GothamBold
	ListClose.Parent = ListFrame

	local ListCloseCorner = Instance.new("UICorner")
	ListCloseCorner.CornerRadius = UDim.new(0, 8)
	ListCloseCorner.Parent = ListClose

	ListClose.MouseButton1Click:Connect(ClosePlayerList)

	local ListScroll = Instance.new("ScrollingFrame")
	ListScroll.Size = UDim2.new(1, 0, 1, -30)
	ListScroll.Position = UDim2.new(0, 0, 0, 30)
	ListScroll.BackgroundTransparency = 1
	ListScroll.BorderSizePixel = 0
	ListScroll.ScrollBarThickness = 3
	ListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	ListScroll.Parent = ListFrame

	local ListLayout = Instance.new("UIListLayout")
	ListLayout.Padding = UDim.new(0, 5)
	ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayout.Parent = ListScroll

	local ListScrollPadding = Instance.new("UIPadding")
	ListScrollPadding.PaddingTop = UDim.new(0, 5)
	ListScrollPadding.Parent = ListScroll

	local function makeBtn(text, color, onClick)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.9, 0, 0, 30)
		b.BackgroundColor3 = color
		b.Text = text
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.TextSize = 12
		b.Font = Enum.Font.Gotham
		b.Parent = ListScroll
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = b
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			makeBtn(p.Name, Color3.fromRGB(40, 40, 80), function()
				startSpectate(p)
				ClosePlayerList()
			end)
		end
	end

	makeBtn("Stop spectating", Color3.fromRGB(150, 40, 40), function()
		stopSpectate()
		ClosePlayerList()
	end)
end

local Unload -- defined in the "Unload" block below

-- Menu items
CreateToggle("Aimbot (RMB)", "Aimbot")
CreateToggle("ESP", "ESP", clearESP)
CreateToggle("Infinite Jump", "InfiniteJump")
CreateToggle("Fly", "Fly")
CreateToggle("Triggerbot", "Triggerbot")
CreateToggle("FOV Circle", "FOV")
CreateToggle("Hitboxes", "Hitboxes", restoreHitboxes)
CreateToggle("Attach to Target", "Attach", detach)
CreateToggle("Invisible", "Invisible", function()
	setInvisible(false)
end)
CreateButton("Select / Spectate Player", OpenPlayerList, Color3.fromRGB(80, 50, 150))
CreateSlider("FOV Size", "FOVSize", 50, 500, 150)
CreateSlider("Hitbox Size", "HitboxSize", 1, 50, 10)
CreateButton("Unload Script", function()
	Unload()
end, Color3.fromRGB(150, 40, 40))

----------------------------------------------------------------
-- Unload (full cleanup)
----------------------------------------------------------------
Unload = function()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	RunService:UnbindFromRenderStep("BobaabobaCamera")
	detach()
	clearESP()
	restoreHitboxes()
	setInvisible(false)
	stopSpectate()
	ClosePlayerList()
	OverlayGui:Destroy()
	ScreenGui:Destroy()
end

-- M key toggles the menu (ignored while typing in chat / a TextBox)
local MENU_KEY = Enum.KeyCode.M

connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == MENU_KEY then
		setMenuOpen(not MainFrame.Visible)
	end
end)

setMenuOpen(false) -- start collapsed as the "B" logo (use true to start open)

----------------------------------------------------------------
-- Logic
----------------------------------------------------------------

-- Aimbot: runs after the default camera, while RMB is held
RunService:BindToRenderStep("BobaabobaCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if Settings.Aimbot and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		local part = getClosestTarget(Settings.FOVSize)
		if part then
			Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, part.Position)
		end
	end
end)

connect(RunService.RenderStepped, function()
	if Settings.ESP then
		updateESP()
	end

	if Settings.Hitboxes then
		updateHitboxes()
	end

	if Settings.Invisible then
		setInvisible(true)
	end

	-- Triggerbot: activates the Tool you are holding
	if Settings.Triggerbot and getClosestTarget(50) then
		local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
		if tool then
			tool:Activate()
		end
	end

	-- FOV circle
	FOVCircle.Visible = Settings.FOV
	if Settings.FOV then
		local m = UserInputService:GetMouseLocation()
		FOVCircle.Size = UDim2.fromOffset(Settings.FOVSize * 2, Settings.FOVSize * 2)
		FOVCircle.Position = UDim2.fromOffset(m.X, m.Y)
	end
end)

-- Fly and Attach run in Heartbeat because they deal with physics
connect(RunService.Heartbeat, function()
	updateAttach()

	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if Settings.Fly and not UserInputService:GetFocusedTextBox() then
		local v = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then v += Camera.CFrame.LookVector * 50 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then v -= Camera.CFrame.LookVector * 50 end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then v -= Camera.CFrame.RightVector * 50 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then v += Camera.CFrame.RightVector * 50 end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then v += Vector3.new(0, 50, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then v -= Vector3.new(0, 50, 0) end
		hrp.AssemblyLinearVelocity = v
	end
end)

-- Infinite jump
connect(UserInputService.JumpRequest, function()
	if Settings.InfiniteJump then
		local hum = getHumanoid(LP.Character)
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

-- Reset target on respawn
connect(LP.CharacterAdded, function()
	Settings.Target = nil
end)

print("Bobaaboba Script loaded! Click the B logo or press M to open the menu.")
