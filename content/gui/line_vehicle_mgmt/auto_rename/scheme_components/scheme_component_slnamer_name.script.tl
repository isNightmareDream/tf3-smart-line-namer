local record Core
	lineName : function(Engine.Entity) : string
end

local core = ug_require "/gui/line_vehicle_mgmt/auto_rename/smart_line_namer_core.tl" as Core

local Ret = {
	renameFn = function(p : AutoRename.RenameParams) : string
		return core.lineName(p.lineEntity)
	end,
}

return Ret
