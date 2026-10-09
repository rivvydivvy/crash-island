--!strict
-- Crash Island HUD: left-edge menu, vehicle menu, first-time hint, in-vehicle panel,
-- contextual Flip / Respawn / Exit buttons and notifications. Everything the server decides
-- (ownership, spawning, recovery) arrives through VehicleClient.request / Notify.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.VehicleCatalog)
local Net = require(Shared.Net)
local VehicleClient = require(script.Parent.VehicleClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STUDS_PER_SECOND_TO_MPH = 3600 / 5280 -- the chassis treats 1 stud as 1 foot
local FLIP_ACTION = "CrashIslandFlip"

local COLORS = {
	panel = Color3.fromRGB(22, 27, 36),
	panelLight = Color3.fromRGB(38, 46, 60),
	text = Color3.fromRGB(245, 247, 250),
	muted = Color3.fromRGB(170, 180, 195),
	car = Color3.fromRGB(46, 160, 67),
	plane = Color3.fromRGB(33, 118, 214),
	accent = Color3.fromRGB(255, 176, 32),
	success = Color3.fromRGB(46, 160, 67),
	error = Color3.fromRGB(214, 59, 59),
	info = Color3.fromRGB(33, 118, 214),
	disabled = Color3.fromRGB(80, 86, 96),
}

-- UI helpers ---------------------------------------------------------------------------

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = COLORS.panel
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = COLORS.text
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		if k ~= "MaxTextSize" then
			(l :: any)[k] = v
		end
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = (props :: any).MaxTextSize or 22
	limit.Parent = l
	return l
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = COLORS.panelLight
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = COLORS.text
	b.TextScaled = true
	b.AutoButtonColor = true
	for k, v in props do
		if k ~= "MaxTextSize" then
			(b :: any)[k] = v
		end
	end
	corner(b, 10)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = (props :: any).MaxTextSize or 20
	limit.Parent = b
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.PaddingTop = UDim.new(0, 6)
	p.PaddingBottom = UDim.new(0, 6)
	p.Parent = b
	return b
end

-- Root -----------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "CrashIslandHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function updateScale()
	local size = gui.AbsoluteSize
	uiScale.Scale = if math.min(size.X, size.Y) < 500 then 0.8 else 1
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
updateScale()

-- Notifications (top centre) -------------------------------------------------------------

local toastList = frame({
	Name = "Notifications",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(460, 200),
})
toastList.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastList

local toastCount = 0
local PREFIX = { success = "OK", error = "!", info = "i" }
local function showToast(kind: string, text: string)
	toastCount += 1
	local toast = frame({
		Name = "Toast",
		LayoutOrder = toastCount,
		Size = UDim2.fromOffset(440, 44),
		BackgroundTransparency = 0.1,
	})
	corner(toast, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = COLORS[kind] or COLORS.info
	stroke.Parent = toast
	local badge = label({
		Text = PREFIX[kind] or "i",
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = COLORS[kind] or COLORS.info,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.fromOffset(6, 6),
	})
	corner(badge, 16)
	badge.Parent = toast
	label({ Text = text, Size = UDim2.new(1, -52, 1, -12), Position = UDim2.fromOffset(46, 6), MaxTextSize = 20 }).Parent = toast
	toast.Parent = toastList
	task.delay(Config.Ui.NotificationSeconds, function()
		toast:Destroy()
	end)
	-- Keep at most three on screen.
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > 3 do
		table.remove(toasts, 1):Destroy()
	end
end

local notifyRemote = Net.get(Net.Notify) :: RemoteEvent
notifyRemote.OnClientEvent:Connect(function(message)
	if typeof(message) == "table" and typeof(message.text) == "string" then
		showToast(tostring(message.kind), message.text)
	end
end)
VehicleClient.localNotify:Connect(function(message)
	showToast(message.kind, message.text)
end)

-- Left-edge menu -------------------------------------------------------------------------

local leftMenu = frame({
	Name = "LeftMenu",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0.5, -60),
	Size = UDim2.fromOffset(170, 120),
})
leftMenu.Parent = gui
local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 8)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftMenu

local vehiclesButton = button({ Name = "VehiclesButton", Text = "Vehicles", LayoutOrder = 1, Size = UDim2.fromOffset(170, 52), BackgroundColor3 = COLORS.accent, TextColor3 = Color3.fromRGB(30, 30, 30) })
vehiclesButton.Parent = leftMenu
local hqButton = button({ Name = "HqButton", Text = "Return to HQ", LayoutOrder = 2, Size = UDim2.fromOffset(170, 52) })
hqButton.Parent = leftMenu

