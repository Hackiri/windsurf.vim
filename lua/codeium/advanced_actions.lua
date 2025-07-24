-- Advanced Lua Actions for windsurf.nvim
-- Leveraging coroutines, metatables, and advanced patterns

local actions = require("codeium.actions")
local notify = require("codeium.notify")
local providers = require("codeium.providers")

local M = {}

-- Advanced Lua pattern analyzer using coroutines
local function analyze_lua_patterns_async(code, callback)
	local co = coroutine.create(function()
		local patterns = {
			metatables = code:match("setmetatable") or code:match("__index") or code:match("__newindex"),
			coroutines = code:match("coroutine%.") or code:match("yield"),
			closures = code:match("local%s+function.*return%s+function") or code:match("function.*function.*end.*end"),
			modules = code:match("local%s+M%s*=%s*{}") or code:match("return%s+M"),
			error_handling = code:match("pcall") or code:match("xpcall") or code:match("assert"),
			performance_patterns = code:match("local%s+[%w_]+%s*=") and not code:match("global"),
		}

		local analysis = {
			complexity_score = 0,
			recommendations = {},
			detected_patterns = {},
		}

		for pattern, found in pairs(patterns) do
			if found then
				analysis.complexity_score = analysis.complexity_score + 1
				table.insert(analysis.detected_patterns, pattern)
			end
		end

		-- Generate recommendations based on missing patterns
		if not patterns.error_handling then
			table.insert(analysis.recommendations, "Add error handling with pcall/xpcall")
		end

		if not patterns.modules and #code > 500 then
			table.insert(analysis.recommendations, "Consider modularizing code with local M = {} pattern")
		end

		if not patterns.performance_patterns then
			table.insert(analysis.recommendations, "Use local variables for better performance")
		end

		coroutine.yield(analysis)
	end)

	vim.schedule(function()
		local success, result = coroutine.resume(co)
		if success then
			callback(result)
		else
			callback(nil, result)
		end
	end)
end

-- Metatable-based action context with enhanced capabilities
local AdvancedActionContext = {}
AdvancedActionContext.__index = AdvancedActionContext

function AdvancedActionContext:new(base_context)
	local instance = setmetatable({}, self)

	-- Copy base context properties
	for k, v in pairs(base_context) do
		instance[k] = v
	end

	-- Add advanced capabilities
	instance.cache = setmetatable({}, { __mode = "v" }) -- Weak table for caching
	instance.history = {}
	instance.performance_metrics = {
		start_time = os.clock(),
		memory_before = collectgarbage("count"),
	}

	return instance
end

function AdvancedActionContext:get_cached_analysis()
	local cache_key = self.filename .. ":" .. vim.fn.getftime(self.filename)
	return self.cache[cache_key]
end

function AdvancedActionContext:set_cached_analysis(analysis)
	local cache_key = self.filename .. ":" .. vim.fn.getftime(self.filename)
	self.cache[cache_key] = analysis
end

function AdvancedActionContext:get_performance_metrics()
	return {
		execution_time = os.clock() - self.performance_metrics.start_time,
		memory_used = collectgarbage("count") - self.performance_metrics.memory_before,
	}
end

-- Metamethod for string representation
function AdvancedActionContext:__tostring()
	return string.format(
		"AdvancedActionContext[%s:%d:%d]",
		vim.fn.fnamemodify(self.filename, ":t"),
		self.cursor_pos[1],
		self.cursor_pos[2]
	)
end

-- Advanced action factory using closures
local function create_advanced_action(name, config)
	-- Create closure with persistent state
	local action_state = {
		execution_count = 0,
		last_execution = nil,
		performance_history = {},
	}

	local enhanced_config = vim.tbl_deep_extend("force", config, {
		transform = function(context)
			-- Enhance context with advanced capabilities
			local advanced_context = AdvancedActionContext:new(context)

			-- Track execution
			action_state.execution_count = action_state.execution_count + 1
			action_state.last_execution = os.time()

			return advanced_context
		end,

		post_process = function(result)
			-- Apply original post-processing if exists
			if config.post_process then
				result = config.post_process(result)
			end

			-- Add performance metrics
			local metrics = {
				timestamp = os.time(),
				execution_count = action_state.execution_count,
				result_length = #result,
			}
			table.insert(action_state.performance_history, metrics)

			-- Keep only last 10 metrics
			if #action_state.performance_history > 10 then
				table.remove(action_state.performance_history, 1)
			end

			return result
		end,
	})

	actions.register_action(name, enhanced_config)

	-- Return state accessor for debugging
	return {
		get_state = function()
			return action_state
		end,
		reset_state = function()
			action_state.execution_count = 0
			action_state.performance_history = {}
		end,
	}
