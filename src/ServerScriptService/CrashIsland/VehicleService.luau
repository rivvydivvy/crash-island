--!strict
-- Server-owned vehicle lifecycle shared by every car and plane:
-- spawn (ownership check, cooldown, pad obstruction check, replace-only-on-success),
-- owner-only seating, flip, respawn, return to HQ, out-of-bounds recovery and cleanup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Catalog = require(Shared.VehicleCatalog)
local Net = require(Shared.Net)
local Collision = require(script.Parent.Collision)
local Ownership = require(script.Parent.Ownership)

-- Attribute the Racing-template chassis reads to know its owner (see its Scripts.Constants).
local CHASSIS_OWNER_ATTRIBUTE = "owner"
local SEAT_NAME = "DriverSeat"
local RECOLOR_TAG = "Recolor"

type PlayerState = {
	vehicle: Model?,
	vehicleId: string?,
	busy: boolean,
	lastSpawn: number,
	lastFlip: number,
	outOfBoundsSince: number?,
	requestTimes: { number },
}

type Result = { ok: boolean, message: string?, [string]: any }

local VehicleService = {}

local states: { [Player]: PlayerState } = {}
local activeFolder: Folder
local templates: Folder
local notifyRemote: RemoteEvent
local boundsCache: { [Model]: { size: Vector3, offset: CFrame } } = {}

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = {
			vehicle = nil,
			vehicleId = nil,
			busy = false,
			lastSpawn = -math.huge,
			lastFlip = -math.huge,
			outOfBoundsSince = nil,
			requestTimes = {},
		}
		states[player] = state
	end
	return state
end

local function notify(player: Player, kind: string, text: string)
	notifyRemote:FireClient(player, { kind = kind, text = text })
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function getSeat(vehicle: Model): Seat?
	local seat = vehicle:FindFirstChild(SEAT_NAME)
	if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return seat :: any
	end
	return nil
end

local function setNetworkOwner(vehicle: Model, player: Player?)
	local root = vehicle.PrimaryPart
	if root and root:IsDescendantOf(Workspace) and root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(player)
	end
end

-- Bounding box of a template relative to its pivot, cached per template.
local function getBounds(template: Model): (Vector3, CFrame)
	local cached = boundsCache[template]
	if not cached then
		local boxCFrame, size = template:GetBoundingBox()
		cached = { size = size, offset = template:GetPivot():ToObjectSpace(boxCFrame) }
		boundsCache[template] = cached
	end
	return cached.size, cached.offset
end

-- Pivot CFrame that rests the vehicle's bounding box on top of the pad.
local function placementOnPad(pad: BasePart, size: Vector3, offset: CFrame): CFrame
	local top = pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
	local bottomBelowPivot = offset.Position.Y - size.Y / 2
	return top * CFrame.new(0, -bottomBelowPivot + Config.Vehicles.SpawnLift, 0)
end

local function isAreaClear(pivot: CFrame, size: Vector3, offset: CFrame, ignore: { Instance }): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { Workspace.Terrain }
	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(filter, map)
	end
	for _, inst in ignore do
		table.insert(filter, inst)
	end
	params.FilterDescendantsInstances = filter
	local hits = Workspace:GetPartBoundsInBox(pivot * offset, size + Config.Vehicles.PadClearance, params)
	return #hits == 0
end

local function padsFor(spawnCategory: string, near: Vector3?): { BasePart }
	local pads = {}
	for _, inst in CollectionService:GetTagged(Config.Tags.VehiclePad) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) and inst:GetAttribute("SpawnCategory") == spawnCategory then
			table.insert(pads, inst)
		end
	end
	if near then
		table.sort(pads, function(a, b)
			return (a.Position - near).Magnitude < (b.Position - near).Magnitude
		end)
	end
	return pads
end

-- First pad of the category whose spawn area is clear, ignoring the given instances.
local function findClearPad(spawnCategory: string, template: Model, near: Vector3?, ignore: { Instance }): CFrame?
	local size, offset = getBounds(template)
	for _, pad in padsFor(spawnCategory, near) do
		local pivot = placementOnPad(pad, size, offset)
		if isAreaClear(pivot, size, offset, ignore) then
			return pivot
		end
	end
	return nil
end

local function unseat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

local function seatPlayer(player: Player, vehicle: Model)
	local humanoid = getHumanoid(player)
	local seat = getSeat(vehicle)
	local character = player.Character
	if not humanoid or not seat or not character or seat.Occupant or not vehicle:IsDescendantOf(Workspace) then
		return
	end
	unseat(humanoid)
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(humanoid)
end

