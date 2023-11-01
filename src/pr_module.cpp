#include "pr_module.hpp"
#include <pragma/lua/luaapi.h>
#include <pragma/console/conout.h>
#include <luainterface.hpp>
#include <sharedutils/util.h>
#include <sharedutils/scope_guard.h>
#include <fsys/filesystem.h>
#include <filesystem>
#include <udm.hpp>
#pragma optimize("", off)
static std::string get_danvinci_resolve_installation_path()
{
#ifdef _WIN32
	return "C:/Program Files/Blackmagic Design/DaVinci Resolve/"; // TODO: Allow user to specify resolve executable path in PFM settings
#else
	static_assert(false, "Not yet implemented!");
#endif
}

static std::string get_danvinci_resolve_script_path()
{
#ifdef _WIN32
	return "C:/ProgramData/Blackmagic Design/DaVinci Resolve/Fusion/"; // TODO: Allow user to specify resolve executable path in PFM settings
#else
	static_assert(false, "Not yet implemented!");
#endif
}

static bool install_pragma_davinci_module()
{
	namespace fs = std::filesystem;

	auto assetsDir = util::Path::CreatePath(util::get_program_path()) + "addons/davinci/assets/davinci/";
	auto scriptPath = util::Path::CreatePath(get_danvinci_resolve_script_path());
	try {
		std::filesystem::copy(assetsDir.GetString(), scriptPath.GetString(), std::filesystem::copy_options::recursive | std::filesystem::copy_options::overwrite_existing);
		return true;
	}
	catch(const fs::filesystem_error &e) {
		std::cerr << "Filesystem error: " << e.what() << std::endl;
		// Handle the error as needed
		return false;
	}
	// Copy files from "assets/" to "C:/ProgramData/Blackmagic Design/DaVinci Resolve/Fusion/Scripts"
	return false;
}

static bool generate_davinci_project(const std::string &projectFileName)
{
	if(!install_pragma_davinci_module())
		return false;
	auto udmData = udm::Data::Load(projectFileName);
	if(!udmData)
		return false;

	std::string davinciInstallationPath = get_danvinci_resolve_installation_path();
	std::string davinciExecutablePath = davinciInstallationPath;
#ifdef _WIN32
	davinciExecutablePath += "Resolve.exe";
#else
	static_assert(false, "Not yet implemented!");
#endif

	// davinciExecutablePath += " -nogui";
	uint32_t exitCode;
	auto success = util::start_process(davinciExecutablePath.c_str(), true);
	if(!success)
		return false;

	std::stringstream ssJson;
	udm::to_json(udmData->GetAssetData().GetData(), ssJson);

	filemanager::create_directory("temp");
	// We need to convert the UDM project data to JSON, so we can load it in the davinci script
	std::string jsonFilePath = "temp/davinci_target_project.json";
	if(!filemanager::write_file(jsonFilePath, ssJson.str()))
		return false;
	// util::ScopeGuard sgJson {[&jsonFilePath]() { filemanager::remove_file(jsonFilePath); }};

	auto scriptPath = get_danvinci_resolve_script_path();
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
		return false;
	auto programPath = util::Path::CreatePath(util::get_program_path()).GetString();
	std::stringstream ss;
	ss << "require(\"pragma\")\n\n";
	ss << "local pragmaInstallPath = \"" << programPath << "\"\n";
	ss << "local projectFile = \"" << projectFileName << "\"\n";
	ss << "local jsonProjectFilePath = \"" << jsonFilePath << "\"\n";
	ss << "print(\"pragmaInstallPath: \", pragmaInstallPath)\n";
	ss << "print(\"projectFile: \", projectFile)\n";
	ss << "print(\"jsonProjectFilePath: \", jsonProjectFilePath)\n";
	ss << "local res, errMsg = pfm.import_project(\"" << programPath << "\", \"" << jsonFilePath << "\")\n";
	ss << "if(res == false) then\n";
	ss << "\tprint(\"Failed to import PFM project: \", errMsg)\n";
	ss << "end\n";
	ss << "os.remove(\"" << scriptFileLocation << "\")\n";
	ss << "os.remove(\"" << (util::Path::CreatePath(util::get_program_path()) + jsonFilePath).GetString() << "\")\n";
	f->WriteString(ss.str());
	f = nullptr;
	return true;
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
	auto &libDemo = lua.RegisterLibrary("davinci");
	libDemo[luabind::def("generate_project", &generate_davinci_project)];

	struct DemoClass {
		DemoClass() {}
		void PrintWarning(const std::string &msg) { Con::cwar << msg << Con::endl; }
	};
}

// Called when the Lua state is about to be closed.
DLLEXPORT void pragma_terminate_lua(Lua::Interface &lua) {}
};
