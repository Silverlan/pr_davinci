#include "pr_module.hpp"
#include <pragma/lua/luaapi.h>
#include <pragma/console/conout.h>
#include <pragma/networkstate/networkstate.h>
#include <pragma/lua/converters/game_type_converters_t.hpp>
#include <luainterface.hpp>
#include <sharedutils/util.h>
#include <sharedutils/scope_guard.h>
#include <fsys/filesystem.h>
#include <filesystem>
#include <udm.hpp>
#pragma optimize("", off)
static std::string get_danvinci_resolve_installation_path(NetworkState &nw) { return nw.GetConVarString("pfm_davinci_resolve_executable_path"); }

static std::string get_danvinci_resolve_script_path(NetworkState &nw) { return nw.GetConVarString("pfm_davinci_resolve_script_path"); }

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
	auto success = util::start_process(davinciExecutablePath.c_str(), true);
	if(!success)
		return davinci::DaVinciErrorCode::FailedToLaunchDaVinci;

	std::string absTimelineXmlPath;
	if(!FileManager::FindAbsolutePath(timelineXmlPath, absTimelineXmlPath))
		return davinci::DaVinciErrorCode::FailedToLocateTimelineFile;

	auto scriptPath = get_danvinci_resolve_script_path(nw);
	std::string scriptFileLocation = scriptPath + "Scripts/Utility/Import PFM Project.lua";
	auto f = filemanager::open_system_file(scriptFileLocation, filemanager::FileMode::Write);
	if(!f)
		return davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript;
	auto programPath = util::Path::CreatePath(util::get_program_path()).GetString();

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
DLLEXPORT bool pragma_attach(std::string &outErr)
{
	// Return true to indicate that the module has been loaded successfully.
	// If the module could not be loaded properly, return false and populate 'outErr' with a descriptive error message.
	Con::cout << "Custom module \"pr_davinci\" has been loaded!" << Con::endl;
	return true;
}

// Called when the module is about to be unloaded
DLLEXPORT void pragma_detach() { Con::cout << "Custom module \"pr_davinci\" is about to be unloaded!" << Con::endl; }

// Lua bindings can be initialized here
DLLEXPORT void pragma_initialize_lua(Lua::Interface &lua)
{
	auto &libDavinci = lua.RegisterLibrary("davinci");
	libDavinci[luabind::def("generate_project", &generate_davinci_project)];
	libDavinci[luabind::def(
	  "is_installed", +[](NetworkState &nw) {
		  auto exePath = get_danvinci_resolve_installation_path(nw);
		  return filemanager::exists_system(exePath);
	  })];
	libDavinci[luabind::def(
	  "result_to_string", +[](davinci::DaVinciErrorCode err) { return std::string {magic_enum::enum_name(err)}; })];

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
DLLEXPORT void pragma_terminate_lua(Lua::Interface &lua) {}
};
