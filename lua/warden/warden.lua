function Warden.SetupPlayer(plyOrID)
	if not isstring(plyOrID) then
		plyOrID = plyOrID:SteamID()
	end

	Warden.Permissions[plyOrID] = {}
	for _, id in pairs(Warden.PermissionIDs) do
		Warden.Permissions[plyOrID][id] = { global = false }
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

function Warden.PlayerIsDisconnected(steamid)
	local ply = Warden.GetPlayerFromSteamID(steamid)
	return not IsValid(ply)
end

local worldEntityPermissions = {
	[Warden.PERMISSION_ALL] = false,
	[Warden.PERMISSION_PHYSGUN] = false,
	[Warden.PERMISSION_GRAVGUN] = true,
	[Warden.PERMISSION_TOOL] = false,
	[Warden.PERMISSION_USE] = true,
	[Warden.PERMISSION_DAMAGE] = true,
}

local function adminCheck(ply, permission)
	local permLevel = GetConVar("warden_admin_level_" .. Warden.PermissionList[permission].id):GetInt()
	if permLevel < 0 then
		permLevel = Warden.PermissionList[permission].defaultAdminLevel
	end

	return permLevel <= ply:WardenGetAdminLevel()
end

function Warden.CheckPermission(ent, checkEnt, permission)
	if not (IsValid(checkEnt) or checkEnt:IsWorld()) then return false end
	if not ent then return false end
	local receiver
	if ent:IsPlayer() then
		if adminCheck(ent, permission) then
			return true
		end

		receiver = ent
	else
		local owner = Warden.GetOwner(ent)
		if IsValid(owner) then
			if owner:IsPlayer() then
				receiver = owner
			elseif owner:IsWorld() then
				return worldEntityPermissions[permission]
			else
				return false
			end
		else
			return false
		end
	end

	if checkEnt:IsPlayer() then
		if checkEnt:IsBot() and GetConVar("warden_always_target_bots"):GetBool() then
			return true
		end

		return Warden.HasPermission(receiver, checkEnt, permission)
	end

	local owner = Warden.GetOwner(checkEnt)
	if not IsValid(owner) then return false end

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

	local override = hook.Run("WardenCheckPermission", receiver, granter, permission)
	if override ~= nil then
		return override
	end

	if receiver == granter then return true end

	if permission ~= Warden.PERMISSION_ALL and Warden.HasPermission(receiver, granter, Warden.PERMISSION_ALL) then
		return true
	end

	--make individual permissions exclude players when the global permission is set
	--we do 'or false' to ensure the permission isn't nil for the inequality
	local perm = Warden.Permissions[granter:SteamID()][permission]
	return (perm.global or false) ~= (perm[receiver:SteamID()] or false)
end

gameevent.Listen("player_disconnect")

