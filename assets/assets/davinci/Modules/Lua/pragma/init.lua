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
	local audioTimelines = {}
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
				local trackName = track["name"]
				local audioItems = {}
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
							print(
								"Importing audio file '"
									.. soundPath
									.. "' with start time "
									.. start
									.. " and duration "
									.. duration
									.. "!"
							)
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
				if #audioItems > 0 then
					table.insert(audioTimelines, {
						name = trackName,
						audioItems = audioItems,
					})
					table.insert(audioTimelines, {
						name = trackName .. "_2",
						audioItems = audioItems,
					})
				end
			end
		end
	end
	return audioTimelines
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

local function get_null_frame_path(pragmaRootPath)
	return pragmaRootPath .. "addons/davinci/assets/davinci/null_frames/frame%04d.png"
end

local nullAudioItem
local nullAudioItemInitialized = false
local function get_null_audio(pragmaRootPath, project)
	if nullAudioItemInitialized then
		return nullAudioItem
	end
	nullAudioItemInitialized = true
	nullAudioItem = project:GetMediaPool():ImportMedia(pragmaRootPath .. "addons/davinci/assets/davinci/null.mp3")
	if nullAudioItem[1] ~= nil then
		nullAudioItem = nullAudioItem[1]
	else
		nullAudioItem = nil
	end
	return nullAudioItem
end

local function import_frames(project, pragmaRootPath, jsonData, frameRate)
	local pfmPath = pragmaRootPath .. "addons/filmmaker/"
	local session = jsonData["session"]
	local nullPath = get_null_frame_path(pragmaRootPath)
	local tFrames = {}
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

					local path = renderRootPath .. "frame%04d.png"
					local startFrame = 1
					local endFrame = math.ceil(duration * frameRate)
					local frameStart = {
						["effective"] = nil,
						["null"] = nil,
					}
					local function update_frames(identifier, path, startFrame, endFrame)
						if startFrame == nil then
							return
						end
						local items = project:GetMediaPool():ImportMedia({
							{
								["FilePath"] = path,
								["StartIndex"] = startFrame,
								["EndIndex"] = endFrame,
							},
						})
						if items ~= nil then
							for _, item in ipairs(items) do
								table.insert(tFrames, item)
							end
						end
						frameStart[identifier] = nil
					end
					local function update_effective_frames(endFrame)
						return update_frames("effective", path, frameStart["effective"], endFrame)
					end
					local function update_null_frames(endFrame)
						if frameStart["null"] == nil then
							return
						end
						local startFrame = 1
						local endFrame = (endFrame - frameStart["null"]) + 1
						local numFrames = (endFrame - startFrame) + 1
						while numFrames > 0 do
							local numFramesClamped = math.min(numFrames, 100)
							update_frames("null", nullPath, startFrame, (startFrame + numFramesClamped) - 1)
							numFrames = numFrames - numFramesClamped
						end
					end
					for i = startFrame, endFrame do
						local framePath = string.format(path, i)
						if not file_exists(framePath) then
							update_effective_frames(i - 1)
							frameStart["null"] = frameStart["null"] or i
						else
							update_null_frames(i - 1)
							frameStart["effective"] = frameStart["effective"] or i
						end
					end
					update_null_frames(endFrame)
					update_effective_frames(endFrame)
				end
			end
		end
	end
	return tFrames
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
	local function frame_to_time(frame)
		return frame / frameRate
	end

	local mediaPoolItems = import_frames(project, pragmaRootPath, jsonData, frameRate)
	local timeline = project:GetMediaPool():CreateTimelineFromClips("pfm_animation", mediaPoolItems)
	if timeline == nil then
		return false, "Failed to create timeline!"
	end

	local nullAudioItem = get_null_audio(pragmaRootPath, project)
	local trackLastFrame = {}
	local function add_audio_item(trackIndex, audioItem, startFrame, endFrame, isNull, soundStartOffset, soundDuration)
		local lastFrame = trackLastFrame[trackIndex] or -1
		if startFrame > lastFrame + 1 then
			local frame = lastFrame + 1
			if nullAudioItem ~= nil then
				local nullEndFrame = startFrame - 1
				local nullNumFrames = (nullEndFrame - frame) + 1
				add_audio_item(trackIndex, nullAudioItem, frame, nullEndFrame, true, 0, frame_to_time(nullNumFrames))
			else
				print("Unable to insert NULL audio!")
			end
		end
		print(
			"Adding "
				.. (isNull and "NULL " or "")
				.. "audio item '"
				.. tostring(audioItem)
				.. "' to range ["
				.. startFrame
				.. ","
				.. endFrame
				.. "] in track "
				.. trackIndex
				.. "..."
		)
		project:GetMediaPool():AppendToTimeline({
			{
				["startFrame"] = time_to_frame(soundStartOffset),
				["endFrame"] = time_to_frame(soundStartOffset + soundDuration),
				["mediaPoolItem"] = audioItem,
				["mediaType"] = 2, -- Audio
				["trackIndex"] = trackIndex,
			},
		})
		trackLastFrame[trackIndex] = endFrame
	end

	local audioTimelines = import_audio(project, pragmaRootPath, jsonData, jsonAudioMapData)
	local timeline = project:GetCurrentTimeline()
	for trackIndex, timelineData in ipairs(audioTimelines) do
		if timeline:GetTrackCount("audio") < trackIndex then
			timeline:AddTrack("audio", "stereo")
		end
		timeline:SetTrackName("audio", trackIndex, timelineData.name)
		for _, itemData in ipairs(timelineData.audioItems) do
			local startTime = itemData.start
			local startFrame = time_to_frame(startTime)
			local endFrame = time_to_frame(startTime + itemData.duration)
			add_audio_item(trackIndex, itemData.audioItem, startFrame, endFrame, false, 0, itemData.duration)
		end
	end

	return true
end

pfm = {}
pfm.import_project = function(...)
	return import_project(...)
end
