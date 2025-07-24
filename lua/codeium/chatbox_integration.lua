-- Chatbox Integration for windsurf.nvim
-- Bridges browser-based Windsurf AI chat with advanced Action System

local actions = require("codeium.actions")
local advanced_actions = require("codeium.advanced_actions")
local history = require("codeium.history")
local notify = require("codeium.notify")
local providers = require("codeium.providers")
local sidebar = require("codeium.views.sidebar")

local M = {}

-- Enhanced chatbox state management
local chatbox_state = {
	active_mode = "sidebar", -- "sidebar" or "browser"
	action_suggestions = {},
	context_awareness = {
		current_file = nil,
		selected_text = nil,
		cursor_position = nil,
		project_context = {},
	},
	browser_integration = {
		last_url = nil,
		sync_enabled = false,
	},
}

-- Context-aware action suggestions based on current code
local function get_contextual_action_suggestions(context)
	local suggestions = {}

	if context.filetype == "lua" then
		table.insert(suggestions, {
			action = "analyze_lua_async",
			reason = "Lua code detected - analyze patterns and performance",
			priority = 5,
		})

		if context.selected_text and context.selected_text:match("function") then
			table.insert(suggestions, {
				action = "enhance_with_metatables",
				reason = "Function detected - consider metatable enhancement",
				priority = 4,
			})
		end

		if context.selected_text and not context.selected_text:match("pcall") then
			table.insert(suggestions, {
				action = "add_advanced_error_handling",
				reason = "Missing error handling detected",
				priority = 4,
			})
		end
	end

	-- General suggestions based on selection
	if context.selected_text then
		table.insert(suggestions, {
			action = "explain_code",
			reason = "Code selected - get explanation",
			priority = 3,
		})

		table.insert(suggestions, {
			action = "optimize_code",
			reason = "Code selected - optimize performance",
			priority = 3,
		})

		table.insert(suggestions, {
			action = "generate_tests",
			reason = "Code selected - generate tests",
			priority = 3,
		})
	end

	-- Sort by priority
	table.sort(suggestions, function(a, b)
		return a.priority > b.priority
	end)

	return suggestions
end

-- Enhanced context gathering for chatbox
local function gather_enhanced_context()
	local context = {
		bufnr = vim.api.nvim_get_current_buf(),
		winid = vim.api.nvim_get_current_win(),
		cursor_pos = vim.api.nvim_win_get_cursor(0),
		filetype = vim.bo.filetype,
		filename = vim.api.nvim_buf_get_name(0),
		workspace_root = vim.fn.getcwd(),
	}

	-- Get selected text if in visual mode
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is Ctrl-V
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		local lines = vim.api.nvim_buf_get_lines(context.bufnr, start_pos[2] - 1, end_pos[2], false)
		context.selected_text = table.concat(lines, "\n")
		context.range = {
			start = { line = start_pos[2] - 1, col = start_pos[3] - 1 },
			["end"] = { line = end_pos[2] - 1, col = end_pos[3] - 1 },
		}
	end

	-- Get surrounding context (5 lines before and after cursor)
	local current_line = context.cursor_pos[1] - 1
	local start_line = math.max(0, current_line - 5)
	local end_line = math.min(vim.api.nvim_buf_line_count(context.bufnr) - 1, current_line + 5)
	local surrounding_lines = vim.api.nvim_buf_get_lines(context.bufnr, start_line, end_line + 1, false)
	context.surrounding_context = table.concat(surrounding_lines, "\n")

	-- Get project context
	context.project_files = vim.fn.glob(context.workspace_root .. "/**/*.lua", false, true)
	context.git_info = {
		branch = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("\n", ""),
		status = vim.fn.system("git status --porcelain 2>/dev/null"):gsub("\n", " "),
	}

	return context
end

-- Enhanced chatbox interface with action integration
function M.enhanced_chat_interface()
	local context = gather_enhanced_context()
	local suggestions = get_contextual_action_suggestions(context)

	-- Update global state
	chatbox_state.context_awareness = context
	chatbox_state.action_suggestions = suggestions

	-- Create enhanced chat prompt with context and suggestions
	local chat_options = {
		"🌐 Open Browser Chat (Full Windsurf AI)",
		"💬 Use Sidebar Chat (Quick Questions)",
		"⚡ Quick Actions Menu",
		"🎯 Context-Aware Actions",
		"📊 Action Performance Stats",
	}

	vim.ui.select(chat_options, {
		prompt = "Windsurf AI Chat Options:",
		format_item = function(item)
			return item
		end,
	}, function(choice, idx)
		if not choice then
			return
		end

		if idx == 1 then
			M.open_browser_chat_enhanced()
		elseif idx == 2 then
			M.open_sidebar_chat_enhanced()
		elseif idx == 3 then
			M.show_quick_actions_menu()
		elseif idx == 4 then
			M.show_contextual_actions()
		elseif idx == 5 then
			M.show_action_stats()
		end
	end)
