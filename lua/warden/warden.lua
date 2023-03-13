function Warden.SetupPlayer(ply)
	Warden.Permissions[ply:SteamID()] = {}
	for _, id in pairs(Warden.PermissionIDs) do
		Warden.Permissions[ply:SteamID()][id] = { global = false }
	end
end

function Warden.SetupSteamID(steamid)
	Warden.Permissions[steamid] = {}
	for _, id in pairs(Warden.PermissionIDs) do
		Warden.Permissions[steamid][id] = { global = false }
	end
end

Warden.SteamIDMap = Warden.SteamIDMap or {}

function Warden.GetPlayerFromSteamID(steamid)
	if not Warden.SteamIDMap[steamid] then
		for _, ply in pairs(player.GetAll()) do
			Warden.SteamIDMap[ply:SteamID()] = ply
		end
	end
	return Warden.SteamIDMap[steamid]
end

function Warden.CheckPermission(ent, checkEnt, permission)
	if not checkEnt or not (checkEnt:IsValid() or checkEnt:IsWorld()) then return false end
	if not ent then return false end
	local receiver
	if ent:IsPlayer() then
		receiver = ent
	else
		local owner = Warden.GetOwner(ent)
		if owner and owner:IsPlayer() then
			receiver = owner
		else
			return false
		end
	end
	if checkEnt:IsPlayer() then return Warden.HasPermission(receiver, checkEnt, permission) end

	local owner = Warden.GetOwner(checkEnt)
	if not IsValid(owner) then return false end

	if not Warden.Permissions[owner:SteamID()] then
		Warden.SetupPlayer(owner)
	end

	return Warden.HasPermission(receiver, owner, permission)
end

function Warden.HasPermissionLocal(receiver, granter, permission)
	if not Warden.Permissions[granter:SteamID()] then
		Warden.SetupPlayer(granter)
	end

	return Warden.Permissions[granter:SteamID()][permission][receiver:SteamID()] or false
end

function Warden.HasPermissionGlobal(ply, permission)
	if not Warden.Permissions[ply:SteamID()] then
		Warden.SetupPlayer(ply)
	end

	return Warden.Permissions[ply:SteamID()][permission].global or false
end

function Warden.HasPermission(receiver, granter, permission)
	if not Warden.Permissions[granter:SteamID()] then
		Warden.SetupPlayer(granter)
	end
	if receiver == granter then return true end

	if permission ~= Warden.PERMISSION_ALL and Warden.HasPermission(receiver, granter, Warden.PERMISSION_ALL) then
		return true
	end

	return Warden.Permissions[granter:SteamID()][permission].global or Warden.Permissions[granter:SteamID()][permission][receiver:SteamID()] or false
end

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "WardenPlayerDisconnect", function(data)
	local steamid = data.networkid
	Warden.Permissions[steamid] = nil
end)

