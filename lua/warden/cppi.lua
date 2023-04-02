CPPI = CPPI or {}

CPPI.CPPI_DEFER = "CPPI_DEFER"
CPPI.CPPI_NOTIMPLEMENTED = "CPPI_NOTIMPLEMENTED"

function CPPI.GetName()
	return "Warden"
end

function CPPI.GetVersion()
	return "1.0"
end

function CPPI.GetInterfaceVersion()
	return 1.3
end

function CPPI.GetNameFromUID()
	return CPPI.CPPI_NOTIMPLEMENTED
end

local plyMeta = FindMetaTable("Player")

function plyMeta:CPPIGetFriends()
	local friends = {}

	for _, ply in ipairs(player.GetAll()) do
		if Warden.CheckPermission(ply, self, Warden.PERMISSION_TOOL) then
			table.insert(friends, ply)
		end
	end

	return friends
end

local entMeta = FindMetaTable("Entity")

function entMeta:CPPIGetOwner()
	local ownerEnt = self:GetNWEntity("OwnerEnt")
	local steamid = self:GetNWString("OwnerID")

	if ownerEnt:IsValid() or ownerEnt == game.GetWorld() then
		return ownerEnt, steamid
	elseif steamid ~= "" then
		return nil, steamid
	end
end

if SERVER then
	function entMeta:CPPISetOwner(ply)
		if ply then
			return Warden.SetOwner(self, ply)
		else
			return Warden.ClearOwner(self)	
		end
	end

	function entMeta:CPPISetOwnerUID()
		return CPPI.CPPI_NOTIMPLEMENTED
	end

	function entMeta:CPPICanTool(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_TOOL)
	end
	entMeta.CPPICanProperty = entMeta.CPPICanTool
	entMeta.CPPICanEditVariable = entMeta.CPPICanTool

	function entMeta:CPPICanPhysgun(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_PHYSGUN)
	end

	function entMeta:CPPICanPickup(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_GRAVGUN)
	end
	function entMeta:CPPICanPunt(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_GRAVGUN)
	end

	function entMeta:CPPICanUse(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_USE)
	end
	entMeta.CPPIDrive = entMeta.CPPICanUse

	function entMeta:CPPICanDamage(ply)
		return Warden.CheckPermission(self, ply, Warden.PERMISSION_DAMAGE)
	end
end