end

-- Enhanced browser chat with pre-populated context
function M.open_browser_chat_enhanced()
	local context = chatbox_state.context_awareness

	-- Prepare context summary for browser chat
	local context_summary = {
		"=== Windsurf AI Context ===",
		"File: " .. vim.fn.fnamemodify(context.filename, ":t"),
		"Type: " .. context.filetype,
		"Line: " .. context.cursor_pos[1],
	}

	if context.selected_text then
		table.insert(context_summary, "Selected: " .. #context.selected_text .. " characters")
	end

	if #chatbox_state.action_suggestions > 0 then
		table.insert(context_summary, "")
		table.insert(context_summary, "Suggested Actions:")
		for i, suggestion in ipairs(vim.list_slice(chatbox_state.action_suggestions, 1, 3)) do
			table.insert(context_summary, string.format("%d. %s - %s", i, suggestion.action, suggestion.reason))
		end
	end

	-- Copy context to clipboard for easy pasting in browser
	local context_text = table.concat(context_summary, "\n")
	vim.fn.setreg("+", context_text)

	notify.info("Context copied to clipboard! Paste in browser chat.")

	-- Open browser chat
	local init = require("codeium.init")
	init.chat()

	-- Store browser state
	chatbox_state.active_mode = "browser"
	chatbox_state.browser_integration.last_url = "browser_opened"
end

-- Enhanced sidebar chat with action integration
function M.open_sidebar_chat_enhanced()
	local context = chatbox_state.context_awareness

	-- Open sidebar
	sidebar.open()

	-- Add context information to chat
	local context_message =
		string.format("Context: %s (line %d)", vim.fn.fnamemodify(context.filename, ":t"), context.cursor_pos[1])

	if context.selected_text then
		context_message = context_message .. string.format(" | Selected: %d chars", #context.selected_text)
	end

	sidebar.add_message("system", context_message)

	-- Show action suggestions in sidebar
	if #chatbox_state.action_suggestions > 0 then
		local suggestions_text = "💡 Suggested actions:\n"
		for i, suggestion in ipairs(vim.list_slice(chatbox_state.action_suggestions, 1, 3)) do
			suggestions_text = suggestions_text .. string.format("• %s - %s\n", suggestion.action, suggestion.reason)
		end
		sidebar.add_message("system", suggestions_text)
	end

	chatbox_state.active_mode = "sidebar"
	sidebar.focus_input()
end

-- Quick actions menu with immediate execution
function M.show_quick_actions_menu()
	local quick_actions = {
		{ name = "explain_code", desc = "Explain selected code", icon = "📖" },
		{ name = "optimize_code", desc = "Optimize for performance", icon = "⚡" },
		{ name = "add_comments", desc = "Add detailed comments", icon = "💬" },
		{ name = "generate_tests", desc = "Generate unit tests", icon = "🧪" },
		{ name = "fix_bugs", desc = "Find and fix bugs", icon = "🐛" },
		{ name = "refactor_code", desc = "Refactor structure", icon = "🔧" },
	}

	local display_items = {}
	for _, action in ipairs(quick_actions) do
		table.insert(display_items, action.icon .. " " .. action.desc)
	end

	vim.ui.select(display_items, {
		prompt = "Quick Actions:",
	}, function(choice, idx)
		if choice and idx then
			local action = quick_actions[idx]
			local context = gather_enhanced_context()

			if not context.selected_text and actions.get_action(action.name).requires_selection then
				notify.warn("This action requires text selection")
				return
			end

			notify.info("Executing: " .. action.desc)
			actions.execute_action(action.name, context)
		end
	end)
end

-- Context-aware actions based on current code
function M.show_contextual_actions()
	local suggestions = chatbox_state.action_suggestions

	if #suggestions == 0 then
		notify.info("No contextual actions available for current code")
		return
	end

	local display_items = {}
	for _, suggestion in ipairs(suggestions) do
		table.insert(
			display_items,
			string.format("⭐ %s - %s (Priority: %d)", suggestion.action, suggestion.reason, suggestion.priority)
		)
	end

	vim.ui.select(display_items, {
		prompt = "Context-Aware Actions:",
	}, function(choice, idx)
		if choice and idx then
			local suggestion = suggestions[idx]
			local context = gather_enhanced_context()

			notify.info("Executing contextual action: " .. suggestion.action)
			actions.execute_action(suggestion.action, context)
		end
	end)
end

-- Action performance statistics
function M.show_action_stats()
	-- This would integrate with the performance monitoring from our advanced system
	local stats_lines = {
		"=== Windsurf Action Statistics ===",
		"",
		"Active Mode: " .. chatbox_state.active_mode,
		"Current File: " .. vim.fn.fnamemodify(chatbox_state.context_awareness.filename or "", ":t"),
		"Available Actions: " .. #chatbox_state.action_suggestions,
		"",
		"Recent Suggestions:",
	}

	for i, suggestion in ipairs(vim.list_slice(chatbox_state.action_suggestions, 1, 5)) do
		table.insert(stats_lines, string.format("%d. %s (Priority: %d)", i, suggestion.action, suggestion.priority))
	end

	-- Display in floating window
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, stats_lines)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "text")

	local width = 60
	local height = #stats_lines + 2
	vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "rounded",
		title = " Action Statistics ",
		title_pos = "center",
	})
