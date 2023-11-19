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

local function import_audio(project, pragmaRootPath, jsonData, jsonAudioMapData)
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
						local pitch = sound["pitch"]
						local volume = sound["volume"]
						-- TODO: Can we apply pitch and volume somehow?

						local soundPath = jsonAudioMapData[soundName]
						if soundPath ~= nil then
							print("Importing audio file '" .. soundPath .. "'!")
							local audioItem = project:GetMediaPool():ImportMedia(pragmaRootPath .. soundPath)
							if audioItem[1] ~= nil then
								table.insert(audioItems, {
									audioItem = audioItem[1],
									start = start,
									duration = duration,
								})
							end
						else
							print("Failed to import sound file '" .. soundName .. "'!")
						end
					end
				end
			end
		end
	end
	return audioItems
end

local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function round(v)
	return math.floor(v + 0.5)
end

local function import_frames(project, pragmaRootPath, jsonData, frameRate)
	local pfmPath = pragmaRootPath .. "addons/filmmaker/"
	local session = jsonData["session"]
	local tFrames = {}
	local frameIndices = {}
	for _, clip in ipairs(session["clips"]) do
		local clipName = clip["name"]
		local filmTrackGroup
		for _, trackGroup in ipairs(clip["trackGroups"]) do
			if trackGroup["name"] == "subClipTrackGroup" then
				filmTrackGroup = trackGroup
				break
			end
		end
		if filmTrackGroup ~= nil then
			for _, track in ipairs(filmTrackGroup["tracks"] or {}) do
				for _, filmClip in ipairs(track["filmClips"] or {}) do
					local filmClipName = filmClip["name"]
					local renderRootPath = pfmPath .. "render/" .. clipName .. "/" .. filmClipName .. "/"
					local timeFrame = filmClip["timeFrame"]
					local duration = timeFrame["duration"]
					local start = timeFrame["start"]

					local startFrame = 1
					local endFrame = math.ceil(duration * frameRate)
					for i = startFrame, endFrame do
						-- TODO: Check all supported file extensions
						local path = renderRootPath .. "frame" .. string.rep("0", 4 - string.len(i)) .. i .. ".png"
						if file_exists(path) then
							table.insert(tFrames, path)
							table.insert(frameIndices, round(start * frameRate) + (i - 1))
						end
					end
				end
			end
		end
	end
	return project:GetMediaPool():ImportMedia(tFrames), frameIndices
end

local function import_project(pragmaRootPath, jsonFilePath, jsonAudioMapFilePath)
	print("Importing PFM project...")

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

	local function read_json_path(jsonFilePath)
		local fullJsonPath = pragmaRootPath .. jsonFilePath
		local f = io.open(fullJsonPath, "r")
		if f == nil then
			return false, "Failed to open JSON project file '" .. fullJsonPath .. "'!"
		end
		local contents = f:read("*a")
		f:close()

		return json.parse(contents)
	end

	jsonData = read_json_path(jsonFilePath)
	local jsonAudioMapData = read_json_path(jsonAudioMapFilePath)
	if jsonData == nil or jsonAudioMapData == nil then
		return
	end

	local renderSettings = get_json_value("session", "settings", "renderSettings") or {}

	local frameRate = 24
	frameRate = renderSettings["frameRate"] or frameRate
	project:SetSetting("timelineFrameRate", tostring(frameRate))

	if renderSettings["width"] ~= nil then
		project:SetSetting("timelineResolutionWidth", tostring(renderSettings["width"]))
	end
	if renderSettings["height"] ~= nil then
		project:SetSetting("timelineResolutionHeight", tostring(renderSettings["height"]))
	end
	project:SetSetting("videoCaptureCodec", "H.265")
	project:SetSetting("videoCaptureFormat", "QuickTime")

	local function time_to_frame(t)
		return t * frameRate
	end

	local mediaPoolItems, frameIndices = import_frames(project, pragmaRootPath, jsonData, frameRate)
	local timeline = project:GetMediaPool():CreateTimelineFromClips("pfm_animation", mediaPoolItems)
	if timeline == nil then
		return false, "Failed to create timeline!"
	end

	local audioItems = import_audio(project, pragmaRootPath, jsonData, jsonAudioMapData)
	for _, itemData in ipairs(audioItems) do
		local startFrame = time_to_frame(itemData.start)
		project:GetMediaPool():AppendToTimeline({
			{
				-- ["startFrame"] = startFrame,
				-- ["endFrame"] = startFrame + time_to_frame(itemData.duration),
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
