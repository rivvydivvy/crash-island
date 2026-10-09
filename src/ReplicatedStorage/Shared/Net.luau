--!strict
-- Remote names and lookup. The server creates the remotes on boot; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FOLDER = "Remotes"

-- RemoteFunction: (action: string, payload: any) -> { ok: boolean, message: string?, ... }
-- Actions: "spawn" (vehicleId), "respawn", "flip", "returnToHq", "getState"
Net.VehicleRequest = "VehicleRequest"
-- RemoteEvent server -> client: ({ kind: "info" | "success" | "error", text: string })
Net.Notify = "Notify"

local REMOTES: { [string]: string } = {
	[Net.VehicleRequest] = "RemoteFunction",
	[Net.Notify] = "RemoteEvent",
}

function Net.createAll()
	assert(RunService:IsServer(), "Net.createAll is server-only")
	local folder = ReplicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		folder.Parent = ReplicatedStorage
	end
	for name, className in REMOTES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.get(name: string): Instance
	local folder = ReplicatedStorage:WaitForChild(Net.FOLDER)
	return folder:WaitForChild(name)
end

return Net