-- First-time hint next to the Vehicles button.
local hint = frame({
	Name = "FirstTimeHint",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 192, 0.5, -34),
	Size = UDim2.fromOffset(330, 52),
	BackgroundColor3 = COLORS.accent,
	BackgroundTransparency = 0,
})
corner(hint, 10)
label({ Text = "<  Spawn your free car or plane.", TextColor3 = Color3.fromRGB(30, 30, 30), Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8) }).Parent = hint
hint.Parent = gui
task.spawn(function()
	while hint.Parent do
		TweenService:Create(hint, TweenInfo.new(0.6), { Position = UDim2.new(0, 202, 0.5, -34) }):Play()
		task.wait(0.6)
		TweenService:Create(hint, TweenInfo.new(0.6), { Position = UDim2.new(0, 192, 0.5, -34) }):Play()
		task.wait(0.6)
	end
end)

-- Vehicle menu ---------------------------------------------------------------------------

local menu = frame({
	Name = "VehicleMenu",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(560, 380),
	Visible = false,
	BackgroundTransparency = 0.05,
})
corner(menu, 14)
padding(menu, 14)
menu.Parent = gui

label({ Text = "Vehicles", Size = UDim2.new(1, -60, 0, 34), MaxTextSize = 30 }).Parent = menu
local closeButton = button({ Name = "Close", Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(48, 48) })
closeButton.Parent = menu

local tabs = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 44) })
tabs.Parent = menu
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabs

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(0, 104)
list.Size = UDim2.new(1, 0, 1, -104)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 6
list.Parent = menu
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local DESTINATION = { car = "Car Bay", plane = "Airfield" }
local currentTab: Catalog.Category = "car"
local owned: { [string]: boolean } = {}
local pending = false
local spawnButtons: { TextButton } = {}
local tabButtons: { [string]: TextButton } = {}

local function setPending(value: boolean)
	pending = value
	for _, b in spawnButtons do
		if b:GetAttribute("Owned") then
			b.Active = not value
			b.AutoButtonColor = not value
			b.Text = if value then "Spawning..." else b:GetAttribute("IdleText") :: string
		end
	end
	hqButton.Active = not value
end

local spawnVehicle: (string) -> ()

local function renderList()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(spawnButtons)
	for name, tab in tabButtons do
		local selected = name == currentTab
		tab.BackgroundColor3 = if selected then COLORS[name] else COLORS.panelLight
		tab.Text = (if selected then "> " else "") .. (if name == "car" then "Cars" else "Planes")
	end
	for index, entry in Catalog.byCategory(currentTab) do
		local isOwned = owned[entry.id] == true
		local card = frame({ Name = entry.id, LayoutOrder = index, Size = UDim2.new(1, -10, 0, 96), BackgroundColor3 = COLORS.panelLight, BackgroundTransparency = 0 })
		corner(card, 12)
		padding(card, 10)

		local swatch = frame({ Size = UDim2.fromOffset(76, 76), BackgroundColor3 = entry.color, BackgroundTransparency = 0 })
		corner(swatch, 10)
		if entry.preview ~= "" then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Size = UDim2.fromScale(1, 1)
			image.Image = entry.preview
			image.Parent = swatch
		else
			label({ Text = string.upper(entry.category), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), MaxTextSize = 18 }).Parent = swatch
		end
		swatch.Parent = card

		label({ Text = entry.displayName, Position = UDim2.fromOffset(88, 0), Size = UDim2.new(1, -270, 0, 28), MaxTextSize = 22 }).Parent = card
		label({ Text = entry.description, Font = Enum.Font.Gotham, TextColor3 = COLORS.muted, Position = UDim2.fromOffset(88, 30), Size = UDim2.new(1, -270, 0, 20), MaxTextSize = 16 }).Parent = card
		local status = if isOwned then (if entry.price == 0 then "Owned - Free" else "Owned") else `Locked - {entry.price} Crash Cash`
		label({ Text = status, TextColor3 = if isOwned then COLORS.success else COLORS.muted, Position = UDim2.fromOffset(88, 54), Size = UDim2.new(1, -270, 0, 20), MaxTextSize = 16 }).Parent = card

		local idleText = if isOwned then `Spawn at {DESTINATION[entry.category]}` else "Locked"
		local spawnButton = button({
			Name = "SpawnButton",
			Text = idleText,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(170, 60),
			BackgroundColor3 = if isOwned then COLORS[entry.category] else COLORS.disabled,
			AutoButtonColor = isOwned,
			MaxTextSize = 18,
		})
		spawnButton:SetAttribute("Owned", isOwned)
		spawnButton:SetAttribute("IdleText", idleText)
		spawnButton.Parent = card
		if isOwned then
			table.insert(spawnButtons, spawnButton)
			spawnButton.Activated:Connect(function()
				spawnVehicle(entry.id)
			end)
		end
		card.Parent = list
	end
	setPending(pending)
