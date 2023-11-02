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

static bool install_pragma_davinci_module(NetworkState &nw)
{
	namespace fs = std::filesystem;

	auto assetsDir = util::Path::CreatePath(util::get_program_path()) + "addons/davinci/assets/davinci/";
	auto scriptPath = util::Path::CreatePath(get_danvinci_resolve_script_path(nw));
	try {
		std::filesystem::copy(assetsDir.GetString(), scriptPath.GetString(), std::filesystem::copy_options::recursive | std::filesystem::copy_options::overwrite_existing);
		return true;
	}
	catch(const fs::filesystem_error &e) {
		return false;
	}
	return false;
}

namespace davinci {
	enum class DaVinciErrorCode : uint32_t {
		Success = 0,
		FailedToInstallPFMModule,
		FailedToLoadPFMProject,
		FailedToLaunchDaVinci,
		FailedToWriteTempJsonProject,
		FailedToWriteDaVinciImportScript,

		Count,
	};
};

static davinci::DaVinciErrorCode generate_davinci_project(NetworkState &nw, const std::string &projectFileName, const std::string audioMapJson)
{
	if(!install_pragma_davinci_module(nw))
		return davinci::DaVinciErrorCode::FailedToInstallPFMModule;
	auto udmData = udm::Data::Load(projectFileName);
	if(!udmData)
		return davinci::DaVinciErrorCode::FailedToLoadPFMProject;

	std::string davinciExecutablePath = get_danvinci_resolve_installation_path(nw);

	// davinciExecutablePath += " -nogui";
	uint32_t exitCode;
	auto success = util::start_process(davinciExecutablePath.c_str(), true);
	if(!success)
		return davinci::DaVinciErrorCode::FailedToLaunchDaVinci;

	std::stringstream ssJson;
	udm::to_json(udmData->GetAssetData().GetData(), ssJson);

	filemanager::create_directory("temp");
	// We need to convert the UDM project data to JSON, so we can load it in the davinci script
	std::string jsonFilePath = "temp/davinci_target_project.json";
	std::string jsonFilePathAudioMap = "temp/davinci_target_project_audio_map.json";
	if(!filemanager::write_file(jsonFilePath, ssJson.str()) || !filemanager::write_file(jsonFilePathAudioMap, audioMapJson))
		return davinci::DaVinciErrorCode::FailedToWriteTempJsonProject;
	// util::ScopeGuard sgJson {[&jsonFilePath]() { filemanager::remove_file(jsonFilePath); }};

	auto scriptPath = get_danvinci_resolve_script_path(nw);
	// .scriptlib are automatically loaded on startup, which would be ideal in our case,
	// unfortunately DaVinci Resolve is not fully initialized at that time, which can cause crashes and
	// instability when trying to run the script.
	// std::string scriptFileLocation = scriptPath + "Scripts/Utility/import_pfm_project.scriptlib";

	// The Lua-file will have to be executed by the user manually through the DaVinci Resolve menu:
	// Workspace -> Scripts -> import_pfm_project
	std::string scriptFileLocation = scriptPath + "Scripts/Utility/Import PFM Project.lua";
	// util::ScopeGuard sgDavinciScript {[&scriptFileLocation]() { filemanager::remove_system_file(scriptFileLocation); }};
	auto f = filemanager::open_system_file(scriptFileLocation, filemanager::FileMode::Write);
	if(!f)
		return davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript;
	auto programPath = util::Path::CreatePath(util::get_program_path()).GetString();
	std::stringstream ss;
	ss << "require(\"pragma\")\n\n";
	ss << "local pragmaInstallPath = \"" << programPath << "\"\n";
	ss << "local projectFile = \"" << projectFileName << "\"\n";
	ss << "local jsonProjectFilePath = \"" << jsonFilePath << "\"\n";
	ss << "local jsonAudioMapFilePath = \"" << jsonFilePathAudioMap << "\"\n";
	ss << "print(\"pragmaInstallPath: \", pragmaInstallPath)\n";
	ss << "print(\"projectFile: \", projectFile)\n";
	ss << "print(\"jsonProjectFilePath: \", jsonProjectFilePath)\n";
	ss << "print(\"jsonAudioMapFilePath: \", jsonAudioMapFilePath)\n";
	ss << "local res, errMsg = pfm.import_project(\"" << programPath << "\", \"" << jsonFilePath << "\", \"" << jsonFilePathAudioMap << "\")\n";
	ss << "if(res == false) then\n";
	ss << "\tprint(\"Failed to import PFM project: \", errMsg)\n";
	ss << "end\n";
	ss << "os.remove(\"" << scriptFileLocation << "\")\n";
	ss << "os.remove(\"" << (util::Path::CreatePath(util::get_program_path()) + jsonFilePath).GetString() << "\")\n";
	ss << "os.remove(\"" << (util::Path::CreatePath(util::get_program_path()) + jsonFilePathAudioMap).GetString() << "\")\n";
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
	    {"RESULT_FAILED_TO_INSTALL_PFM_MODULE", umath::to_integral(davinci::DaVinciErrorCode::FailedToInstallPFMModule)},
	    {"RESULT_FAILED_TO_LOAD_PFM_PROJECT", umath::to_integral(davinci::DaVinciErrorCode::FailedToLoadPFMProject)},
	    {"RESULT_FAILED_TO_LAUNCH_DAVINCI", umath::to_integral(davinci::DaVinciErrorCode::FailedToLaunchDaVinci)},
	    {"RESULT_FAILED_TO_WRITE_TEMP_JSON_PROJECT", umath::to_integral(davinci::DaVinciErrorCode::FailedToWriteTempJsonProject)},
	    {"RESULT_FAILED_TO_WRITE_DAVINCI_IMPORT_SCRIPT", umath::to_integral(davinci::DaVinciErrorCode::FailedToWriteDaVinciImportScript)},
	    {"RESULT_COUNT", umath::to_integral(davinci::DaVinciErrorCode::Count)},
	  });
}

// Called when the Lua state is about to be closed.
DLLEXPORT void pragma_terminate_lua(Lua::Interface &lua) {}
};
