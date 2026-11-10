function data()
	return {
		type = "rename_scheme_component",
		data = {
			schemeComponentNameRaw = "slnamer_name",
			schemeComponentNameTranslated = _("Town - Vehicle - Route"),
			renameFnDefinition = {
				fileName = resolve("scheme_component_slnamer_name.script@renameFn"),
				params = {},
			},
		},
	}
end
