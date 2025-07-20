local api = vim.api
local config = require("codeium.config")
local notify = require("codeium.notify")

local M = {}

-- History storage
local history_file = vim.fn.stdpath("cache") .. "/codeium/chat_history.json"
local sessions = {}
local current_session_id = nil

-- Ensure history directory exists
local function ensure_history_dir()
	local dir = vim.fn.fnamemodify(history_file, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

-- Load history from file
function M.load_history()
	ensure_history_dir()

	if vim.fn.filereadable(history_file) == 1 then
		local content = vim.fn.readfile(history_file)
		if #content > 0 then
			local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
			if ok and type(data) == "table" then
				sessions = data.sessions or {}
				current_session_id = data.current_session_id
				return true
			end
		end
	end

	-- Initialize empty history
	sessions = {}
	current_session_id = nil
	return false
end

-- Save history to file
function M.save_history()
	ensure_history_dir()

	local data = {
		sessions = sessions,
		current_session_id = current_session_id,
		last_updated = os.time(),
	}

	local ok, json = pcall(vim.json.encode, data)
	if ok then
		vim.fn.writefile({ json }, history_file)
		return true
	end

	return false
end

-- Create new chat session
function M.create_session(title)
	local session_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
	local session = {
		id = session_id,
		title = title or "Chat Session",
		created_at = os.time(),
		updated_at = os.time(),
		messages = {},
		context_files = {},
		provider = require("codeium.providers").current_provider,
	}

	sessions[session_id] = session
	current_session_id = session_id
	M.save_history()

	return session_id
end

-- Get current session
function M.get_current_session()
	if not current_session_id or not sessions[current_session_id] then
		current_session_id = M.create_session("New Chat")
	end

	return sessions[current_session_id]
end

-- Switch to different session
function M.switch_session(session_id)
	if sessions[session_id] then
		current_session_id = session_id
		M.save_history()
		return true
	end
	return false
end

-- Add message to current session
function M.add_message(role, content, metadata)
	local session = M.get_current_session()
	local message = {
		id = tostring(os.time()) .. "_" .. math.random(1000, 9999),
		role = role,
		content = content,
		timestamp = os.time(),
		metadata = metadata or {},
	}

	table.insert(session.messages, message)
	session.updated_at = os.time()
	M.save_history()

	return message.id
end

-- Update session context files
function M.update_context_files(files)
	local session = M.get_current_session()
	session.context_files = files or {}
	session.updated_at = os.time()
	M.save_history()
end

-- Get session messages for AI context
function M.get_messages_for_context(limit)
	local session = M.get_current_session()
	limit = limit or 10

	local messages = {}
	local start_idx = math.max(1, #session.messages - limit + 1)

	for i = start_idx, #session.messages do
		local msg = session.messages[i]
		table.insert(messages, {
			role = msg.role,
			content = msg.content,
		})
	end

	return messages
end

-- Get all sessions for selection
function M.get_all_sessions()
	local session_list = {}

	for id, session in pairs(sessions) do
		table.insert(session_list, {
			id = id,
			title = session.title,
			created_at = session.created_at,
			updated_at = session.updated_at,
			message_count = #session.messages,
			provider = session.provider,
			is_current = id == current_session_id,
		})
	end

	-- Sort by updated_at descending
	table.sort(session_list, function(a, b)
		return a.updated_at > b.updated_at
	end)

	return session_list
end

-- Show session selection menu
function M.show_session_menu()
	local session_list = M.get_all_sessions()

	if #session_list == 0 then
		notify.info("No chat sessions found")
		return
	end

	local items = {}
	for _, session in ipairs(session_list) do
		local status = session.is_current and " (current)" or ""
		local date = os.date("%Y-%m-%d %H:%M", session.updated_at)
		local preview = ""

		-- Get preview from last user message
		if session.message_count > 0 then
			local full_session = sessions[session.id]
			for i = #full_session.messages, 1, -1 do
				local msg = full_session.messages[i]
				if msg.role == "user" then
					preview = msg.content:sub(1, 50)
					if #msg.content > 50 then
						preview = preview .. "..."
					end
					break
				end
			end
		end

		table.insert(
			items,
			string.format("%s%s - %s (%d msgs) - %s", session.title, status, date, session.message_count, preview)
		)
	end

	-- Add option to create new session
	table.insert(items, "➕ Create New Session")

	vim.ui.select(items, {
		prompt = "Select Chat Session:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		if idx == #items then
			-- Create new session
			vim.ui.input({ prompt = "Session title: " }, function(title)
				if title and title ~= "" then
					local session_id = M.create_session(title)
					notify.info("Created new session: " .. title)
					-- Refresh sidebar if open
					local sidebar = require("codeium.views.sidebar")
					if sidebar.get_state().is_open then
						sidebar.open() -- This will refresh the content
					end
				end
			end)
		else
			-- Switch to selected session
			local selected_session = session_list[idx]
			M.switch_session(selected_session.id)
			notify.info("Switched to session: " .. selected_session.title)

			-- Refresh sidebar if open
			local sidebar = require("codeium.views.sidebar")
			if sidebar.get_state().is_open then
				sidebar.open() -- This will refresh the content
			end
		end
	end)
end

-- Delete session
function M.delete_session(session_id)
	if not sessions[session_id] then
		return false
	end

	sessions[session_id] = nil

	-- If deleting current session, switch to most recent
	if current_session_id == session_id then
		local session_list = M.get_all_sessions()
		if #session_list > 0 then
			current_session_id = session_list[1].id
		else
			current_session_id = nil
		end
	end

	M.save_history()
	return true
end

-- Clear current session
function M.clear_current_session()
	local session = M.get_current_session()
	session.messages = {}
	session.updated_at = os.time()
	M.save_history()

	notify.info("Cleared current session")
end

-- Export session to file
function M.export_session(session_id, file_path)
	local session = sessions[session_id]
	if not session then
		return false
	end

	local export_data = {
		title = session.title,
		created_at = os.date("%Y-%m-%d %H:%M:%S", session.created_at),
		provider = session.provider,
		messages = session.messages,
		context_files = session.context_files,
	}

	local lines = {}
	table.insert(lines, "# " .. export_data.title)
	table.insert(lines, "")
	table.insert(lines, "**Created:** " .. export_data.created_at)
	table.insert(lines, "**Provider:** " .. export_data.provider)
	table.insert(lines, "")

	if #export_data.context_files > 0 then
		table.insert(lines, "## Context Files")
		for _, file in ipairs(export_data.context_files) do
			table.insert(lines, "- " .. file)
		end
		table.insert(lines, "")
	end

	table.insert(lines, "## Conversation")
	table.insert(lines, "")

	for _, message in ipairs(export_data.messages) do
		local timestamp = os.date("%H:%M:%S", message.timestamp)
		table.insert(lines, string.format("### %s [%s]", message.role:upper(), timestamp))
		table.insert(lines, "")
		table.insert(lines, message.content)
		table.insert(lines, "")
	end

	vim.fn.writefile(lines, file_path)
	return true
end

-- Initialize history system
function M.setup()
	M.load_history()

	-- Auto-save every 30 seconds
	local timer = vim.loop.new_timer()
	timer:start(
		30000,
		30000,
		vim.schedule_wrap(function()
			M.save_history()
		end)
	)
end

return M
