// SPDX-FileCopyrightText: (c) 2023 Silverlan <opensource@pragma-engine.com>
// SPDX-License-Identifier: MIT

import pragma.shared;

static std::string get_danvinci_resolve_installation_path(NetworkState &nw)
{
	auto exePath = nw.GetConVarString("pfm_davinci_resolve_executable_path");
	if(!exePath.empty())
		return exePath;
#ifdef _WIN32
	return "C:/Program Files/Blackmagic Design/DaVinci Resolve/Resolve.exe";
#else
	return "/opt/resolve/bin/resolve";
#endif
}

static std::string get_danvinci_resolve_script_path(NetworkState &nw)
{
	auto scriptPath = nw.GetConVarString("pfm_davinci_resolve_script_path");
	if(!scriptPath.empty())
		return scriptPath;
#ifdef _WIN32
	return "C:/ProgramData/Blackmagic Design/DaVinci Resolve/Fusion/";
#else
	std::vector<util::Path> candidates;
	candidates.reserve(3);
	auto home = util::get_env_variable("HOME");
	if(home)
		candidates.push_back(util::DirPath(*home, ".local/share/DaVinciResolve/Fusion"));
	candidates.push_back(util::DirPath("/opt/resolve/Fusion"));
	candidates.push_back(util::DirPath("/home/resolve/Fusion"));
	for(auto &candidate : candidates) {
		if(filemanager::exists_system(candidate.GetString()))
			return candidate.GetString();
	}
	return {};
#endif
}

namespace davinci {
	enum class DaVinciErrorCode : uint32_t {
		Success = 0,
		FailedToLaunchDaVinci,
		FailedToLocateTimelineFile,
		FailedToWriteDaVinciImportScript,

		Count,
	};
};

static davinci::DaVinciErrorCode generate_davinci_project(NetworkState &nw, const std::string &timelineXmlPath)
{
	std::string davinciExecutablePath = get_danvinci_resolve_installation_path(nw);
	uint32_t exitCode;
	util::CommandInfo cmdInfo;
	cmdInfo.command = davinciExecutablePath;
	cmdInfo.absoluteCommandPath = true;

	// Note: This does not work in a flatpak sandbox.
	// We could use
	// system("flatpak-spawn --host /opt/resolve/bin/resolve");
	// to launch DaVinci Resolve, but that would require
	// --talk-name=org.freedesktop.Flatpak
	// permissions.
	auto success = util::start_process(cmdInfo);
	if(!success)
		return davinci::DaVinciErrorCode::FailedToLaunchDaVinci;

	std::string absTimelineXmlPath;
	if(!FileManager::FindAbsolutePath(timelineXmlPath, absTimelineXmlPath))
		return davinci::DaVinciErrorCode::FailedToLocateTimelineFile;

	auto scriptPath = get_danvinci_resolve_script_path(nw);
	if(scriptPath.empty())
		return davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript;

	std::string scriptFileLocation = util::FilePath(scriptPath, "Scripts/Utility/Import PFM Project.lua").GetString();
	auto f = filemanager::open_system_file(scriptFileLocation, filemanager::FileMode::Write);
	if(!f)
		return davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript;

	std::stringstream ss;
	ss << R"(
local project = resolve:GetProjectManager():CreateProject("Pragma_Project")
local i = 2
while project == nil do
	project = resolve:GetProjectManager():CreateProject("Pragma_Project" .. i)
	i = i + 1
	if i > 1000 then
		break
	end
end
if project == nil then
	return false, "Failed to create project!"
end
)";
	ss << "project:GetMediaPool():ImportTimelineFromFile(\"" + absTimelineXmlPath + "\")\n";
	ss << "os.remove(\"" << scriptFileLocation << "\")\n";
	f->WriteString(ss.str());
	f = nullptr;
	return davinci::DaVinciErrorCode::Success;
}

extern "C" {
// Called after the module has been loaded
PR_EXPORT bool pragma_attach(std::string &outErr)
{
	// Return true to indicate that the module has been loaded successfully.
	// If the module could not be loaded properly, return false and populate 'outErr' with a descriptive error message.
	// Con::cout << "Custom module \"pr_davinci\" has been loaded!" << Con::endl;
	return true;
}

// Called when the module is about to be unloaded
PR_EXPORT void pragma_detach()
{
	// Con::cout << "Custom module \"pr_davinci\" is about to be unloaded!" << Con::endl;
}

// Lua bindings can be initialized here
PR_EXPORT void pragma_initialize_lua(Lua::Interface &lua)
{
	auto &libDavinci = lua.RegisterLibrary("davinci");
	libDavinci[luabind::def("generate_project", &generate_davinci_project)];
	libDavinci[luabind::def(
	  "is_installed", +[](NetworkState &nw) {
		  auto exePath = get_danvinci_resolve_installation_path(nw);
		  return filemanager::exists_system(exePath);
	  })];
	libDavinci[luabind::def("result_to_string", +[](davinci::DaVinciErrorCode err) { return std::string {magic_enum::enum_name(err)}; })];

	Lua::RegisterLibraryEnums(lua.GetState(), "davinci",
	  {
	    {"RESULT_SUCCESS", umath::to_integral(davinci::DaVinciErrorCode::Success)},
	    {"RESULT_FAILED_TO_LOCATE_TIMELINE_FILE", umath::to_integral(davinci::DaVinciErrorCode::FailedToLocateTimelineFile)},
	    {"RESULT_FAILED_TO_LAUNCH_DAVINCI", umath::to_integral(davinci::DaVinciErrorCode::FailedToLaunchDaVinci)},
	    {"RESULT_FAILED_TO_WRITE_DAVINCI_IMPORT_SCRIPT", umath::to_integral(davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript)},
	    {"RESULT_COUNT", umath::to_integral(davinci::DaVinciErrorCode::Count)},
	  });
}

// Called when the Lua state is about to be closed.
PR_EXPORT void pragma_terminate_lua(Lua::Interface &lua) {}
};
