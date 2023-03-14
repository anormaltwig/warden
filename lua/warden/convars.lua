if SERVER then
	CreateConVar("warden_freeze_disconnect", 1, nil, "Freeze owned entities on player disconnect", 0, 1)
	CreateConVar("warden_cleanup_disconnect", 1, nil, "Cleanup owned entities on player disconnect", 0, 1)
	CreateConVar("warden_cleanup_time", 600, nil, "Time in seconds until cleanup after player disconnect", 0)

	return
end