end

-- Register advanced Lua-specific actions
function M.register_advanced_actions()
	-- Coroutine-based async code analyzer
	create_advanced_action("analyze_lua_async", {
		description = "Analyze Lua code patterns asynchronously",
		template = "Analyze this Lua code for advanced patterns and provide recommendations:\n\n```lua\n{code}\n```\n\nFocus on:\n- Metatable usage and opportunities\n- Coroutine patterns\n- Performance optimizations\n- Memory management\n- Error handling patterns\n- Module structure\n\nProvide specific, actionable recommendations.",
		strategy = "display",
		requires_selection = true,
		category = "lua_advanced",
		priority = 5,
		validate = function(context)
			return context.filetype == "lua", "This action requires Lua code"
		end,
		transform = function(context)
			local advanced_context = AdvancedActionContext:new(context)

			-- Check cache first
			local cached = advanced_context:get_cached_analysis()
			if cached then
				notify.info("Using cached analysis")
				advanced_context.metadata.cached_analysis = cached
			else
				-- Perform async analysis
				analyze_lua_patterns_async(context:get_selected_text(), function(analysis, err)
					if analysis then
						advanced_context:set_cached_analysis(analysis)
						advanced_context.metadata.pattern_analysis = analysis
					end
				end)
			end

			return advanced_context
		end,
	})

	-- Metatable enhancement action
	create_advanced_action("enhance_with_metatables", {
		description = "Enhance Lua tables with metatables",
		template = "Enhance this Lua code by adding appropriate metatables and metamethods:\n\n```lua\n{code}\n```\n\nAdd metatables for:\n- Custom indexing behavior (__index)\n- String representation (__tostring)\n- Arithmetic operations (__add, __sub, etc.) if applicable\n- Comparison operations (__eq, __lt) if applicable\n- Custom behavior for table access\n\nProvide the enhanced version with explanations.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 4,
		validate = function(context)
			local code = context:get_selected_text()
			return context.filetype == "lua" and (code:match("local%s+%w+%s*=%s*{}") or code:match("%.new%s*=")),
				"This action works best with table/object definitions"
		end,
	})

	-- Coroutine conversion action
	create_advanced_action("convert_to_coroutines", {
		description = "Convert blocking code to use coroutines",
		template = "Convert this Lua code to use coroutines for better async behavior:\n\n```lua\n{code}\n```\n\nTransform blocking operations into coroutine-based patterns:\n- Use coroutine.create() for task creation\n- Add coroutine.yield() for cooperative yielding\n- Implement proper coroutine.resume() handling\n- Add error handling for coroutine failures\n\nProvide the coroutine-enhanced version.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 4,
		validate = function(context)
			local code = context:get_selected_text()
			return context.filetype == "lua" and not code:match("coroutine%.") and (code:match("function") or code:match(
				"while"
			) or code:match("for")),
				"This action works with functions that could benefit from async behavior"
		end,
	})

	-- Performance optimization with closures
	create_advanced_action("optimize_lua_performance", {
		description = "Optimize Lua code performance using advanced patterns",
		template = "Optimize this Lua code for maximum performance:\n\n```lua\n{code}\n```\n\nApply these optimizations:\n- Convert to local variables where possible\n- Use table pre-allocation\n- Implement memoization with closures\n- Add weak tables for caching\n- Optimize loops and iterations\n- Use table.concat for string building\n- Add tail call optimization where applicable\n\nProvide the optimized version with performance notes.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 5,
		validate = function(context)
			return context.filetype == "lua", "This action requires Lua code"
		end,
		api_params = {
			temperature = 0.3, -- Lower temperature for more consistent optimizations
			max_tokens = 2500,
		},
	})

	-- Advanced error handling patterns
	create_advanced_action("add_advanced_error_handling", {
		description = "Add comprehensive error handling patterns",
		template = "Add advanced error handling to this Lua code:\n\n```lua\n{code}\n```\n\nImplement:\n- pcall/xpcall for protected calls\n- Custom error objects with stack traces\n- Error recovery strategies\n- Logging and notification patterns\n- Input validation\n- Resource cleanup in error cases\n- Graceful degradation\n\nProvide the error-hardened version.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 4,
		validate = function(context)
			local code = context:get_selected_text()
			return context.filetype == "lua" and not code:match("pcall") and not code:match("xpcall"),
				"This action adds error handling to code that doesn't have it"
		end,
	})

	-- Memory management optimization
	create_advanced_action("optimize_memory_management", {
		description = "Optimize Lua memory management",
		template = "Optimize memory management in this Lua code:\n\n```lua\n{code}\n```\n\nApply memory optimizations:\n- Use weak tables (__mode = 'k', 'v', or 'kv') for caches\n- Add explicit cleanup functions\n- Implement object pooling where appropriate\n- Use table.clear() for table reuse\n- Add garbage collection hints\n- Minimize table creation in loops\n- Use string interning for repeated strings\n\nProvide the memory-optimized version.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 4,
		validate = function(context)
			return context.filetype == "lua", "This action requires Lua code"
		end,
	})

	-- Module pattern enhancement
	create_advanced_action("enhance_module_pattern", {
		description = "Enhance Lua module with advanced patterns",
		template = "Enhance this Lua module with advanced patterns:\n\n```lua\n{code}\n```\n\nAdd:\n- Proper module structure with local M = {}\n- Private function scoping\n- Module metadata (__VERSION, __AUTHOR, etc.)\n- Configuration validation\n- Setup/teardown functions\n- Event system if applicable\n- Documentation comments\n- Export control\n\nProvide the enhanced module.",
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 4,
		validate = function(context)
			local code = context:get_selected_text()
			return context.filetype == "lua" and #code > 100,
				"This action works with substantial code that can be modularized"
		end,
	})
