local M = {}

function M.setup(options)
	local Source = require("codeium.source")
	local Server = require("codeium.api")
	local update = require("codeium.update")
	local health = require("codeium.health")
	local sidebar = require("codeium.views.sidebar")
	local providers = require("codeium.providers")
	local history = require("codeium.history")
	local web_search = require("codeium.web_search")
	local rag = require("codeium.rag")
	local tools = require("codeium.tools")
	require("codeium.config").setup(options)

	M.s = Server.new()
	update.download(function(err)
		if not err then
			Server.load_api_key()
			M.s:start()
			-- Connect sidebar to server
			sidebar.set_server(M.s)
		end
	end)
	health.register(M.s)
	
	-- Initialize all advanced systems
	providers.setup()
	history.setup()
	web_search.setup(options.web_search or {})
	rag.setup(options.rag_service or {})
	tools.setup(options.tools or {})
	sidebar.setup()
	
	-- Setup key bindings
	M.setup_keymaps()

	vim.api.nvim_create_user_command("Codeium", function(opts)
		local args = opts.fargs
		if args[1] == "Auth" then
			Server.authenticate()
		end
		if args[1] == "Chat" then
			M.chat()
		end
		if args[1] == "Toggle" then
			M.toggle()
		end
	end, {
		nargs = 1,
		complete = function()
			local commands = { "Auth", "Toggle" }
			if require("codeium.config").options.enable_chat then
				commands = vim.list_extend(commands, { "Chat" })
			end
			return commands
		end,
	})

	-- Add new avante-style commands
	vim.api.nvim_create_user_command("WindsurfAsk", function(opts)
		local message = table.concat(opts.fargs, " ")
		if message == "" then
			vim.ui.input({ prompt = "Ask Windsurf AI: " }, function(input)
				if input and input ~= "" then
					M.ask(input)
				end
			end)
		else
			M.ask(message)
		end
	end, {
		nargs = "*",
		desc = "Ask Windsurf AI about your code",
	})

	vim.api.nvim_create_user_command("WindsurfChat", function()
		sidebar.open()
		sidebar.focus_input()
	end, {
		desc = "Open Windsurf AI chat sidebar",
	})

	vim.api.nvim_create_user_command("WindsurfToggle", function()
		sidebar.toggle()
	end, {
		desc = "Toggle Windsurf AI sidebar",
	})

	vim.api.nvim_create_user_command("WindsurfFocus", function()
		if sidebar.get_state().is_open then
			sidebar.focus_input()
		else
			sidebar.open()
			sidebar.focus_input()
		end
	end, {
		desc = "Focus Windsurf AI input",
	})

	vim.api.nvim_create_user_command("WindsurfApply", function()
		sidebar.apply_code_smart()
	end, {
		desc = "Apply AI code suggestion using smart diff",
	})

	-- Advanced provider and session management commands
	vim.api.nvim_create_user_command("WindsurfProvider", function(opts)
		local provider_name = opts.args
		if provider_name == "" then
			providers.show_provider_menu()
		else
			providers.switch_provider(provider_name)
		end
	end, {
		nargs = "?",
		desc = "Switch AI provider or show provider menu",
		complete = function()
			local available_providers = providers.get_available_providers()
			local names = {}
			for _, provider in ipairs(available_providers) do
				table.insert(names, provider.name)
			end
			return names
		end,
	})

	vim.api.nvim_create_user_command("WindsurfHistory", function()
		history.show_session_menu()
	end, {
		desc = "Show chat session history",
	})

	vim.api.nvim_create_user_command("WindsurfClear", function()
		history.clear_current_session()
	end, {
		desc = "Clear current chat session",
	})

	vim.api.nvim_create_user_command("WindsurfEdit", function()
		local session = history.get_current_session()
		if session.pending_code_blocks and #session.pending_code_blocks > 0 then
			local diff_module = require("codeium.diff")
			-- Get the last AI response for interactive editing
			local last_response = ""
			if #session.messages > 0 then
				for i = #session.messages, 1, -1 do
					if session.messages[i].role == "assistant" then
						last_response = session.messages[i].content
						break
					end
				end
			end
			
			local context = {
				current_file = vim.api.nvim_buf_get_name(0),
				cursor_line = vim.api.nvim_win_get_cursor(0)[1],
			}
			
			diff_module.apply_with_confirmation(last_response, context)
		else
			notify.warn("No code suggestions available to edit")
		end
	end, {
		desc = "Edit and apply code suggestions interactively",
	})

	-- Advanced RAG and Web Search commands
	vim.api.nvim_create_user_command("WindsurfWebSearch", function(opts)
		local query = opts.args
		if query == "" then
			vim.ui.input({ prompt = "Web search query: " }, function(input)
				if input and input ~= "" then
					web_search.search_and_format(input, function(results, err)
						if err then
							notify.error("Web search failed: " .. err)
						else
							-- Display results in sidebar or new buffer
							local buf = vim.api.nvim_create_buf(false, true)
							vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(results, "\n"))
							vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
							vim.api.nvim_win_set_buf(0, buf)
						end
					end)
				end
			end)
		else
			web_search.search_and_format(query, function(results, err)
				if err then
					notify.error("Web search failed: " .. err)
				else
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(results, "\n"))
					vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
					vim.api.nvim_win_set_buf(0, buf)
				end
			end)
		end
	end, {
		nargs = "?",
		desc = "Perform web search and display results",
	})

	vim.api.nvim_create_user_command("WindsurfRAG", function()
		rag.show_service_menu()
	end, {
		desc = "Manage RAG service",
	})

	vim.api.nvim_create_user_command("WindsurfTools", function()
		tools.show_tools_menu()
	end, {
		desc = "Show available tools",
	})

	vim.api.nvim_create_user_command("WindsurfWebProvider", function()
		web_search.show_provider_menu()
	end, {
		desc = "Switch web search provider",
	})

	local source = Source:new(M.s)
	if require("codeium.config").options.enable_cmp_source then
		require("cmp").register_source("codeium", source)
	end

	require("codeium.virtual_text").setup(M.s)
