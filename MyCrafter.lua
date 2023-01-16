-- Instantiate our new add-on object
MyCrafter = LibStub("AceAddon-3.0"):NewAddon("MyCrafter", "AceEvent-3.0", "AceConsole-3.0")
-- Create a local pointer for readability (not required)
local MyCrafter = MyCrafter


-------------------------------------------------------------------------
------------------------- Lifecycle Functions ---------------------------
-------------------------------------------------------------------------

--- **OnInitialize**, which is called directly after the addon is fully loaded.
--- do init tasks here, like loading the Saved Variables
--- or setting up slash commands.
function MyCrafter:OnInitialize()
	MyCrafter:RegisterChatCommand("mycrafter", MyCrafter.ExportData)
end

--- **OnEnable** which gets called during the PLAYER_LOGIN event, when most of the data provided by the game is already present.
--- Do more initialization here, that really enables the use of your addon.
--- Register Events, Hook functions, Create Frames, Get information from
--- the game that wasn't available in OnInitialize
function MyCrafter:OnEnable()
	-- empty --
end

--- **OnDisable**, which is only called when your addon is manually being disabled.
--- Unhook, Unregister Events, Hide frames that you created.
--- You would probably only use an OnDisable if you want to
--- build a "standby" mode, or be able to toggle modules on/off.
function MyCrafter:OnDisable()
	-- empty --
end

local function getNodeInfo(pathID, skillLineID)
	local children = C_ProfSpecs.GetChildrenForPath(pathID)
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
	local nodeInfo = C_Traits.GetNodeInfo(configID, pathID)
	if nodeInfo.currentRank > 0 then
		return {
			children = children,
			currentRank = nodeInfo.currentRank,
			pathID = pathID
		}
	end
end

local function getFullTabTree(tabTreeID, skillLineID)
	local nodeInfos = {}
	local rootPathID = C_ProfSpecs.GetRootPathForTab(tabTreeID)

	local currentNode = rootPathID
	local nodeStack = {}

	while currentNode do
		local nodeInfo = getNodeInfo(currentNode, skillLineID)
		if nodeInfo then
			table.insert(nodeInfos, nodeInfo)
			for _, child in pairs(nodeInfo.children) do
				table.insert(nodeStack, child)
			end
			nodeInfo.children = nil
		end
		currentNode = table.remove(nodeStack)
	end

	return nodeInfos
end