end

for _, category in { "car", "plane" } do
	local tab = button({ Name = category .. "Tab", Text = category, Size = UDim2.fromOffset(150, 44) })
	tab.Parent = tabs
	tabButtons[category] = tab
	tab.Activated:Connect(function()
		currentTab = category :: Catalog.Category
		renderList()
	end)
end

local function refreshOwned()
	local result = VehicleClient.request("getState")
	if result.ok and typeof(result.owned) == "table" then
		table.clear(owned)
		for _, id in result.owned do
			owned[id] = true
		end
	end
	renderList()
end

local function setMenuOpen(open: boolean)
	menu.Visible = open
	if open then
		task.spawn(refreshOwned)
	end
end

spawnVehicle = function(vehicleId: string)
	if pending then
		return
	end
	setPending(true)
	local result = VehicleClient.request("spawn", vehicleId)
	setPending(false)
	if result.ok then
		showToast("success", result.message or "Spawned!")
		setMenuOpen(false)
		if hint.Parent then
			hint:Destroy()
		end
	else
		showToast("error", result.message or "Couldn't spawn that vehicle.")
	end
end

vehiclesButton.Activated:Connect(function()
	setMenuOpen(not menu.Visible)
end)
closeButton.Activated:Connect(function()
	setMenuOpen(false)
end)
hqButton.Activated:Connect(function()
	if pending then
		return
	end
	setPending(true)
	local result = VehicleClient.request("returnToHq")
	setPending(false)
	showToast(if result.ok then "success" else "error", result.message or "")
end)

-- The dealership kiosk at HQ carries a prompt tagged with this attribute.
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt:GetAttribute("OpensVehicleMenu") then
		setMenuOpen(true)
	end
end)

-- In-vehicle panel (bottom centre) and contextual buttons (right edge) -------------------

local vehiclePanel = frame({
	Name = "VehiclePanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(300, 74),
	Visible = false,
})
corner(vehiclePanel, 12)
padding(vehiclePanel, 8)
vehiclePanel.Parent = gui
local speedLabel = label({ Name = "Speed", Text = "0 mph", Size = UDim2.new(0.5, 0, 0, 30), MaxTextSize = 28 })
speedLabel.Parent = vehiclePanel
local altitudeLabel = label({ Name = "Altitude", Text = "", TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 0, 30), MaxTextSize = 20 })
altitudeLabel.Parent = vehiclePanel
local throttleBack = frame({ Name = "Throttle", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = COLORS.panelLight, BackgroundTransparency = 0 })
corner(throttleBack, 6)
throttleBack.Parent = vehiclePanel
local throttleFill = frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = COLORS.plane, BackgroundTransparency = 0 })
corner(throttleFill, 6)
throttleFill.Parent = throttleBack
local throttleText = label({ Text = "THROTTLE 0%", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), MaxTextSize = 14, ZIndex = 2 })
throttleText.Parent = throttleBack

local statusLabel = label({
	Name = "PlaneStatus",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -100),
	Size = UDim2.fromOffset(520, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.4,
	MaxTextSize = 24,
	Visible = false,
})
statusLabel.Parent = gui

local actions = frame({
	Name = "VehicleActions",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 84),
	Size = UDim2.fromOffset(130, 170),
	Visible = false,
})
actions.Parent = gui
local actionsLayout = Instance.new("UIListLayout")
actionsLayout.Padding = UDim.new(0, 8)
actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionsLayout.Parent = actions
local flipButton = button({ Name = "Flip", Text = "Flip (R)", LayoutOrder = 1, Size = UDim2.fromOffset(130, 48) })
flipButton.Parent = actions
local respawnButton = button({ Name = "Respawn", Text = "Respawn", LayoutOrder = 2, Size = UDim2.fromOffset(130, 48) })
respawnButton.Parent = actions
local exitButton = button({ Name = "Exit", Text = "Exit (E)", LayoutOrder = 3, Size = UDim2.fromOffset(130, 48) })
exitButton.Parent = actions

local function runAction(action: string)
	local result = VehicleClient.request(action)
	if not result.ok and result.message then
		showToast("error", result.message)
	elseif result.ok and result.message then
		showToast("success", result.message)
	end
