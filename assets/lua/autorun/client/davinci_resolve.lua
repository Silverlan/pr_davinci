--[[
    Copyright (C) 2023 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("/pfm/events.lua")

locale.load("davinci.txt")

local defaultExecutablePath
local defaultScriptPath
if os.SYSTEM_WINDOWS then
	defaultExecutablePath = "C:/Program Files/Blackmagic Design/DaVinci Resolve/Resolve.exe"
	defaultScriptPath = "C:/ProgramData/Blackmagic Design/DaVinci Resolve/Fusion/"
else
	defaultExecutablePath = "/opt/resolve/bin/resolve"
	defaultScriptPath = "/opt/resolve/Fusion/"
end
console.register_variable(
	"pfm_davinci_resolve_executable_path",
	udm.TYPE_STRING,
	defaultExecutablePath,
	bit.bor(console.FLAG_BIT_ARCHIVE),
	"The path to the executable for DaVinci Resolve, including the filename."
)

console.register_variable(
	"pfm_davinci_resolve_script_path",
	udm.TYPE_STRING,
	defaultScriptPath,
	bit.bor(console.FLAG_BIT_ARCHIVE),
	'The path to the DaVinci Resolve "Fusion" script location.'
)

pfm.add_event_listener("OnFilmmakerLaunched", function(pm)
	pm:AddEventListener("OnWindowOpened", function(pm, identifier, el)
		if identifier == "render" then
			local miscOptionsButton = el:GetMiscOptionsButton()
			if util.is_valid(miscOptionsButton) then
				miscOptionsButton:AddEventListener("PopulateContextMenu", function(miscOptionsButton, pContext)
					pContext:AddItem(locale.get_text("pfm_davinci_import"), function()
						local r = engine.load_library("davinci/pr_davinci")
						if r ~= true then
							pfm.create_popup_message("Failed to load davinci module: " .. r, 5, gui.InfoBox.TYPE_ERROR)
							return
						end
						local projectFileName = pfm.get_project_manager():GetProjectFileName()
						if projectFileName == nil then
							pfm.create_popup_message("No active project found!", 5, gui.InfoBox.TYPE_WARNING)
							return
						end
						local path = file.find_absolute_path(projectFileName)
						if path == nil then
							pfm.create_popup_message(
								locale.get_text("pfm_davinci_failed_to_determine_project_location"),
								5,
								gui.InfoBox.TYPE_WARNING
							)
							return
						end
						if davinci.is_installed() == false then
							pfm.open_message_prompt(
								locale.get_text("pfm_davinci_installation_not_found"),
								locale.get_text("pfm_davinci_installation_not_found_message"),
								bit.bor(gui.PfmPrompt.BUTTON_YES, gui.PfmPrompt.BUTTON_NO),
								function(bt)
									if bt == gui.PfmPrompt.BUTTON_YES then
										util.open_url_in_browser(
											"https://www.blackmagicdesign.com/products/davinciresolve"
										)
									end
								end
							)
							return
						end
						if pfm.util.export_xml_timeline == nil then
							pfm.log(
								"DaVinci addon has not been loaded!",
								pfm.LOG_CATEGORY_PFM,
								pfm.LOG_SEVERITY_WARNING
							)
							return
						end
						pfm.log("Generating DaVinci Resolve project...", pfm.LOG_CATEGORY_PFM)

						file.create_path("temp")
						local timelineXmlPath = "temp/pfm_davinci_timeline.fcpxml"
						pfm.util.export_xml_timeline(pm, timelineXmlPath)
						local res = davinci.generate_project(timelineXmlPath)
						pfm.log(
							"Result: " .. davinci.result_to_string(res),
							pfm.LOG_CATEGORY_PFM,
							(res == davinci.RESULT_SUCCESS) and pfm.LOG_SEVERITY_NORMAL or pfm.LOG_SEVERITY_ERROR
						)
						if res ~= davinci.RESULT_SUCCESS then
							pfm.create_popup_message(
								locale.get_text(
									"pfm_davinci_failed_to_generate_project",
									{ davinci.result_to_string(res) }
								),
								5,
								gui.InfoBox.TYPE_ERROR
							)
						else
							pfm.open_message_prompt(
								locale.get_text("pfm_davinci_import"),
								locale.get_text("pfm_davinci_import_project"),
								gui.PfmPrompt.BUTTON_OK
							)
						end
					end)
				end)
			end
		end
	end)
end)
