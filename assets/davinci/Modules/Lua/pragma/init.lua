-- Create a new project in DaVinci Resolve

-- Check if the script is running within DaVinci Resolve
if not fusion then
	print("Please run this script in DaVinci Resolve.")
	return
end

require("json")

local function dump(o)
	if type(o) == "table" then
		local s = "{ "
		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = '"' .. k .. '"'
			end
			s = s .. "[" .. k .. "] = " .. dump(v) .. ",\n"
		end
		return s .. "} "
	else
		return tostring(o)
	end
end

local function import_audio(project, jsonData)
	local audioItems = {}
	local session = jsonData["session"]
	for _, clip in ipairs(session["clips"]) do
		local soundTrackGroup
		for _, trackGroup in ipairs(clip["trackGroups"]) do
			if trackGroup["name"] == "Sound" then
				soundTrackGroup = trackGroup
				break
			end
		end
		if soundTrackGroup ~= nil then
			for _, track in ipairs(soundTrackGroup["tracks"] or {}) do
				-- TODO: Add new audio clip with track["name"]
				for _, audioClip in ipairs(track["audioClips"] or {}) do
					local sound = (audioClip ~= nil) and audioClip["sound"] or nil
					local timeFrame = (audioClip ~= nil) and audioClip["timeFrame"] or nil
					if sound ~= nil and timeFrame ~= nil then
						local soundName = sound["soundName"]

						local start = timeFrame["start"]
						local duration = timeFrame["duration"]

						local audioPath = "E:/projects/pragma/build/install/addons/imported/sounds/" -- TODO
						local audioItem = project:GetMediaPool():ImportMedia(audioPath .. soundName)
						if audioItem[1] ~= nil then
							table.insert(audioItems, {
								audioItem = audioItem[1],
								start = start,
								duration = duration,
							})
						end
					end
				end
			end
		end
	end
	return audioItems
end

local function import_frames(project)
	local renderRootPath = "F:/projects/pragma/build_winx64/install/addons/filmmaker/render/new_project/shot1/"
	local startFrame = 2
	local endFrame = 73

	local tFrames = {}
	for i = startFrame, endFrame do
		local path = renderRootPath .. "frame" .. string.rep("0", 4 - string.len(i)) .. i .. ".png"
		table.insert(tFrames, path)
	end
	return project:GetMediaPool():ImportMedia(tFrames)
end

local function import_project(pragmaRootPath, jsonFilePath)
	print("Importing PFM project...")

	pragmaRootPath = "E:/projects/pragma/build/install/"
	jsonFilePath = "addons/filmmaker/projects/test_audio.json"

	local jsonData
	local function get_json_value(...)
		local v = jsonData
		for _, n in ipairs({ ... }) do
			v = v[n]
			if v == nil then
				return
			end
		end
		return v
	end

	resolve:GetProjectManager():DeleteProject("Pragma_Project")
	local project = resolve:GetProjectManager():CreateProject("Pragma_Project")
	if project == nil then
		return false, "Failed to create project!"
	end

	local fullJsonPath = pragmaRootPath .. jsonFilePath
	local frameRate = 24
	local f = io.open(fullJsonPath, "r")
	if f == nil then
		return false, "Failed to open JSON project file '" .. fullJsonPath .. "'!"
	end
	local contents = f:read("*a")
	f:close()

	jsonData = json.parse(contents)

	frameRate = get_json_value("session", "settings", "renderSettings", "frameRate") or frameRate
	project:SetSetting("timelineFrameRate", tostring(frameRate))

	local function time_to_frame(t)
		return t * frameRate
	end

	local mediaPoolItems = import_frames(project)
	local timeline = project:GetMediaPool():CreateTimelineFromClips("test", mediaPoolItems)
	if timeline == nil then
		return false, "Failed to create timeline!"
	end

	local audioItems = import_audio(project, jsonData)
	for _, itemData in ipairs(audioItems) do
		local startFrame = time_to_frame(itemData.start)
		project:GetMediaPool():AppendToTimeline({
			{
				["startFrame"] = startFrame,
				["endFrame"] = startFrame + time_to_frame(itemData.duration),
				["mediaPoolItem"] = itemData.audioItem,
				["mediaType"] = 2, -- Audio
			},
		})
	end

	return true
end

pfm = {}
pfm.import_project = function(...)
	return import_project(...)
end
