--!strict
-- Forgiving arcade flight controller. Runs on the pilot's client, which owns the plane's
-- physics, and drives two movers on the plane's Body:
--   FlightVelocity (LinearVelocity): forward speed. On the ground the Y axis gets no force so
--     gravity and the landing gear handle height; in the air it controls all three axes.
--   FlightGyro (AlignOrientation): heading/pitch/bank target with gentle auto-levelling.
-- No stalls, fuel or cockpit procedures: below takeoff speed the plane just sinks gently.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleClient = require(script.Parent.VehicleClient)

local player = Players.LocalPlayer

local EXIT_ACTION = "CrashIslandPlaneExit"
local CAMERA_BIND = "CrashIslandPlaneCamera"
local FORCE_PER_MASS = 600
local DEADZONE = 0.15

local DEFAULT_HANDLING = {
	maxSpeed = 150,
	takeoffSpeed = 60,
	acceleration = 28,
	deceleration = 14,
	groundBrake = 45,
	throttleRate = 0.55,
	turnRate = 55,
	groundTurnRate = 50,
	pitchRate = 45,
	maxPitch = 45,
	bankAngle = 35,
	autoLevelRate = 18,
	sinkRate = 28,
}

type Session = {
	plane: Model,
	body: BasePart,
	velocity: LinearVelocity,
	gyro: AlignOrientation,
	h: { [string]: number },
	throttle: number,
	speed: number,
	yaw: number,
	pitch: number,
	roll: number,
	grounded: boolean,
	airTime: number,
	noGroundTime: number,
	gearProbe: number,
	rayParams: RaycastParams,
	cameraPosition: Vector3,
	connections: { RBXScriptConnection },
	touchGui: ScreenGui?,
}

local session: Session? = nil

-- Touch input written by the on-screen controls.
local touchStick = Vector2.zero
local touchThrottle = 0

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function readHandling(plane: Model): { [string]: number }
	local h = {}
	for key, default in DEFAULT_HANDLING do
		local value = plane:GetAttribute("Handling_" .. key)
		h[key] = if typeof(value) == "number" then value else default
	end
	return h
end

local function axis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	local value = 0
	for _, key in positive do
		if UserInputService:IsKeyDown(key) then
			value += 1
			break
		end
	end
	for _, key in negative do
		if UserInputService:IsKeyDown(key) then
			value -= 1
			break
		end
	end
	return value
end

-- Returns throttle, pitch (+ = climb), turn (+ = right), each in [-1, 1].
local function gatherInput(): (number, number, number)
	local throttle, pitch, turn = 0, 0, 0
	if not UserInputService:GetFocusedTextBox() then
		throttle += axis({ Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift }, { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl })
		pitch += axis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down })
		turn += axis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })
	end
	if UserInputService.GamepadEnabled then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local p = input.Position
				if math.abs(p.X) > DEADZONE then
					turn += p.X
				end
				if math.abs(p.Y) > DEADZONE then
					pitch += p.Y
				end
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				throttle += input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				throttle -= input.Position.Z
			end
		end
	end
	pitch += touchStick.Y
	turn += touchStick.X
	throttle += touchThrottle
	return math.clamp(throttle, -1, 1), math.clamp(pitch, -1, 1), math.clamp(turn, -1, 1)
end