end

--- Open Codeium Chat
function M.chat()
	M.s:refresh_context()
	M.s:get_chat_ports()
	M.s:add_workspace()
end

--- Toggle the Codeium plugin
function M.toggle()
	M.s:toggle()
end

function M.enable()
	M.s:enable()
end

function M.disable()
	M.s:disable()
end

--- Ask Windsurf AI a question
function M.ask(message)
	local sidebar = require("codeium.views.sidebar")
	sidebar.open()
	-- Add the message directly and process it
	sidebar.add_message("user", message)
	sidebar.process_user_message(message)
end

--- Setup key bindings
function M.setup_keymaps()
	local opts = { noremap = true, silent = true }
	
	-- Leader key mappings (similar to avante.nvim)
	vim.keymap.set("n", "<leader>aa", function()
		require("codeium.views.sidebar").open()
	end, vim.tbl_extend("force", opts, { desc = "Show Windsurf AI sidebar" }))
	
	vim.keymap.set("n", "<leader>at", function()
		require("codeium.views.sidebar").toggle()
	end, vim.tbl_extend("force", opts, { desc = "Toggle Windsurf AI sidebar" }))
	
	vim.keymap.set("n", "<leader>af", function()
		local sidebar = require("codeium.views.sidebar")
		if sidebar.get_state().is_open then
			sidebar.focus_input()
		else
			sidebar.open()
			sidebar.focus_input()
		end
	end, vim.tbl_extend("force", opts, { desc = "Focus Windsurf AI input" }))
	
	vim.keymap.set("n", "<leader>an", function()
		vim.ui.input({ prompt = "Ask Windsurf AI: " }, function(input)
			if input and input ~= "" then
				M.ask(input)
			end
		end)
	end, vim.tbl_extend("force", opts, { desc = "New ask" }))
	
	vim.keymap.set("n", "<leader>ac", function()
		require("codeium.views.sidebar").add_file()
	end, vim.tbl_extend("force", opts, { desc = "Add current buffer to context" }))
	
	-- Advanced features
	vim.keymap.set("n", "<leader>ap", function()
		require("codeium.providers").show_provider_menu()
	end, vim.tbl_extend("force", opts, { desc = "Switch AI provider" }))
	
	vim.keymap.set("n", "<leader>ah", function()
		require("codeium.history").show_session_menu()
	end, vim.tbl_extend("force", opts, { desc = "Show session history" }))
	
	vim.keymap.set("n", "<leader>ae", function()
		vim.cmd("WindsurfEdit")
	end, vim.tbl_extend("force", opts, { desc = "Edit code suggestions" }))
	
	vim.keymap.set("n", "<leader>ar", function()
		require("codeium.views.sidebar").retry_last()
	end, vim.tbl_extend("force", opts, { desc = "Retry last message" }))
	
	vim.keymap.set("n", "<leader>aS", function()
		-- Stop current AI request (placeholder for now)
		notify.info("Stop AI request (not implemented yet)")
	end, vim.tbl_extend("force", opts, { desc = "Stop AI request" }))
	
	-- Advanced RAG, Web Search, and Tools features
	vim.keymap.set("n", "<leader>aw", function()
		vim.ui.input({ prompt = "Web search: " }, function(query)
			if query and query ~= "" then
				vim.cmd("WindsurfWebSearch " .. query)
			end
		end)
	end, vim.tbl_extend("force", opts, { desc = "Web search" }))
	
	vim.keymap.set("n", "<leader>aR", function()
		vim.cmd("WindsurfRAG")
	end, vim.tbl_extend("force", opts, { desc = "RAG service menu" }))
	
	vim.keymap.set("n", "<leader>aT", function()
		vim.cmd("WindsurfTools")
	end, vim.tbl_extend("force", opts, { desc = "Tools menu" }))
	
	vim.keymap.set("n", "<leader>aW", function()
		vim.cmd("WindsurfWebProvider")
	end, vim.tbl_extend("force", opts, { desc = "Web search provider" }))
	
	-- Enhanced suggestion handling
	vim.keymap.set("n", "<M-l>", function()
		require("codeium.views.sidebar").apply_code_smart()
	end, vim.tbl_extend("force", opts, { desc = "Accept AI suggestion (smart)" }))
	
	vim.keymap.set("n", "<M-]>", function()
		-- Next suggestion (placeholder)
		notify.info("Next suggestion (not implemented yet)")
	end, vim.tbl_extend("force", opts, { desc = "Next suggestion" }))
	
	vim.keymap.set("n", "<M-[>", function()
		-- Previous suggestion (placeholder)
		notify.info("Previous suggestion (not implemented yet)")
	end, vim.tbl_extend("force", opts, { desc = "Previous suggestion" }))
	
	vim.keymap.set("n", "<C-]>", function()
		-- Dismiss suggestion (placeholder)
		notify.info("Dismiss suggestion (not implemented yet)")
	end, vim.tbl_extend("force", opts, { desc = "Dismiss suggestion" }))
end

return M