end

-- Smart chat mode switcher
function M.smart_chat_switch()
	local context = gather_enhanced_context()

	-- Decide best chat mode based on context
	local use_browser = false

	-- Use browser for complex tasks
	if context.selected_text and #context.selected_text > 1000 then
		use_browser = true
	end

	-- Use browser for multi-file projects
	if context.project_files and #context.project_files > 10 then
		use_browser = true
	end

	-- Use browser for complex Lua patterns
	if context.filetype == "lua" and context.selected_text then
		local complexity_indicators = {
			"setmetatable",
			"coroutine",
			"__index",
			"__newindex",
			"pcall",
			"xpcall",
			"require.*require",
		}

		for _, indicator in ipairs(complexity_indicators) do
			if context.selected_text:match(indicator) then
				use_browser = true
				break
			end
		end
	end

	if use_browser then
		notify.info("Complex context detected - opening browser chat")
		M.open_browser_chat_enhanced()
	else
		notify.info("Simple context - using sidebar chat")
		M.open_sidebar_chat_enhanced()
	end
end

-- Integration with existing windsurf functions
function M.enhance_existing_chat_functions()
	local init = require("codeium.init")

	-- Store original functions
	local original_chat = init.chat
	local original_ask = init.ask

	-- Enhanced chat function
	init.chat = function()
		local context = gather_enhanced_context()
		chatbox_state.context_awareness = context
		chatbox_state.action_suggestions = get_contextual_action_suggestions(context)

		-- Show enhanced interface first
		M.enhanced_chat_interface()
	end

	-- Enhanced ask function
	init.ask = function(message)
		local context = gather_enhanced_context()
		chatbox_state.context_awareness = context
		chatbox_state.action_suggestions = get_contextual_action_suggestions(context)

		-- Add contextual information to the message
		local enhanced_message = message
		if context.selected_text then
			enhanced_message = string.format(
				"%s\n\nContext: %s (line %d)\nSelected code:\n```%s\n%s\n```",
				message,
				vim.fn.fnamemodify(context.filename, ":t"),
				context.cursor_pos[1],
				context.filetype,
				context.selected_text
			)
		end

		original_ask(enhanced_message)
	end
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Enhance existing chat functions
	if opts.enhance_existing ~= false then
		M.enhance_existing_chat_functions()
	end

	-- Register new commands
	vim.api.nvim_create_user_command("WindsurfChatEnhanced", function()
		M.enhanced_chat_interface()
	end, {
		desc = "Open enhanced Windsurf AI chat interface",
	})

	vim.api.nvim_create_user_command("WindsurfSmartChat", function()
		M.smart_chat_switch()
	end, {
		desc = "Smart chat mode selection based on context",
	})

	vim.api.nvim_create_user_command("WindsurfQuickActions", function()
		M.show_quick_actions_menu()
	end, {
		desc = "Show quick actions menu",
	})

	vim.api.nvim_create_user_command("WindsurfContextActions", function()
		M.show_contextual_actions()
	end, {
		desc = "Show context-aware actions",
	})

	-- Enhanced keybindings
	vim.keymap.set("n", "<leader>aC", function()
		M.enhanced_chat_interface()
	end, { desc = "Enhanced Chat Interface" })

	vim.keymap.set("n", "<leader>aS", function()
		M.smart_chat_switch()
	end, { desc = "Smart Chat Mode" })

	vim.keymap.set("n", "<leader>aQ", function()
		M.show_quick_actions_menu()
	end, { desc = "Quick Actions" })

	vim.keymap.set("n", "<leader>aX", function()
		M.show_contextual_actions()
	end, { desc = "Context Actions" })

	-- Auto-update context on cursor move (throttled)
	local update_timer = nil
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		callback = function()
			if update_timer then
				update_timer:stop()
			end

			update_timer = vim.defer_fn(function()
				local context = gather_enhanced_context()
				chatbox_state.context_awareness = context
				chatbox_state.action_suggestions = get_contextual_action_suggestions(context)
			end, 500) -- Update every 500ms
		end,
	})

	notify.info("Windsurf chatbox integration enhanced successfully!")
end

return M