local function statusText(s: Session): string
	local h = s.h
	local body = s.body
	local center = Config.World.Center
	local offset = body.Position - center
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.World.PlaneSoftRadius then
		return "Too far out - turning back to the island"
	end
	if body.Position.Y > Config.World.PlaneCeiling then
		return "Maximum altitude"
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if s.grounded then
		if s.throttle < 0.05 and s.speed < 1 then
			return if touch then "Hold + THROTTLE to speed up" else "Hold SHIFT to throttle up"
		elseif s.speed < h.takeoffSpeed then
			return "Building speed for takeoff..."
		end
		return if touch then "Takeoff speed! Push the stick up to climb" else "Takeoff speed! Press W to climb"
	end
	if s.speed < h.takeoffSpeed then
		return "Too slow to climb - throttle up"
	end
	return ""
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	local h = s.h
	local body = s.body
	local throttleIn, pitchIn, turnIn = gatherInput()

	-- Throttle and speed
	s.throttle = math.clamp(s.throttle + throttleIn * h.throttleRate * dt, 0, 1)
	local targetSpeed = s.throttle * h.maxSpeed
	local rate = h.acceleration
	if targetSpeed < s.speed then
		rate = if s.grounded and s.throttle < 0.05 then h.groundBrake else h.deceleration
	end
	s.speed = moveToward(s.speed, targetSpeed, rate * dt)
	-- If something physically stopped us (a wall, another plane), don't keep pushing at full speed.
	local actualForward = body.AssemblyLinearVelocity:Dot(body.CFrame.LookVector)
	if actualForward < s.speed - 30 then
		s.speed = math.max(actualForward + 30, 0)
	end

	-- Ground contact
	local hit = Workspace:Raycast(body.Position, Vector3.new(0, -s.gearProbe, 0), s.rayParams)

	-- Heading
	local turnRate = math.rad(if s.grounded then h.groundTurnRate else h.turnRate)
	s.yaw = wrapAngle(s.yaw - turnIn * turnRate * dt)

	if s.grounded then
		s.pitch = 0
		s.roll = 0
		s.noGroundTime = if hit then 0 else s.noGroundTime + dt
		if pitchIn > 0.3 and s.speed >= h.takeoffSpeed then
			s.grounded = false
			s.airTime = 0
			s.pitch = math.rad(8)
		elseif s.noGroundTime > 0.3 then
			-- Rolled off an edge (or was moved into the air): switch to flight so it glides.
			s.grounded = false
			s.airTime = 0.6
		end
	else
		s.airTime += dt
		local maxPitch = math.rad(h.maxPitch)
		if math.abs(pitchIn) > 0 then
			s.pitch += pitchIn * math.rad(h.pitchRate) * dt
		else
			s.pitch = moveToward(s.pitch, 0, math.rad(h.autoLevelRate) * dt)
		end
		local maxUp = if s.speed >= h.takeoffSpeed then maxPitch else 0
		if body.Position.Y > Config.World.PlaneCeiling then
			maxUp = math.min(maxUp, -math.rad(5))
		end
		s.pitch = math.clamp(s.pitch, -maxPitch, maxUp)
		s.roll = moveToward(s.roll, -turnIn * math.rad(h.bankAngle), math.rad(90) * dt)

		-- Soft boundary: steer back toward the island.
		local offset = body.Position - Config.World.Center
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		if flatOffset.Magnitude > Config.World.PlaneSoftRadius then
			local toCenter = -flatOffset.Unit
			local desiredYaw = math.atan2(-toCenter.X, -toCenter.Z)
			local diff = wrapAngle(desiredYaw - s.yaw)
			s.yaw = wrapAngle(s.yaw + math.clamp(diff, -turnRate * dt, turnRate * dt))
			s.roll = moveToward(s.roll, math.sign(diff) * math.rad(h.bankAngle), math.rad(90) * dt)
		end

		-- Touchdown: close to the ground, not climbing, nose roughly level.
		if hit and s.airTime > 0.6 and body.AssemblyLinearVelocity.Y <= 4 and s.pitch <= math.rad(8) then
			s.grounded = true
		end
	end

	local heading = CFrame.Angles(0, s.yaw, 0)
	local attitude = heading * CFrame.Angles(s.pitch, 0, 0)
	local force = body.AssemblyMass * FORCE_PER_MASS
	if s.grounded then
		s.velocity.MaxAxesForce = Vector3.new(force, 0, force)
		s.velocity.VectorVelocity = heading.LookVector * s.speed
	else
		local sink = if s.speed < h.takeoffSpeed then h.sinkRate * (1 - s.speed / h.takeoffSpeed) else 0
		s.velocity.MaxAxesForce = Vector3.new(force, force, force)
		s.velocity.VectorVelocity = attitude.LookVector * s.speed - Vector3.new(0, sink, 0)
	end
	s.gyro.CFrame = attitude * CFrame.Angles(0, 0, s.roll)

	VehicleClient.planeTelemetry = {
		speed = s.speed,
		throttle = s.throttle,
		altitude = math.max(0, body.Position.Y),
		airborne = not s.grounded,
		status = statusText(s),
	}
end

local function updateCamera(dt: number)
	local s = session
	if not s then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local body = s.body
	local look = body.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	-- Follow mostly the heading, partly the pitch, so climbs and dives read clearly.
	local follow = (flat * 0.75 + look * 0.25).Unit
	local desired = body.Position - follow * 38 + Vector3.new(0, 12, 0)
	s.cameraPosition = s.cameraPosition:Lerp(desired, 1 - math.exp(-dt * 6))
	camera.CFrame = CFrame.lookAt(s.cameraPosition, body.Position + look * 30 + Vector3.new(0, 4, 0))
end

local function makeButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, anchor: Vector2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Size = size
	button.Position = position
	button.AnchorPoint = anchor
	button.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	button.BackgroundTransparency = 0.25
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.Parent = button
	button.Parent = parent
	return button
end

