Warden.PermissionList = Warden.PermissionList or {}
Warden.PermissionIDs = Warden.PermissionIDs or {}

Warden.Permissions = Warden.Permissions or {}

function Warden.CreatePermission(id, name, desc, priority)
	local index = table.insert(Warden.PermissionList, {
		id = id,
		name = name,
		description = desc,
		priority = priority,
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

Warden.PERMISSION_ALL     = Warden.CreatePermission("whitelist", "Whitelist", "Grants full permissions.")
Warden.PERMISSION_PHYSGUN = Warden.CreatePermission("physgun", "Physgun", "Allows users to pickup your stuff with the physgun.")
Warden.PERMISSION_GRAVGUN = Warden.CreatePermission("gravgun", "Gravgun", "Allows users to pickup your stuff with the gravgun.")
Warden.PERMISSION_TOOL    = Warden.CreatePermission("tool", "Toolgun", "Allows users to use the toogun on your stuff.")
Warden.PERMISSION_USE     = Warden.CreatePermission("use", "Use (E)", "Allows users to sit in your seats, use your wire buttons, etc.")
Warden.PERMISSION_DAMAGE  = Warden.CreatePermission("damage", "Damage", "Allows users to damage you and your stuff (excluding ACF).")

