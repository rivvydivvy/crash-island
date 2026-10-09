--!strict
-- Client-side helpers shared by the HUD and vehicle controllers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer

export type PlaneTelemetry = {
	speed: number,
	throttle: number,
	altitude: number,
	airborne: boolean,
	status: string,
}

local VehicleClient = {}

-- Written every frame by PlaneController while the local player is piloting.
VehicleClient.planeTelemetry = nil :: PlaneTelemetry?

local localNotify = Instance.new("BindableEvent")
-- Fires ({ kind, text }) for client-side messages, alongside server Notify events.
VehicleClient.localNotify = localNotify.Event

function VehicleClient.notify(kind: string, text: string)
	localNotify:Fire({ kind = kind, text = text })
end

function VehicleClient.getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- The local player's own vehicle they are currently seated in, and its category.
function VehicleClient.getCurrentVehicle(): (Model?, string?)
	local humanoid = VehicleClient.getHumanoid()
	local seat = humanoid and humanoid.SeatPart
	local vehicle = seat and seat.Parent
	if vehicle and vehicle:IsA("Model") and vehicle:GetAttribute("OwnerUserId") == player.UserId then
		return vehicle, vehicle:GetAttribute("VehicleCategory") :: string?
	end
	return nil, nil
end

function VehicleClient.request(action: string, payload: any?): { ok: boolean, message: string?, [string]: any }
	local remote = Net.get(Net.VehicleRequest) :: RemoteFunction
	local ok, result = pcall(remote.InvokeServer, remote, action, payload)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, message = "Couldn't reach the server. Try again." }
	end
	return result
end

-- Leaves the current vehicle and steps out beside it (same approach as the chassis' own exit).
function VehicleClient.exitVehicle(): boolean
	local vehicle, category = VehicleClient.getCurrentVehicle()
	local humanoid = VehicleClient.getHumanoid()
	local character = player.Character
	if not vehicle or not humanoid or not character then
		return false
	end
	local telemetry = VehicleClient.planeTelemetry
	if category == "plane" and telemetry and telemetry.airborne then
		VehicleClient.notify("error", "Land first - or use Respawn / Return to HQ.")
		return false
	end
	local exitAttachment = vehicle:FindFirstChild("ExitLocationAttachment", true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	task.spawn(function()
		local seatWeld = humanoid.SeatPart and humanoid.SeatPart:FindFirstChild("SeatWeld")
		if seatWeld then
			humanoid.Sit = false
			local deadline = os.clock() + 1
			while seatWeld:IsDescendantOf(game) and os.clock() < deadline do
				task.wait()
			end
		end
		task.defer(function()
			if exitAttachment and exitAttachment:IsA("Attachment") and exitAttachment:IsDescendantOf(workspace) then
				character:PivotTo(exitAttachment.WorldCFrame)
			end
		end)
	end)
	return true
end

return VehicleClient