if SERVER then
	util.AddNetworkString("WardenUpdatePermission")
	util.AddNetworkString("WardenInitialize")

	local initialized = {}
	net.Receive("WardenInitialize", "Warden", function(_, ply)
		if initialized[ply] then return end
		initialized[ply] = true

		Warden.SetupPlayer(ply)
		net.Start("WardenInitialize")
		net.WriteUInt(#Warden.Permissions, 8)
		for steamid, perms in pairs(Warden.Permissions) do
			net.WriteString(steamid)
			net.WriteUInt(#perms, 8)
			for permisson, ssteamids in pairs(perms) do
				net.WriteUInt(permisson, 8)

				local toSend = {}
				for ssteamid, granted in pairs(ssteamids) do
					if granted then
						table.insert(toSend, ssteamid)
					end
				end
				net.WriteUInt(#toSend, 8)
				for _, ssteamid in ipairs(toSend) do
					net.WriteString(ssteamid)
				end
			end
		end
	end)

	Warden.Ownership = Warden.Ownership or {}
	Warden.Players = Warden.Players or {}

	function Warden.SetOwner(ent, ply)
		local index = ent:EntIndex()
		local steamid = ply:SteamID()

		-- Cleanup original ownership if has one
		if Warden.Ownership[index] then
			local lastOwner = Warden.Ownership[index]

			if Warden.Players[lastOwner.steamid] then
				Warden.Players[lastOwner.steamid][index] = nil
			end
		end

		Warden.Ownership[index] = {
			ent = ent,
			owner = ply,
			steamid = steamid,
		}

		if not Warden.Players[steamid] then
			Warden.Players[steamid] = {}
		end

		Warden.Players[steamid][index] = true

		ent:SetNWString("Owner", ply:Nick())
		ent:SetNWString("OwnerID", ply:SteamID())
		ent:SetNWEntity("OwnerEnt", ply)
	end

	function Warden.ClearOwner(ent)
		local index = ent:EntIndex()
		local ownership = Warden.Ownership[index]
		if ownership then
			Warden.Players[ownership.steamid][index] = nil
			Warden.Ownership[index] = nil
		end

		ent:SetNWString("Owner", nil)
		ent:SetNWString("OwnerID", nil)
		ent:SetNWEntity("OwnerEnt", nil)
	end

	function Warden.GetOwner(ent)
		local ownership = Warden.Ownership[ent:EntIndex()]
		return ownership and ownership.owner
	end

	hook.Add("PlayerInitialSpawn", "Warden", function(ply)
		if Warden.Players[ply:SteamID()] then
			for entIndex, _ in pairs(Warden.Players[ply:SteamID()]) do
				Warden.SetOwner(Entity(entIndex), ply)
			end
		end
	end)

	net.Receive("WardenUpdatePermission", function(_, ply)
		local permission = net.ReadUInt(8)
		if not Warden.PermissionList[permission] then return end

		local granting = net.ReadBool()
		if net.ReadBool() then
			local receiver = net.ReadEntity()
			if IsValid(receiver) then
				if granting then
					Warden.GrantPermission(ply, receiver, permission)
				else
					Warden.RevokePermission(ply, receiver, permission)
				end
			end
		else
			if granting then
				Warden.GrantPermission(ply, nil, permission)
			else
				Warden.RevokePermission(ply, nil, permission)
			end
		end
	end)

	local function networkPermission(ply, receiver, permission, granting)
		net.Start("WardenUpdatePermission")
		net.WriteBool(granting) -- Granting = true, Revoking = false
		net.WriteUInt(permission, 8) -- Permission index
		net.WriteEntity(ply) -- Player granting the permission
		if receiver then
			net.WriteBool(false) -- Is Global Permission
			net.WriteEntity(receiver) -- Player receiving the permission
		else
			net.WriteBool(true)
		end
		net.Broadcast()
	end

	function Warden.GrantPermission(granter, receiver, permission)
		if not Warden.Permissions[granter] then
			Warden.SetupPlayer(granter)
		end

		if IsValid(receiver) and receiver:IsPlayer() then
			Warden.Permissions[granter:SteamID()][permission][receiver:SteamID()] = true
			networkPermission(granter, receiver, permission, true)
		else
			Warden.Permissions[granter:SteamID()][permission]["global"] = true
			networkPermission(granter, nil, permission, true)
		end
	end

	function Warden.RevokePermission(revoker, receiver, permission)
		if not Warden.Permissions[revoker:SteamID()][permission] then
			Warden.SetupPlayer(revoker)
		end

		if IsValid(receiver) and receiver:IsPlayer() then
			Warden.Permissions[revoker:SteamID()][permission][receiver:SteamID()] = false
			networkPermission(revoker, receiver, permission, false)
		else
			Warden.Permissions[revoker:SteamID()][permission]["global"] = false
			networkPermission(revoker, nil, permission, false)
		end
	end

	-- Assigning spawned props to their owners
	local plyMeta = FindMetaTable("Player")
	if plyMeta.AddCount then
		Warden.BackupAddCount = Warden.BackupAddCount or plyMeta.AddCount
		function plyMeta:AddCount(enttype, ent)
			Warden.SetOwner(ent, self)
			Warden.BackupAddCount(self, enttype, ent)
		end
	end

	if cleanup then
		Warden.BackupCleanupAdd = Warden.BackupCleanupAdd or cleanup.Add
		function cleanup.Add(ply, enttype, ent)
			Warden.SetOwner(ent, ply)
			Warden.BackupCleanupAdd(ply, enttype, ent)
		end

		Warden.BackupUndoReplaceEntity = Warden.BackupUndoReplaceEntity or undo.ReplaceEntity
		function undo.ReplaceEntity(from, to)
			if Warden.Ownership[from:EntIndex()] then
				Warden.SetOwner(to, Warden.Ownership[from:EntIndex()].owner)
			end

			return Warden.BackupUndoReplaceEntity(from, to)
		end
	end

	hook.Add("PlayerSpawnedEffect",  "Warden", function(ply, _, ent) Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedProp",    "Warden", function(ply, _, ent) Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedRagdoll", "Warden", function(ply, _, ent) Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedNPC",     "Warden", function(ply, ent)    Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedSENT",    "Warden", function(ply, ent)    Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedSWEP",    "Warden", function(ply, ent)    Warden.SetOwner(ent, ply) end)
	hook.Add("PlayerSpawnedVehicle", "Warden", function(ply, ent)    Warden.SetOwner(ent, ply) end)

	hook.Add("EntityRemoved", "Warden", Warden.ClearOwner)

	hook.Add("CanTool", "Warden", function(ply, tr, tool)
		local ent = tr.Entity
		if not IsValid(ent) and not ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenCanTool", ply, tr, tool)
		if override ~= nil then return override end

		if ent:IsWorld() then return true end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_TOOL)
	end)

	hook.Add("PhysgunPickup", "Warden", function(ply, ent)
		if ent and ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenPhysgunPickup", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_PHYSGUN)
	end)

	hook.Add("GravGunPickupAllowed", "Warden", function(ply, ent)
		if ent and ent:IsWorld() then return true end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenGravGunPickupAllowed", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_GRAVGUN)
	end)

	hook.Add("GravGunPunt", "Warden", function(ply, ent)
		if ent and ent:IsWorld() then return true end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenGravGunPunt", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_GRAVGUN)
	end)

	hook.Add("PlayerUse", "Warden", function(ply, ent)
		if ent:IsWorld() then return true end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenPlayerUse", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_USE)
	end)

	hook.Add("EntityTakeDamage", "Warden", function(ent, dmg)
		if ent and ent:IsWorld() then return end
		local override = hook.Run("WardenEntityTakeDamage", ent, dmg)
		if override ~= nil then return override end

		local attacker = dmg:GetAttacker()
		local inflictor = dmg:GetInflictor()

		if attacker:IsPlayer() then
			if Warden.CheckPermission(attacker, ent, Warden.PERMISSION_DAMAGE) then
				return
			end
		elseif inflictor:IsValid() then
			local owner = Warden.GetOwner(inflictor)
			if owner and owner:IsPlayer() and Warden.CheckPermission(owner, ent, Warden.PERMISSION_DAMAGE) then
				return
			end
		end
		return true
	end)

	hook.Add("CanProperty", "Warden", function(ply, property, ent)
		if ent and ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenCanProperty", ply, property, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_TOOL)
	end)

	hook.Add("CanEditVariable", "Warden", function(ent, ply, key, val, editor)
		if ent and ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenCanEditVariable", ent, ply, key, val, editor)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_TOOL)
	end)

	hook.Add("OnPhysgunReload", "Warden", function(wep, ply)
		local ent = ply:GetEyeTrace().Entity
		if not IsValid(ent) then return false end

		local override = hook.Run("WardenOnPhysgunReload", wep, ply)
		if override ~= nil then return override end

		if not Warden.CheckPermission(ply, ent, Warden.PERMISSION_PHYSGUN) then
			return false
		end
	end)

	return
end

-- Ask server for permission info
hook.Add("InitPostEntity", "Warden", function()
	net.Start("WardenInitialize")
	net.SendToServer()
end)

net.Receive("WardenInitialize", "Warden", function(_, ply)
	local n = net.ReadUInt(8)
	for i = 1, n do
		local granter = net.ReadString()

		local o = net.WriteUInt(8)
		for j = 1, o do
			local permission = net.ReadUInt(8)

			local p = net.ReadUInt(8)
			for k = 1, p do
				local reciever = net.ReadString()

				Warden.SetupSteamID(granter)
				Warden.Permissions[granter][permission][reciever] = true
			end
		end
	end
end)

-- Clientside permission setting
function Warden.GetOwner(ent)
	return ent:GetNWEntity("OwnerEnt")
end

net.Receive("WardenUpdatePermission", function()
	local granting = net.ReadBool()
	local permission = net.ReadUInt(8)
	local granter = net.ReadEntity()

	if not Warden.Permissions[granter:SteamID()] then
		Warden.SetupPlayer(granter)
	end

	if net.ReadBool() then
		Warden.Permissions[granter:SteamID()][permission]["global"] = granting
	else
		local receiver = net.ReadEntity()
		if IsValid(receiver) and receiver:IsPlayer() then
			Warden.Permissions[granter:SteamID()][permission][receiver:SteamID()] = granting
		end
	end
end)

local function networkPermission(receiver, permission, granting)
	net.Start("WardenUpdatePermission")
	net.WriteUInt(permission, 8)
	net.WriteBool(granting)
	if receiver then
		net.WriteBool(true)
		net.WriteEntity(receiver)
	else
		net.WriteBool(false)
	end
	net.SendToServer()
end

function Warden.GrantPermission(receiver, permission)
	networkPermission(receiver, permission, true)
end

function Warden.RevokePermission(receiver, permission)
	networkPermission(receiver, permission, false)
end

