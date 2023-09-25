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

	if SERVER then
		CreateConVar("warden_admin_level_" .. id, -1, FCVAR_REPLICATED, "Set the admin level needed for admins to override this permission.", -1, 99)
	end

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