end

-- Advanced action picker with fuzzy search
function M.advanced_action_picker()
	local advanced_actions = actions.list_actions("lua_advanced")

	if #advanced_actions == 0 then
		notify.warn("No advanced Lua actions available")
		return
	end

	-- Create enhanced picker with descriptions and metadata
	local picker_items = {}
	for _, action in ipairs(advanced_actions) do
		local item = {
			text = action.name,
			description = action.description,
			action = action,
		}
		table.insert(picker_items, item)
	end

	-- Use telescope if available, otherwise fallback to vim.ui.select
	local ok_telescope, telescope = pcall(require, "telescope")
	if ok_telescope then
		-- Enhanced telescope picker (would need telescope extension)
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local telescope_actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		pickers
			.new({}, {
				prompt_title = "Advanced Lua Actions",
				finder = finders.new_table({
					results = picker_items,
					entry_maker = function(entry)
						return {
							value = entry,
							display = entry.text .. " - " .. entry.description,
							ordinal = entry.text .. " " .. entry.description,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					telescope_actions.select_default:replace(function()
						telescope_actions.close(prompt_bufnr)
						local selection = action_state.get_selected_entry()
						actions.execute_action(selection.value.action.name)
					end)
					return true
				end,
			})
			:find()
	else
		-- Fallback to vim.ui.select
		local display_items = {}
		for _, item in ipairs(picker_items) do
			table.insert(display_items, item.text .. " - " .. item.description)
		end

		vim.ui.select(display_items, {
			prompt = "Select advanced Lua action:",
		}, function(choice, idx)
			if choice and idx then
				actions.execute_action(picker_items[idx].action.name)
			end
		end)
	end
end

-- Performance monitoring for actions
function M.get_action_performance_stats()
	local stats = {}
	-- This would integrate with the action state from closures
	-- Implementation would depend on accessing the closure state
	return stats
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Register all advanced actions
	M.register_advanced_actions()

	-- Register commands
	vim.api.nvim_create_user_command("WindsurfAdvancedActions", function()
		M.advanced_action_picker()
	end, {
		desc = "Open advanced Lua actions picker",
	})

	vim.api.nvim_create_user_command("WindsurfActionStats", function()
		local stats = M.get_action_performance_stats()
		print(vim.inspect(stats))
	end, {
		desc = "Show action performance statistics",
	})

	-- Register keybinding
	vim.keymap.set("n", "<leader>aL", function()
		M.advanced_action_picker()
	end, { desc = "Advanced Lua Actions" })

	notify.info("Advanced Lua actions loaded successfully")
end

return M