if SERVER then
	util.AddNetworkString("WardenUpdatePermission")
	util.AddNetworkString("WardenInitialize")

	local initialized = {}
	net.Receive("WardenInitialize", function(_, ply)
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
		net.Send(ply)
	end)

	Warden.Ownership = Warden.Ownership or {}
	Warden.Players = Warden.Players or {}

	function Warden.SetOwner(ent, ply)
		if not IsValid(ent) or not IsValid(ply) then
			return
		end

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
			if Warden.Players[ownership.steamid] then
				Warden.Players[ownership.steamid][index] = nil
			end

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

	function Warden.SetOwnerWorld(ent)
		local world = game.GetWorld()

		local index = ent:EntIndex()

		-- Cleanup original ownership if has one
		if Warden.Ownership[index] then
			local lastOwner = Warden.Ownership[index]

			if Warden.Players[lastOwner.steamid] then
				Warden.Players[lastOwner.steamid][index] = nil
			end
		end

		Warden.Ownership[index] = {
			ent = ent,
			owner = world,
			steamid = "World",
		}

		ent:SetNWString("Owner", "World")
		ent:SetNWString("OwnerID", "World")
		ent:SetNWEntity("OwnerEnt", world)
	end

	hook.Add("OnEntityCreated", "Warden", function(ent)
		timer.Simple(0, function()
			if ent:IsValid() and not Warden.GetOwner(ent) then
				Warden.SetOwnerWorld(ent)
			end
		end)
	end)

	hook.Add("PlayerInitialSpawn", "Warden", function(ply)
		if Warden.Players[ply:SteamID()] then
			for entIndex, _ in pairs(Warden.Players[ply:SteamID()]) do
				Warden.SetOwner(Entity(entIndex), ply)
			end
		end

		timer.Remove("WardenCleanup#" .. ply:SteamID())
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
		if not Warden.Permissions[granter:SteamID()] then
			Warden.SetupPlayer(granter)
		end

		if IsValid(receiver) and receiver:IsPlayer() then
			if Warden.Permissions[granter:SteamID()][permission]["global"] then
				hook.Run("WardenRevokePermission", granter, receiver, Warden.PermissionList[permission].id, true)
			else
				hook.Run("WardenGrantPermission", granter, receiver, Warden.PermissionList[permission].id)
			end

			Warden.Permissions[granter:SteamID()][permission][receiver:SteamID()] = true
			networkPermission(granter, receiver, permission, true)
		else
			hook.Run("WardenGrantPermissionGlobal", granter, Warden.PermissionList[permission].id)
			Warden.Permissions[granter:SteamID()][permission]["global"] = true
			networkPermission(granter, nil, permission, true)
		end
	end

	function Warden.RevokePermission(revoker, receiver, permission)
		if not Warden.Permissions[revoker:SteamID()][permission] then
			Warden.SetupPlayer(revoker)
		end

		if IsValid(receiver) and receiver:IsPlayer() then
			if Warden.Permissions[revoker:SteamID()][permission]["global"] then
				hook.Run("WardenGrantPermission", revoker, receiver, Warden.PermissionList[permission].id, true)
			else
				hook.Run("WardenRevokePermission", revoker, receiver, Warden.PermissionList[permission].id)
			end

			Warden.Permissions[revoker:SteamID()][permission][receiver:SteamID()] = nil
			networkPermission(revoker, receiver, permission, false)
		else
			hook.Run("WardenRevokePermissionGlobal", revoker, Warden.PermissionList[permission].id)
			Warden.Permissions[revoker:SteamID()][permission]["global"] = nil
			networkPermission(revoker, nil, permission, false)
		end
	end

	function Warden.FreezeEntities(steamid)
		local tbl = Warden.Players[steamid]
		local count = 0
		if tbl then
			for entIndex, _ in pairs(tbl) do
				local ent = Entity(entIndex)
				for i = 0, ent:GetPhysicsObjectCount() - 1 do
					local phys = ent:GetPhysicsObjectNum(i)
					phys:EnableMotion(false)
				end
				count = count + 1
			end
		end
		hook.Run("WardenFreeze", steamid, count)
	end

	function Warden.CleanupEntities(steamid)
		local tbl = Warden.Players[steamid]
		local count = 0
		if tbl then
			for entIndex, _ in pairs(tbl) do
				Entity(entIndex):Remove()
			end
			count = count + 1
		end
		hook.Run("WardenCleanup", steamid, count)
	end

	function Warden.FreezeDisconnected()
		for steamid, _ in pairs(Warden.Players) do
			if Warden.PlayerIsDisconnected(steamid) then
				Warden.FreezeEntities(steamid)
			end
		end
	end

	function Warden.CleanupDisconnected()
		for steamid, _ in pairs(Warden.Players) do
			if Warden.PlayerIsDisconnected(steamid) then
				Warden.CleanupEntities(steamid)
			end
		end
	end

	function Warden.GetOwnedEntities(steamid)
		local tbl = Warden.Players[steamid]
		local ents = {}
		if tbl then
			for entIndex, _ in pairs(tbl) do
				table.insert(ents, Entity(entIndex))
			end
		end
		return ents
	end

	function Warden.GetOwnedEntitiesByClass(steamid, class)
		local tbl = Warden.Players[steamid]
		local ents = {}
		if tbl then
			for entIndex, _ in pairs(tbl) do
				local entity = Entity(entIndex)
				if entity:GetClass() == class then
					table.insert(ents, entity)
				end
			end
		end
		return ents
	end

	-- Assigning spawned props to their owners
	local plyMeta = FindMetaTable("Player")
	if plyMeta.AddCount then
		local backupPlyAddCount = plyMeta.AddCount
		function plyMeta:AddCount(enttype, ent)
			Warden.SetOwner(ent, self)
			backupPlyAddCount(self, enttype, ent)
		end
	end
	if plyMeta.AddCleanup then
		local backupPlyAddCleanup = plyMeta.AddCleanup
		function plyMeta:AddCleanup(enttype, ent)
			Warden.SetOwner(ent, self)
			backupPlyAddCleanup(self, enttype, ent)
		end
	end

	function plyMeta:WardenGetAdminLevel()
		if GetConVar("warden_admin_level_needs_admin"):GetBool() and not self:IsAdmin() then
			return 0
		end

		local adminLevel = self.WardenAdminLevel
		if not adminLevel then
			adminLevel = GetConVar("warden_default_admin_level"):GetInt()
		end

		return adminLevel
	end

	function plyMeta:WardenSetAdminLevel(level)
		self.WardenAdminLevel = level
	end

	if cleanup then
		local backupCleanupAdd = cleanup.Add
		function cleanup.Add(ply, enttype, ent)
			if IsValid(ent) then
				Warden.SetOwner(ent, ply)
			end
			backupCleanupAdd(ply, enttype, ent)
		end
	end
	if undo then
		local backupUndoReplaceEntity = undo.ReplaceEntity
		function undo.ReplaceEntity(from, to)
			if Warden.Ownership[from:EntIndex()] then
				Warden.SetOwner(to, Warden.Ownership[from:EntIndex()].owner)
			end

			return backupUndoReplaceEntity(from, to)
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
		if not ent or ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenPhysgunPickup", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_PHYSGUN)
	end)

	hook.Add("GravGunPickupAllowed", "Warden", function(ply, ent)
		if not ent or ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenGravGunPickupAllowed", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_GRAVGUN)
	end)

	hook.Add("GravGunPunt", "Warden", function(ply, ent)
		if not ent or ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenGravGunPunt", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_GRAVGUN)
	end)

	hook.Add("PlayerUse", "Warden", function(ply, ent)
		if not ent or ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local owner = Warden.GetOwner(ent)
		if owner and owner:IsWorld() then return true end

		local override = hook.Run("WardenPlayerUse", ply, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_USE)
	end)

	hook.Add("EntityTakeDamage", "Warden", function(ent, dmg)
		local override = hook.Run("WardenEntityTakeDamage", ent, dmg)
		if override ~= nil then
			if override then return true end
			return
		end

		if not ent or ent:IsWorld() then return end
		if not ent:IsPlayer() and Warden.GetOwner(ent) == game.GetWorld() then return end

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
		if not ent or ent:IsWorld() then return false end
		if not IsValid(ply) then return false end

		local override = hook.Run("WardenCanProperty", ply, property, ent)
		if override ~= nil then return override end

		return Warden.CheckPermission(ply, ent, Warden.PERMISSION_TOOL)
	end)

	hook.Add("CanEditVariable", "Warden", function(ent, ply, key, val, editor)
		if not ent or ent:IsWorld() then return false end
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

	hook.Add("player_disconnect", "WardenPlayerDisconnect", function(data)
		local steamid = data.networkid
		Warden.Permissions[steamid] = nil

		if GetConVar("warden_freeze_disconnect"):GetBool() then
			Warden.FreezeEntities(steamid)
		end

		if GetConVar("warden_cleanup_disconnect"):GetBool() then
			local time = GetConVar("warden_cleanup_time"):GetInt()
			local name = data.name
			timer.Create("WardenCleanup#" .. steamid, time, 1, function()
				Warden.CleanupEntities(steamid)
				hook.Run("WardenNaturalCleanup", name, time)
			end)
		end
	end)

	return
end

-- Ask server for permission info
hook.Add("InitPostEntity", "Warden", function()
	net.Start("WardenInitialize")
	net.SendToServer()
end)

net.Receive("WardenInitialize", function()
	local n = net.ReadUInt(8)
	for i = 1, n do
		local granter = net.ReadString()

		local o = net.ReadUInt(8)
		for j = 1, o do
			local permission = net.ReadUInt(8)

			local p = net.ReadUInt(8)
			for k = 1, p do
				local receiver = net.ReadString()

				Warden.SetupPlayer(granter)
				Warden.Permissions[granter][permission][receiver] = true
			end
		end
	end
end)

function Warden.GetOwnedEntities(steamid)
	local ents = {}
	for _, ent in ipairs(ents.GetAll()) do
		if ent:GetNWString("OwnerID", "") == steamid then
			table.insert(ents, ent)
		end
	end
	return ents
end

function Warden.GetOwnedEntitiesByClass(steamid, class)
	local ents = {}
	for _, ent in ipairs(ents.FindByClass(class)) do
		if ent:GetNWString("OwnerID", "") == steamid then
			table.insert(ents, ent)
		end
	end
	return ents
end

-- Clientside permission setting
function Warden.GetOwner(ent)
	return ent:GetNWEntity("OwnerEnt")
end

net.Receive("WardenUpdatePermission", function()
	local granting = net.ReadBool()
	local permission = net.ReadUInt(8)
	local granter = net.ReadEntity()

	if not IsValid(granter) or granter:IsPlayer() then
		return
	end

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

hook.Add("player_disconnect", "WardenPlayerDisconnect", function(data)
	local steamid = data.networkid
	Warden.Permissions[steamid] = nil
end)

