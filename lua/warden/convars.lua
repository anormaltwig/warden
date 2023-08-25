if SERVER then
	CreateConVar("warden_freeze_disconnect", 1, nil, "Freeze owned entities on player disconnect", 0, 1)
	CreateConVar("warden_cleanup_disconnect", 1, nil, "Cleanup owned entities on player disconnect", 0, 1)
	CreateConVar("warden_always_target_bots", 1, FCVAR_REPLICATED, "If true, bots always have all their permissions overridden.", 0, 1)
	CreateConVar("warden_default_admin_level", 0, FCVAR_REPLICATED, "Set the default permission override level for admins.", 0, 3)
	CreateConVar("warden_admin_level_needs_admin", 1, FCVAR_REPLICATED, "If true, admin level *only* works for admins.", 0, 1)
	CreateConVar("warden_cleanup_time", 600, nil, "Time in seconds until cleanup after player disconnect", 0)

	return
end

