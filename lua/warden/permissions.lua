Warden.PermissionList = {} --these should reset when the file reloads, otherwise they accumulate keys
Warden.PermissionIDs = {}

Warden.Permissions = Warden.Permissions or {}

function Warden.CreatePermission(id, name, desc, priority, adminLevel)
	local index = table.insert(Warden.PermissionList, {
		id = id,
		name = name,
		description = desc,
		priority = priority,
		defaultAdminLevel = adminLevel,
	})

	if index == nil then return end

	Warden.PermissionIDs[id] = index

	return index
end

function Warden.GetPermissionByID(id)
	return Warden.PermissionIDs[id]
end

function Warden.GetPermissionInfo(id)
	return Warden.PermissionList[Warden.PermissionIDs[id]]
end

Warden.PERMISSION_ALL     = Warden.CreatePermission("whitelist", "Whitelist", "Grants full permissions.", nil, 3)
Warden.PERMISSION_PHYSGUN = Warden.CreatePermission("physgun", "Physgun", "Allows users to pickup your stuff with the physgun.", nil, 1)
Warden.PERMISSION_GRAVGUN = Warden.CreatePermission("gravgun", "Gravgun", "Allows users to pickup your stuff with the gravgun.", nil, 1)
Warden.PERMISSION_TOOL    = Warden.CreatePermission("tool", "Toolgun", "Allows users to use the toogun on your stuff.", nil, 2)
Warden.PERMISSION_USE     = Warden.CreatePermission("use", "Use (E)", "Allows users to sit in your seats, use your wire buttons, etc.", nil, 1)
Warden.PERMISSION_DAMAGE  = Warden.CreatePermission("damage", "Damage", "Allows users to damage you and your stuff (excluding ACF).", nil, 2)

local function setConVar(index, val)
	if val < 0 then
		Warden.PermissionList[index].adminLevel = Warden.PermissionList[index].defaultAdminLevel
		return
	end

	Warden.PermissionList[index].adminLevel = val
end

if SERVER then
	for k, v in pairs(Warden.PermissionList) do
		local convar = CreateConVar("warden_admin_level_" .. v.id, -1, FCVAR_REPLICATED, "Set the admin level needed for admins to override this permission.", -1, 3)
		setConVar(k, convar:GetInt())
		cvars.AddChangeCallback("warden_admin_level_" .. v.id, function(_, _, val)
			setConVar(k, val)

			if CurTime() > 1 then
				print("[WARDEN] Clients won't see this change until they restart.")
			end
		end)
	end
else
	for k, v in pairs(Warden.PermissionList) do
		setConVar(k, GetConVar("warden_admin_level_" .. v.id):GetInt())
	end
end