local function applyCatalog(vehicle: Model, entry: Catalog.Entry, player: Player)
	vehicle.Name = `{player.Name}_{entry.id}`
	vehicle:SetAttribute("VehicleId", entry.id)
	vehicle:SetAttribute("VehicleCategory", entry.category)
	vehicle:SetAttribute("OwnerUserId", player.UserId)
	vehicle:SetAttribute(CHASSIS_OWNER_ATTRIBUTE, player.UserId)

	if entry.category == "car" then
		for folderName, overrides in entry.handling do
			local folder = vehicle:FindFirstChild(folderName)
			if folder then
				for key, value in overrides :: { [string]: any } do
					folder:SetAttribute(key, value)
				end
			end
		end
	else
		for key, value in entry.handling do
			vehicle:SetAttribute("Handling_" .. key, value)
		end
	end
	for key, value in entry.damage do
		vehicle:SetAttribute("Damage_" .. key, value)
	end

	for _, d in vehicle:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag(RECOLOR_TAG) then
			d.Color = entry.color
		end
	end
	Collision.setGroup(vehicle, Config.CollisionGroups.Vehicle)
end

local function watchVehicle(player: Player, vehicle: Model, state: PlayerState)
	local seat = getSeat(vehicle)
	if seat then
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			if not occupant then
				return
			end
			-- Initial version: only the owner may drive or pilot their vehicle.
			if Players:GetPlayerFromCharacter(occupant.Parent) ~= player then
				unseat(occupant)
				return
			end
			setNetworkOwner(vehicle, player)
		end)
	end

	-- Planes carry their own DrivePrompt; the car chassis handles its prompt itself.
	if vehicle:GetAttribute("VehicleCategory") == "plane" then
		local prompt = vehicle:FindFirstChild("DrivePrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ObjectText = `{player.DisplayName}'s plane`
			prompt.Triggered:Connect(function(who)
				if who == player then
					seatPlayer(player, vehicle)
				end
			end)
			if seat then
				seat:GetPropertyChangedSignal("Occupant"):Connect(function()
					prompt.Enabled = seat.Occupant == nil
				end)
			end
		end
	end

	vehicle.AncestryChanged:Connect(function()
		if not vehicle:IsDescendantOf(Workspace) and state.vehicle == vehicle then
			state.vehicle = nil
			state.vehicleId = nil
			state.outOfBoundsSince = nil
		end
	end)
end

local function blockedMessage(entry: Catalog.Entry): string
	if entry.spawnCategory == "plane" then
		return "All aircraft pads are blocked. Try again in a moment."
	end
	return "All car bays are blocked. Try again in a moment."
end

function VehicleService.spawn(player: Player, vehicleId: any): Result
	if typeof(vehicleId) ~= "string" then
		return { ok = false, message = "Unknown vehicle." }
	end
	local entry = Catalog.get(vehicleId)
	if not entry then
		return { ok = false, message = "That vehicle isn't available." }
	end
	if not Ownership.owns(player, vehicleId) then
		return { ok = false, message = `You don't own the {entry.displayName} yet.` }
	end
	local template = templates:FindFirstChild(entry.model)
	if not template or not template:IsA("Model") then
		warn(`[VehicleService] missing template ServerStorage.Vehicles.{entry.model}`)
		return { ok = false, message = `The {entry.displayName} is unavailable right now.` }
	end

	local state = getState(player)
	if state.busy then
		return { ok = false, message = "Already spawning a vehicle..." }
	end
	local now = os.clock()
	local remaining = Config.Vehicles.SpawnCooldown - (now - state.lastSpawn)
	if remaining > 0 then
		return { ok = false, message = `Wait {math.ceil(remaining)}s before spawning again.` }
	end
	local humanoid = getHumanoid(player)
	local character = player.Character
	if not humanoid or not character then
		return { ok = false, message = "Wait for your character to load." }
	end

	-- Everything from here to parenting is yield-free, so two requests can't both claim a pad.
	state.busy = true
	local ignore: { Instance } = { character }
	if state.vehicle then
		-- The old vehicle is about to be replaced, so it doesn't count as an obstruction.
		table.insert(ignore, state.vehicle)
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pivot = findClearPad(entry.spawnCategory, template, root and root.Position, ignore)
	if not pivot then
		state.busy = false
		return { ok = false, message = blockedMessage(entry) }
	end

	local vehicle = template:Clone()
	applyCatalog(vehicle, entry, player)
	vehicle:PivotTo(pivot)

	-- Replacement can succeed, so only now remove the previous vehicle.
	unseat(humanoid)
	if state.vehicle then
		state.vehicle:Destroy()
	end
	vehicle.Parent = activeFolder
	state.vehicle = vehicle
	state.vehicleId = vehicleId
	state.lastSpawn = now
	state.outOfBoundsSince = nil
	watchVehicle(player, vehicle, state)
	setNetworkOwner(vehicle, player)
	state.busy = false

	task.defer(seatPlayer, player, vehicle)
	return { ok = true, message = `Spawned your {entry.displayName}!` }
end

-- Moves a vehicle to a CFrame with the server briefly owning its physics, then hands it back.
local function teleportVehicle(player: Player, vehicle: Model, pivot: CFrame)
	setNetworkOwner(vehicle, nil)
	vehicle:PivotTo(pivot)
	for _, d in vehicle:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	task.delay(0.3, function()
		if vehicle:IsDescendantOf(Workspace) then
			setNetworkOwner(vehicle, player)
		end
	end)
end

function VehicleService.flip(player: Player): Result
	local state = getState(player)
	local vehicle = state.vehicle
	if not vehicle or not vehicle.PrimaryPart then
		return { ok = false, message = "You don't have a vehicle out." }
	end
	local now = os.clock()
	if now - state.lastFlip < Config.Vehicles.FlipCooldown then
		return { ok = false, message = "Hang on, still flipping!" }
	end
	state.lastFlip = now
	local current = vehicle:GetPivot()
	local look = current.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(current.UpVector.X, 0, current.UpVector.Z)
	end
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local position = current.Position + Vector3.new(0, 5, 0)
	teleportVehicle(player, vehicle, CFrame.lookAt(position, position + flat.Unit))
	return { ok = true }
end

function VehicleService.respawn(player: Player): Result
	local state = getState(player)
	if not state.vehicleId then
		return { ok = false, message = "Spawn a vehicle first." }
	end
	return VehicleService.spawn(player, state.vehicleId)
end

function VehicleService.returnToHq(player: Player): Result
	local humanoid = getHumanoid(player)
	local character = player.Character
	if not humanoid or not character then
		return { ok = false, message = "Wait for your character to load." }
	end
	local spawns = CollectionService:GetTagged(Config.Tags.HqSpawn)
	local spawnPart = spawns[1]
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return { ok = false, message = "HQ is missing!" }
	end
	unseat(humanoid)
	local jitter = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	task.defer(function()
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0) + jitter)
	end)
	return { ok = true, message = "Welcome back to HQ!" }