end
flipButton.Activated:Connect(function()
	runAction("flip")
end)
respawnButton.Activated:Connect(function()
	runAction("respawn")
end)
exitButton.Activated:Connect(function()
	VehicleClient.exitVehicle()
end)

-- Controls hint shown briefly after entering a plane (the car chassis shows its own).
local controlsHint = frame({
	Name = "ControlsHint",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -16),
	Size = UDim2.fromOffset(300, 150),
	Visible = false,
})
corner(controlsHint, 12)
padding(controlsHint, 10)
controlsHint.Parent = gui
local controlsText = label({ Size = UDim2.fromScale(1, 1), TextYAlignment = Enum.TextYAlignment.Top, TextScaled = false, TextSize = 16, TextWrapped = true, RichText = true, Font = Enum.Font.Gotham })
controlsText.Parent = controlsHint

local PLANE_CONTROLS_DESKTOP = "<b>PLANE CONTROLS</b>\nShift / Ctrl - throttle up / down\nW / S - climb / dive\nA / D - turn\nR - flip   E - exit (on the ground)"
local PLANE_CONTROLS_GAMEPAD = "<b>PLANE CONTROLS</b>\nRT / LT - throttle\nLeft stick - climb, dive, turn\nX - exit (on the ground)"

local lastVehicle: Model? = nil
local hintToken = 0

local function onVehicleChanged(vehicle: Model?, category: string?)
	local touch = UserInputService.TouchEnabled
	actions.Visible = vehicle ~= nil
	-- The car chassis has its own speedometer at bottom centre; this panel is for planes.
	vehiclePanel.Visible = category == "plane"
	if vehicle and hint.Parent then
		hint:Destroy()
	end
	-- Keep touch controls clear of the menu: hide it while driving on touch devices.
	leftMenu.Visible = not (vehicle and touch)
	exitButton.Visible = not (category == "car" and touch)
	flipButton.Text = if touch then "Flip" else "Flip (R)"
	exitButton.Text = if touch then "Exit" else "Exit (E)"
	-- On touch screens the car's pedals fill the bottom-right, so the action buttons become a
	-- row along the top, left of the chassis' own camera/exit buttons.
	if touch then
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		actions.Position = UDim2.new(1, if category == "car" then -150 else -12, 0, 8)
		actions.Size = UDim2.fromOffset(340, 48)
	else
		actionsLayout.FillDirection = Enum.FillDirection.Vertical
		actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		actions.Position = UDim2.new(1, -12, 0, 84)
		actions.Size = UDim2.fromOffset(130, 170)
	end
	for _, b in { flipButton, respawnButton, exitButton } do
		b.Size = if touch then UDim2.fromOffset(104, 48) else UDim2.fromOffset(130, 48)
	end
	throttleBack.Visible = category == "plane"
	altitudeLabel.Visible = category == "plane"
	statusLabel.Visible = category == "plane"
	if vehicle then
		menu.Visible = false
	end

	hintToken += 1
	controlsHint.Visible = false
	if vehicle and category == "plane" and not touch then
		controlsText.Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
			then PLANE_CONTROLS_GAMEPAD
			else PLANE_CONTROLS_DESKTOP
		controlsHint.Visible = true
		local token = hintToken
		task.delay(Config.Ui.ControlsHintSeconds, function()
			if token == hintToken then
				controlsHint.Visible = false
			end
		end)
	end
end

ContextActionService:BindAction(FLIP_ACTION, function(_, state)
	if state == Enum.UserInputState.Begin and lastVehicle then
		task.spawn(runAction, "flip")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.R)

RunService.RenderStepped:Connect(function()
	local vehicle, category = VehicleClient.getCurrentVehicle()
	if vehicle ~= lastVehicle then
		lastVehicle = vehicle
		onVehicleChanged(vehicle, category)
	end
	if not vehicle then
		return
	end
	local telemetry = VehicleClient.planeTelemetry
	if category == "plane" and telemetry then
		speedLabel.Text = `{math.floor(telemetry.speed * STUDS_PER_SECOND_TO_MPH + 0.5)} mph`
		altitudeLabel.Text = `ALT {math.floor(telemetry.altitude)}`
		throttleFill.Size = UDim2.fromScale(telemetry.throttle, 1)
		throttleText.Text = `THROTTLE {math.floor(telemetry.throttle * 100 + 0.5)}%`
		statusLabel.Text = telemetry.status
	else
		local root = vehicle.PrimaryPart
		local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
		speedLabel.Text = `{math.floor(speed * STUDS_PER_SECOND_TO_MPH + 0.5)} mph`
	end
end)

renderList()
task.spawn(refreshOwned)