-- Virtual stick (bottom-left) for pitch/turn, throttle buttons (bottom-right).
local function createTouchGui(s: Session): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaneTouchControls"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local base = Instance.new("Frame")
	base.Name = "Stick"
	base.Size = UDim2.fromOffset(170, 170)
	base.Position = UDim2.new(0, 30, 1, -30)
	base.AnchorPoint = Vector2.new(0, 1)
	base.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	base.BackgroundTransparency = 0.45
	local baseCorner = Instance.new("UICorner")
	baseCorner.CornerRadius = UDim.new(1, 0)
	baseCorner.Parent = base
	base.Parent = gui

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(70, 70)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.2
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	knob.Parent = base

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Position = UDim2.new(0, 0, 0, -26)
	label.Text = "CLIMB / TURN"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = base

	local stickInput: InputObject? = nil
	local function updateStick(position: Vector3)
		local center = base.AbsolutePosition + base.AbsoluteSize / 2
		local radius = base.AbsoluteSize.X / 2
		local delta = Vector2.new(position.X, position.Y) - center
		if delta.Magnitude > radius then
			delta = delta.Unit * radius
		end
		knob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
		local v = delta / radius
		touchStick = Vector2.new(v.X, -v.Y)
	end
	table.insert(s.connections, base.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not stickInput then
			stickInput = input
			updateStick(input.Position)
		end
	end))
	table.insert(s.connections, UserInputService.TouchMoved:Connect(function(input)
		if input == stickInput then
			updateStick(input.Position)
		end
	end))
	table.insert(s.connections, UserInputService.TouchEnded:Connect(function(input)
		if input == stickInput then
			stickInput = nil
			touchStick = Vector2.zero
			knob.Position = UDim2.fromScale(0.5, 0.5)
		end
	end))

	local up = makeButton(gui, "ThrottleUp", "+ THROTTLE", UDim2.fromOffset(110, 80), UDim2.new(1, -140, 1, -30), Vector2.new(1, 1))
	local down = makeButton(gui, "ThrottleDown", "- THROTTLE", UDim2.fromOffset(110, 80), UDim2.new(1, -20, 1, -30), Vector2.new(1, 1))
	local heldUp, heldDown = false, false
	local function refresh()
		touchThrottle = (if heldUp then 1 else 0) - (if heldDown then 1 else 0)
	end
	table.insert(s.connections, up.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			heldUp = true
			refresh()
		end
	end))
	table.insert(s.connections, up.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			heldUp = false
			refresh()
		end
	end))
	table.insert(s.connections, down.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			heldDown = true
			refresh()
		end
	end))
	table.insert(s.connections, down.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			heldDown = false
			refresh()
		end
	end))

	local function updateScale()
		local size = gui.AbsoluteSize
		scale.Scale = if math.min(size.X, size.Y) < 500 then 0.75 else 1
	end
	table.insert(s.connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))
	updateScale()
	return gui
end

local function stop()
	local s = session
	if not s then
		return
	end
	session = nil
	VehicleClient.planeTelemetry = nil
	touchStick = Vector2.zero
	touchThrottle = 0
	for _, c in s.connections do
		c:Disconnect()
	end
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	ContextActionService:UnbindAction(EXIT_ACTION)
	if s.touchGui then
		s.touchGui:Destroy()
	end
	if s.velocity.Parent then
		s.velocity.Enabled = false
	end
	if s.gyro.Parent then
		s.gyro.Enabled = false
	end
	GuiService.TouchControlsEnabled = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = VehicleClient.getHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function start(plane: Model)
	stop()
	local body = plane.PrimaryPart
	if not body then
		return
	end
	local velocity = body:FindFirstChild("FlightVelocity") :: LinearVelocity?
	local gyro = body:FindFirstChild("FlightGyro") :: AlignOrientation?
	if not velocity or not gyro then
		warn("[PlaneController] plane is missing FlightVelocity/FlightGyro")
		return
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { plane, player.Character :: Instance }

	local look = body.CFrame.LookVector
	local s: Session = {
		plane = plane,
		body = body,
		velocity = velocity,
		gyro = gyro,
		h = readHandling(plane),
		throttle = 0,
		speed = math.max(0, body.AssemblyLinearVelocity:Dot(look)),
		yaw = math.atan2(-look.X, -look.Z),
		pitch = 0,
		roll = 0,
		grounded = true,
		airTime = 0,
		noGroundTime = 0,
		gearProbe = (plane:GetAttribute("GearHeight") :: number? or 4.5) + 2,
		rayParams = rayParams,
		cameraPosition = Workspace.CurrentCamera.CFrame.Position,
		connections = {},
		touchGui = nil,
	}
	-- Entering mid-air (e.g. recovered) starts in flight with some speed.
	if not Workspace:Raycast(body.Position, Vector3.new(0, -s.gearProbe, 0), rayParams) then
		s.grounded = false
		s.airTime = 1
		s.throttle = 0.6
		s.speed = math.max(s.speed, s.h.takeoffSpeed)
	end
	session = s

	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.Enabled = true
	gyro.Enabled = true

	GuiService.TouchControlsEnabled = false
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, updateCamera)
	table.insert(s.connections, RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end))
	ContextActionService:BindAction(EXIT_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			VehicleClient.exitVehicle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	table.insert(s.connections, plane.AncestryChanged:Connect(function()
		if not plane:IsDescendantOf(Workspace) then
			stop()
		end
	end))
	if UserInputService.TouchEnabled then
		s.touchGui = createTouchGui(s)
	end
end

local function onSeatChanged(humanoid: Humanoid)
	local vehicle, category = VehicleClient.getCurrentVehicle()
	if vehicle and category == "plane" then
		if not session or session.plane ~= vehicle then
			start(vehicle)
		end
	else
		stop()
	end
end

local function onCharacter(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeatChanged(humanoid)
	end)
	humanoid.Died:Connect(stop)
	onSeatChanged(humanoid)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