end

local function getClientState(player: Player): Result
	local state = getState(player)
	return { ok = true, owned = Ownership.ownedIds(player), activeVehicleId = state.vehicleId }
end

local function allowRequest(state: PlayerState): boolean
	local now = os.clock()
	local times = state.requestTimes
	while #times > 0 and now - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= Config.Net.RequestsPerSecond then
		return false
	end
	table.insert(times, now)
	return true
end

local handlers: { [string]: (Player, any) -> Result } = {
	spawn = VehicleService.spawn,
	respawn = function(player)
		return VehicleService.respawn(player)
	end,
	flip = function(player)
		return VehicleService.flip(player)
	end,
	returnToHq = function(player)
		return VehicleService.returnToHq(player)
	end,
	getState = function(player)
		return getClientState(player)
	end,
}

local function onRequest(player: Player, action: any, payload: any): Result
	if typeof(action) ~= "string" or not handlers[action] then
		return { ok = false, message = "Unknown request." }
	end
	if not allowRequest(getState(player)) then
		return { ok = false, message = "Slow down a little!" }
	end
	local ok, result = pcall(handlers[action], player, payload)
	if not ok then
		warn(`[VehicleService] {action} failed for {player.Name}: {result}`)
		return { ok = false, message = "Something went wrong. Try again." }
	end
	return result
end

local function isOutOfBounds(vehicle: Model, position: Vector3): boolean
	local world = Config.World
	if position.Y < world.RecoveryHeight then
		return true
	end
	if vehicle:GetAttribute("VehicleCategory") == "plane" then
		local offset = position - world.Center
		local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
		return horizontal > world.PlaneHardRadius or position.Y > world.PlaneHardCeiling
	end
	return false
end

local function recover(player: Player, state: PlayerState, vehicle: Model): boolean
	local entry = Catalog.get(vehicle:GetAttribute("VehicleId") :: string)
	local template = entry and templates:FindFirstChild(entry.model)
	if not entry or not template or not template:IsA("Model") then
		return false
	end
	local ignore: { Instance } = { vehicle }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local pivot = findClearPad(entry.spawnCategory, template, nil, ignore)
	if not pivot then
		return false
	end
	teleportVehicle(player, vehicle, pivot)
	notify(player, "info", `Your {entry.displayName} was recovered.`)
	return true
end

local function recoveryLoop()
	while true do
		task.wait(Config.Vehicles.RecoveryCheckInterval)
		local now = os.clock()
		for player, state in states do
			local vehicle = state.vehicle
			local root = vehicle and vehicle.PrimaryPart
			if vehicle and root then
				if isOutOfBounds(vehicle, root.Position) then
					state.outOfBoundsSince = state.outOfBoundsSince or now
					if now - (state.outOfBoundsSince :: number) >= Config.World.OutOfBoundsGrace then
						if recover(player, state, vehicle) then
							state.outOfBoundsSince = nil
						end
					end
				else
					state.outOfBoundsSince = nil
				end
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state and state.vehicle then
		state.vehicle:Destroy()
	end
	states[player] = nil
end

function VehicleService.init()
	activeFolder = Workspace:FindFirstChild("ActiveVehicles") :: Folder
	if not activeFolder then
		activeFolder = Instance.new("Folder")
		activeFolder.Name = "ActiveVehicles"
		activeFolder.Parent = Workspace
	end
	templates = ServerStorage:WaitForChild("Vehicles") :: Folder
	notifyRemote = Net.get(Net.Notify) :: RemoteEvent
	local requestRemote = Net.get(Net.VehicleRequest) :: RemoteFunction
	requestRemote.OnServerInvoke = onRequest

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(recoveryLoop)
end

return VehicleService