--- @param skillLineID number the DF id of a profession
--- @return table
local function getFullProfession(skillLineID)
	local tabTreeIDs = C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLineID)
	local allNodes = {}
	for _, tabTreeID in pairs(tabTreeIDs) do
		local nodes = getFullTabTree(tabTreeID, skillLineID)
		if(#nodes > 0) then
			for _, node in pairs(nodes) do
				table.insert(allNodes, node)
			end
		end
	end

	return allNodes
end

local skillLineToTradeSkillLineID = {}
skillLineToTradeSkillLineID[164] = 2822
skillLineToTradeSkillLineID[165] = 2830
skillLineToTradeSkillLineID[171] = 2823
skillLineToTradeSkillLineID[197] = 2831
skillLineToTradeSkillLineID[202] = 2827
skillLineToTradeSkillLineID[333] = 2825
skillLineToTradeSkillLineID[755] = 2829
skillLineToTradeSkillLineID[773] = 2828

function MyCrafter.GetAllProfessionsOffPlayer()
	local prof1, prof2 = GetProfessions();
	local professionIndexes = {prof1, prof2}
	local character = {}

	character["name"] = UnitName("player")
	character["realm"] = { id = GetRealmID()}
	character["professions"] = {}

	for _, professionIndex in pairs(professionIndexes) do


		local name, _, skillLevel, _, _, _, skillLine, skillModifier = GetProfessionInfo(professionIndex)


		local skillLineID = skillLineToTradeSkillLineID[skillLine]
		if skillLineID then

			local profession = {
				name = name,
				skillLineID = skillLineID,
				progress = {
					skill = skillLevel,
					skillModifier = skillModifier,
					pathNodes = getFullProfession(skillLineID)
				}
			}

			table.insert(character.professions, profession)
		end

	end
	if #character["professions"] == 0 then
		character["professions"] = nil
	end
	return character
end

function MyCrafter.ExportData()
	local data = MyCrafter:GetAllProfessionsOffPlayer()

	if not data.professions then
		data = {
			INFO = "You don't have a crafting profession, that is relevant to MyCrafter.io"
		}
	end

	local json = {}

	local function kind_of(obj)
		if type(obj) ~= 'table' then return type(obj) end
		local i = 1
		for _ in pairs(obj) do
			if obj[i] ~= nil then i = i + 1 else return 'table' end
		end
		if i == 1 then return 'table' else return 'array' end
	end

	local function escape_str(s)
		local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t', "|n"}
		local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't', "n"}
		for i, c in ipairs(in_char) do
			s = s:gsub(c, '\\' .. out_char[i])
		end
		return s
	end

	local function parse_str_val(str, pos, val)
		val = val or ''
		local early_end_error = 'End of input found while parsing string.'
		if pos > #str then error(early_end_error) end
		local c = str:sub(pos, pos)
		if c == '"'  then return val, pos + 1 end
		if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
		-- We must have a \ character.
		local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
		local nextc = str:sub(pos + 1, pos + 1)
		if not nextc then error(early_end_error) end
		return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
	end

	function json.stringify(obj, as_key)
		local s = {}  -- We'll build the string as an array of strings to be concatenated.
		local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
		if kind == 'array' then
			if as_key then error('Can\'t encode array as key.') end
			s[#s + 1] = '['
			for i, val in ipairs(obj) do
				if i > 1 then s[#s + 1] = ', ' end
				s[#s + 1] = json.stringify(val)
			end
			s[#s + 1] = ']'
		elseif kind == 'table' then
			if as_key then error('Can\'t encode table as key.') end
			s[#s + 1] = '{'
			for k, v in pairs(obj) do
				if #s > 1 then s[#s + 1] = ', ' end
				s[#s + 1] = json.stringify(k, true)
				s[#s + 1] = ':'
				s[#s + 1] = json.stringify(v)
			end
			s[#s + 1] = '}'
		elseif kind == 'string' then
			return '"' .. escape_str(obj) .. '"'
		elseif kind == 'number' then
			if as_key then return '"' .. tostring(obj) .. '"' end
			return tostring(obj)
		elseif kind == 'boolean' then
			return tostring(obj)
		elseif kind == 'nil' then
			return 'null'
		else
			error('Unjsonifiable type: ' .. kind .. '.')
		end
		return table.concat(s)
	end

	local jString = json.stringify(data)

	local f = MyCrafter:GetMainFrame(jString)
	f:Show()
end

function MyCrafter:GetMainFrame(text)
	-- Basicaly ripped out of the simc addon, please check out their work at https://www.simulationcraft.org/
	-- Frame code largely adapted from https://www.wowinterface.com/forums/showpost.php?p=323901&postcount=2
	if not MyCrafterFrame then

		local f = CreateFrame("Frame", "MyCrafterFrame", UIParent, "DialogBoxFrame")
		f:ClearAllPoints()

		f:SetPoint("CENTER", nil, "CENTER", 0, 0)
		f:SetSize(750, 600)
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight",
			edgeSize = 16,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
		f:SetMovable(true)
		f:SetClampedToScreen(true)
		f:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
			if button == "LeftButton" then
				self:StartMoving()
			end
		end)
		f:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
			self:StopMovingOrSizing()
		end)

		-- scroll frame
		local sf = CreateFrame("ScrollFrame", "MyCrafterScrollFrame", f, "UIPanelScrollFrameTemplate")
		sf:SetPoint("LEFT", 16, 0)
		sf:SetPoint("RIGHT", -32, 0)
		sf:SetPoint("TOP", 0, -32)
		sf:SetPoint("BOTTOM", MyCrafterFrameButton, "TOP", 0, 0)

		-- edit box
		local eb = CreateFrame("EditBox", "MyCrafterEditBox", MyCrafterScrollFrame)
		eb:SetSize(sf:GetSize())
		eb:SetMultiLine(true)
		eb:SetAutoFocus(true)
		eb:SetFontObject("ChatFontNormal")
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		sf:SetScrollChild(eb)

		-- resizing
		f:SetResizable(true)

		f:SetResizeBounds(150, 100, nil, nil)

		local rb = CreateFrame("Button", "MyCrafterResizeButton", f)
		rb:SetPoint("BOTTOMRIGHT", -6, 7)
		rb:SetSize(16, 16)

		rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

		rb:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
			if button == "LeftButton" then
				f:StartSizing("BOTTOMRIGHT")
				self:GetHighlightTexture():Hide() -- more noticeable
			end
		end)
		rb:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
			f:StopMovingOrSizing()
			self:GetHighlightTexture():Show()
			eb:SetWidth(sf:GetWidth())

		end)

		MyCrafterFrame = f
	end
	MyCrafterEditBox:SetText(text)
	MyCrafterEditBox:HighlightText()
	return MyCrafterFrame
end
