local api = vim.api
local config = require("codeium.config")
local diff = require("codeium.diff")
local history = require("codeium.history")
local notify = require("codeium.notify")
local providers = require("codeium.providers")
local util = require("codeium.util")

local M = {}

-- Sidebar state
local sidebar_state = {
	bufnr = nil,
	winid = nil,
	is_open = false,
	width = 50,
	position = "right", -- "left" or "right"
	input_bufnr = nil,
	input_winid = nil,
}

-- Get current session from history system
local function get_current_session()
	return history.get_current_session()
end

-- Format message for display
local function format_message(message)
	local lines = {}
	local timestamp = os.date("%H:%M", message.timestamp or os.time())

	-- Add message header
	table.insert(lines, string.format("┌─ %s [%s]", message.role:upper(), timestamp))

	-- Add message content
	local content_lines = vim.split(message.content, "\n")
	for _, line in ipairs(content_lines) do
		table.insert(lines, "│ " .. line)
	end

	-- Add message footer
	table.insert(lines, "└─")
	table.insert(lines, "")

	return lines
end

-- Update sidebar content
local function update_sidebar_content()
	if not sidebar_state.bufnr or not api.nvim_buf_is_valid(sidebar_state.bufnr) then
		return
	end

	local session = get_current_session()
	local current_provider = providers.get_current_provider()
	local lines = {}

	-- Add header with provider info
	table.insert(lines, "╭─ Windsurf AI Chat ─╮")
	table.insert(lines, "│ Provider: " .. current_provider.name .. string.rep(" ", 9 - #current_provider.name) .. "│")
	table.insert(
		lines,
		"│ Session: "
			.. (session.title:sub(1, 10) or "Chat")
			.. string.rep(" ", 10 - #(session.title:sub(1, 10) or "Chat"))
			.. "│"
	)
	table.insert(lines, "│                    │")

	-- Add context files if any
	if #session.context_files > 0 then
		table.insert(lines, "│ Context Files:     │")
		for _, file in ipairs(session.context_files) do
			local filename = vim.fn.fnamemodify(file, ":t")
			table.insert(lines, "│ • " .. filename .. string.rep(" ", 15 - #filename) .. "│")
		end
		table.insert(lines, "│                    │")
	end

	table.insert(lines, "╰────────────────────╯")
	table.insert(lines, "")

	-- Add messages
	for _, message in ipairs(session.messages) do
		local formatted = format_message(message)
		for _, line in ipairs(formatted) do
			table.insert(lines, line)
		end
	end

	-- Add input prompt
	table.insert(lines, "")
	table.insert(lines, "┌─ Your Message ─────")
	table.insert(lines, "│")
	table.insert(lines, "│ Type your message below...")
	table.insert(lines, "│ Commands: @file @codebase @diagnostics")
	table.insert(lines, "│ Keys: 'p' provider, 'h' history, 'a' apply")
	table.insert(lines, "│")
	table.insert(lines, "└───────────────────")

	-- Set buffer content
	api.nvim_buf_set_option(sidebar_state.bufnr, "modifiable", true)
	api.nvim_buf_set_lines(sidebar_state.bufnr, 0, -1, false, lines)
	api.nvim_buf_set_option(sidebar_state.bufnr, "modifiable", false)
end

-- Create sidebar buffer
local function create_sidebar_buffer()
	local bufnr = api.nvim_create_buf(false, true)

	-- Set buffer options
	api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	api.nvim_buf_set_option(bufnr, "swapfile", false)
	api.nvim_buf_set_option(bufnr, "filetype", "windsurf-sidebar")
	api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
	api.nvim_buf_set_name(bufnr, "Windsurf AI")

	return bufnr
end

-- Create input buffer
local function create_input_buffer()
	local bufnr = api.nvim_create_buf(false, true)

	-- Set buffer options
	api.nvim_buf_set_option(bufnr, "buftype", "")
	api.nvim_buf_set_option(bufnr, "swapfile", false)
	api.nvim_buf_set_option(bufnr, "filetype", "markdown")
	api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
	api.nvim_buf_set_name(bufnr, "Windsurf Input")

	return bufnr
end

-- Setup sidebar keymaps
local function setup_sidebar_keymaps(bufnr)
	local opts = { noremap = true, silent = true }

	-- Navigation
	api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>lua require('codeium.views.sidebar').close()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "<Tab>", "<cmd>lua require('codeium.views.sidebar').focus_input()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "r", "<cmd>lua require('codeium.views.sidebar').retry_last()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "e", "<cmd>lua require('codeium.views.sidebar').edit_last()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "@", "<cmd>lua require('codeium.views.sidebar').add_file()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "d", "<cmd>lua require('codeium.views.sidebar').remove_file()<cr>", opts)

	-- Code application (enhanced)
	api.nvim_buf_set_keymap(bufnr, "n", "a", "<cmd>lua require('codeium.views.sidebar').apply_code_smart()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "A", "<cmd>lua require('codeium.views.sidebar').apply_all_code_smart()<cr>", opts)

	-- Provider and history management
	api.nvim_buf_set_keymap(bufnr, "n", "p", "<cmd>lua require('codeium.providers').show_provider_menu()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "h", "<cmd>lua require('codeium.history').show_session_menu()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "H", "<cmd>lua require('codeium.views.sidebar').clear_session()<cr>", opts)

	-- Session navigation
	api.nvim_buf_set_keymap(bufnr, "n", "]p", "<cmd>lua require('codeium.views.sidebar').next_session()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "[p", "<cmd>lua require('codeium.views.sidebar').prev_session()<cr>", opts)
end

-- Setup input keymaps
local function setup_input_keymaps(bufnr)
	local opts = { noremap = true, silent = true }

	-- Send message
	api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "<cmd>lua require('codeium.views.sidebar').send_message()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "i", "<C-CR>", "<cmd>lua require('codeium.views.sidebar').send_message()<cr>", opts)

	-- Navigation
	api.nvim_buf_set_keymap(bufnr, "n", "<Tab>", "<cmd>lua require('codeium.views.sidebar').focus_sidebar()<cr>", opts)
	api.nvim_buf_set_keymap(bufnr, "n", "<S-Tab>", "<cmd>lua require('codeium.views.sidebar').focus_sidebar()<cr>", opts)
end

-- Open sidebar
function M.open()
	if sidebar_state.is_open then
		return
	end

	-- Create buffers
	sidebar_state.bufnr = create_sidebar_buffer()
	sidebar_state.input_bufnr = create_input_buffer()

	-- Calculate window dimensions
	local width = math.min(sidebar_state.width, math.floor(vim.o.columns * 0.4))
	local height = vim.o.lines - 2
	local input_height = 5
	local sidebar_height = height - input_height - 1

	-- Calculate window position
	local col = sidebar_state.position == "right" and (vim.o.columns - width) or 0

	-- Create sidebar window
	sidebar_state.winid = api.nvim_open_win(sidebar_state.bufnr, false, {
		relative = "editor",
		width = width,
		height = sidebar_height,
		col = col,
		row = 0,
		style = "minimal",
		border = "rounded",
		title = " Windsurf AI ",
		title_pos = "center",
	})

	-- Create input window
	sidebar_state.input_winid = api.nvim_open_win(sidebar_state.input_bufnr, true, {
		relative = "editor",
		width = width,
		height = input_height,
		col = col,
		row = sidebar_height + 1,
		style = "minimal",
		border = "rounded",
		title = " Message ",
		title_pos = "left",
	})

	-- Set window options
	api.nvim_win_set_option(sidebar_state.winid, "wrap", true)
	api.nvim_win_set_option(sidebar_state.winid, "cursorline", false)
	api.nvim_win_set_option(sidebar_state.input_winid, "wrap", true)

	-- Setup keymaps
	setup_sidebar_keymaps(sidebar_state.bufnr)
	setup_input_keymaps(sidebar_state.input_bufnr)

	sidebar_state.is_open = true
	update_sidebar_content()
end

-- Close sidebar
function M.close()
	if not sidebar_state.is_open then
		return
	end

	if sidebar_state.winid and api.nvim_win_is_valid(sidebar_state.winid) then
		api.nvim_win_close(sidebar_state.winid, true)
	end

	if sidebar_state.input_winid and api.nvim_win_is_valid(sidebar_state.input_winid) then
		api.nvim_win_close(sidebar_state.input_winid, true)
	end

	sidebar_state.is_open = false
	sidebar_state.winid = nil
	sidebar_state.input_winid = nil
end

-- Toggle sidebar
function M.toggle()
	if sidebar_state.is_open then
		M.close()
	else
		M.open()
	end
end

-- Focus input window
function M.focus_input()
	if sidebar_state.input_winid and api.nvim_win_is_valid(sidebar_state.input_winid) then
		api.nvim_set_current_win(sidebar_state.input_winid)
		vim.cmd("startinsert")
	end
end

-- Focus sidebar window
function M.focus_sidebar()
	if sidebar_state.winid and api.nvim_win_is_valid(sidebar_state.winid) then
		api.nvim_set_current_win(sidebar_state.winid)
	end
end

-- Add message to current session
function M.add_message(role, content, metadata)
	history.add_message(role, content, metadata)
	update_sidebar_content()
end

-- Send message
function M.send_message()
	if not sidebar_state.input_bufnr or not api.nvim_buf_is_valid(sidebar_state.input_bufnr) then
		return
	end

	local lines = api.nvim_buf_get_lines(sidebar_state.input_bufnr, 0, -1, false)
	local content = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")

	if content == "" then
		notify.warn("Please enter a message")
		return
	end

	-- Add user message
	M.add_message("user", content)

	-- Clear input
	api.nvim_buf_set_lines(sidebar_state.input_bufnr, 0, -1, false, {})

	-- Process message (this will be connected to the AI API)
	M.process_user_message(content)
end

-- Process user message with AI integration
function M.process_user_message(content)
	local context = require("codeium.context")
	local current_provider = providers.get_current_provider()

	-- Add thinking indicator
	M.add_message("assistant", "🤔 Thinking...")

	-- Parse context from message and get relevant information
	local message_context, mentions = context.process_message_context(content)

	-- If no explicit mentions, get smart context
	if #message_context == 0 then
		message_context = context.get_smart_context(content)
	end

	-- Format context for AI prompt
	local formatted_context = context.format_context_for_prompt(message_context)
	local full_message = formatted_context .. "\n\nUser Request: " .. content

	-- Get conversation history from history system
	local conversation_history = history.get_messages_for_context(5)

	-- Prepare messages for AI
	local messages = vim.list_extend(conversation_history, {
		{ role = "user", content = full_message },
	})

	-- Send to appropriate provider
	if current_provider.name == "Windsurf" and M.server and M.server.send_chat_message then
		-- Use windsurf server
		M.server:send_chat_message(full_message, {
			mentions = mentions,
			context = message_context,
			history = conversation_history,
			files = history.get_current_session().context_files,
		}, M.handle_ai_response)
	else
		-- Use external provider
		providers.make_external_request(providers.current_provider, messages, M.handle_ai_response)
	end
end

-- Handle AI response
function M.handle_ai_response(response, err)
	-- Remove thinking indicator
	local session = get_current_session()
	if #session.messages > 0 and session.messages[#session.messages].content:match("🤔 Thinking") then
		table.remove(session.messages)
		history.save_history()
	end

	if err then
		M.add_message("assistant", "❌ Error: " .. (err.message or "Failed to get AI response"))
		notify.error("AI request failed", err.message or "Unknown error")
		return
	end

	local ai_response = ""
	
	-- Debug: Print response structure to help identify the correct format
	if response then
		print("[DEBUG] Response type:", type(response))
		print("[DEBUG] Response keys:", vim.inspect(vim.tbl_keys(response)))
		if type(response) == "table" then
			print("[DEBUG] Full response:", vim.inspect(response))
		end
	end
	
	-- Try multiple possible response formats
	if response and response.completionItems and #response.completionItems > 0 then
		-- Standard completion format
		ai_response = response.completionItems[1].completion.text
	elseif response and response.completion and response.completion.text then
		-- Alternative completion format
		ai_response = response.completion.text
	elseif response and response.text then
		-- Direct text format
		ai_response = response.text
	elseif response and response.content then
		-- Content format
		ai_response = response.content
	elseif response and response.message then
		-- Message format
		ai_response = response.message
	elseif response and type(response) == "string" then
		-- String response
		ai_response = response
	else
		-- Fallback with more detailed error info
		ai_response = "I received your message but couldn't parse the response format. Response type: " .. type(response or "nil")
		if response and type(response) == "table" then
			ai_response = ai_response .. ". Available keys: " .. table.concat(vim.tbl_keys(response), ", ")
		end
	end

	-- Clean up debug response for user display
	if ai_response:match("Response type:") then
		ai_response = "Debug info printed to console. Please check :messages for response format details."
	end
	
	M.add_message("assistant", ai_response)

	-- Check if response contains code suggestions and store them
	if ai_response:match("```") then
		M.store_code_suggestions(ai_response)
	end
end

-- Store code suggestions for later application
function M.store_code_suggestions(response)
	local code_blocks = diff.parse_code_blocks(response)

	if #code_blocks > 0 then
		notify.info(string.format("Found %d code suggestion(s). Use 'a' to apply smart or 'A' to apply all.", #code_blocks))

		-- Store code blocks in session
		local session = get_current_session()
		session.pending_code_blocks = code_blocks
		history.save_history()
	end
end

-- Apply code suggestions using smart diff system
function M.apply_code_smart()
	local session = get_current_session()
	if not session.pending_code_blocks or #session.pending_code_blocks == 0 then
		notify.warn("No code suggestions to apply")
		return
	end

	-- Get context for smart application
	local context = {
		current_file = api.nvim_buf_get_name(0),
		cursor_line = api.nvim_win_get_cursor(0)[1],
	}

	-- Use the advanced diff system for smart application
	if #session.pending_code_blocks == 1 then
		diff.apply_code_block(session.pending_code_blocks[1], {
			mode = diff.DIFF_MODES.SMART_MERGE,
			context = context,
			show_diff = true,
		})
	else
		diff.apply_multiple_blocks(session.pending_code_blocks, {
			mode = diff.DIFF_MODES.SMART_MERGE,
			context = context,
		})
	end

	-- Clear pending blocks
	session.pending_code_blocks = nil
	history.save_history()
end

-- Apply all code suggestions with confirmation
function M.apply_all_code_smart()
	local session = get_current_session()
	if not session.pending_code_blocks or #session.pending_code_blocks == 0 then
		notify.warn("No code suggestions to apply")
		return
	end

	-- Get the last AI response for interactive application
	local last_response = ""
	if #session.messages > 0 then
		for i = #session.messages, 1, -1 do
			if session.messages[i].role == "assistant" then
				last_response = session.messages[i].content
				break
			end
		end
	end

	-- Use interactive application with confirmation
	local context = {
		current_file = api.nvim_buf_get_name(0),
		cursor_line = api.nvim_win_get_cursor(0)[1],
	}

	diff.apply_with_confirmation(last_response, context)

	-- Clear pending blocks
	session.pending_code_blocks = nil
	history.save_history()
end

-- Set server reference for API calls
function M.set_server(server)
	M.server = server
end

-- Add file to context
function M.add_file()
	local current_file = api.nvim_buf_get_name(0)
	if current_file and current_file ~= "" then
		local session = get_current_session()
		if not vim.tbl_contains(session.context_files, current_file) then
			table.insert(session.context_files, current_file)
			history.update_context_files(session.context_files)
			update_sidebar_content()
			notify.info("Added " .. vim.fn.fnamemodify(current_file, ":t") .. " to context")
		else
			notify.warn("File already in context")
		end
	else
		notify.warn("No file to add")
	end
end

-- Remove file from context
function M.remove_file()
	local session = get_current_session()
	if #session.context_files > 0 then
		table.remove(session.context_files)
		history.update_context_files(session.context_files)
		update_sidebar_content()
		notify.info("Removed file from context")
	else
		notify.warn("No files in context")
	end
end

-- Session navigation functions
function M.next_session()
	local sessions = history.get_all_sessions()
	if #sessions <= 1 then
		notify.info("No other sessions available")
		return
	end

	local current_id = history.get_current_session().id
	local current_idx = nil

	for i, session in ipairs(sessions) do
		if session.id == current_id then
			current_idx = i
			break
		end
	end

	if current_idx and current_idx < #sessions then
		local next_session = sessions[current_idx + 1]
		history.switch_session(next_session.id)
		notify.info("Switched to: " .. next_session.title)
		update_sidebar_content()
	else
		notify.info("Already at the last session")
	end
end

function M.prev_session()
	local sessions = history.get_all_sessions()
	if #sessions <= 1 then
		notify.info("No other sessions available")
		return
	end

	local current_id = history.get_current_session().id
	local current_idx = nil

	for i, session in ipairs(sessions) do
		if session.id == current_id then
			current_idx = i
			break
		end
	end

	if current_idx and current_idx > 1 then
		local prev_session = sessions[current_idx - 1]
		history.switch_session(prev_session.id)
		notify.info("Switched to: " .. prev_session.title)
		update_sidebar_content()
	else
		notify.info("Already at the first session")
	end
end

function M.clear_session()
	vim.ui.input({ prompt = "Clear current session? (y/N): " }, function(input)
		if input and input:lower() == "y" then
			history.clear_current_session()
			update_sidebar_content()
		end
	end)
end

function M.retry_last()
	local session = get_current_session()
	if #session.messages == 0 then
		notify.warn("No messages to retry")
		return
	end

	-- Find last user message
	local last_user_message = nil
	for i = #session.messages, 1, -1 do
		if session.messages[i].role == "user" then
			last_user_message = session.messages[i].content
			break
		end
	end

	if last_user_message then
		M.process_user_message(last_user_message)
	else
		notify.warn("No user message found to retry")
	end
end

function M.edit_last()
	local session = get_current_session()
	if #session.messages == 0 then
		notify.warn("No messages to edit")
		return
	end

	-- Find last user message
	local last_user_message = nil
	for i = #session.messages, 1, -1 do
		if session.messages[i].role == "user" then
			last_user_message = session.messages[i].content
			break
		end
	end

	if last_user_message then
		vim.ui.input({ prompt = "Edit message: ", default = last_user_message }, function(input)
			if input and input ~= "" then
				M.process_user_message(input)
			end
		end)
	else
		notify.warn("No user message found to edit")
	end
end

-- Get sidebar state (for external access)
function M.get_state()
	return sidebar_state
end

-- Initialize sidebar
function M.setup()
	-- Create highlight groups
	vim.cmd([[
    highlight default WindsurfSidebarBorder guifg=#3c3836
    highlight default WindsurfSidebarTitle guifg=#83a598 gui=bold
    highlight default WindsurfUserMessage guifg=#b8bb26
    highlight default WindsurfAssistantMessage guifg=#83a598
  ]])
end

return M
