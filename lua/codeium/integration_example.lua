-- Integration Example: Advanced Lua Action System for windsurf.nvim
-- Demonstrates sophisticated patterns and real-world usage

local action_loader = require("codeium.action_loader")
local actions = require("codeium.actions")
local advanced_actions = require("codeium.advanced_actions")

local M = {}

-- Example: Custom AI-powered Lua refactoring workflow
local function create_lua_refactoring_workflow()
	-- Multi-step workflow using coroutines
	local workflow_state = {
		steps = {},
		current_step = 1,
		context = nil,
	}

	-- Step 1: Analyze code patterns
	local function analyze_step(context)
		return coroutine.create(function()
			local analysis_prompt = string.format(
				[[
Analyze this Lua code for refactoring opportunities:

```lua
%s
```

Provide a JSON response with:
{
  "complexity_score": 1-10,
  "issues": ["list of issues"],
  "recommendations": ["list of recommendations"],
  "refactoring_priority": "low|medium|high"
}
]],
				context:get_selected_text()
			)

			local response = actions.get_action("analyze_lua_async"):execute(context)
			coroutine.yield({
				step = "analysis",
				result = response,
				next_step = "optimize",
			})
		end)
	end

	-- Step 2: Apply optimizations
	local function optimize_step(context, analysis)
		return coroutine.create(function()
			if analysis.refactoring_priority == "high" then
				local optimize_result = actions.get_action("optimize_lua_performance"):execute(context)
				coroutine.yield({
					step = "optimization",
					result = optimize_result,
					next_step = "finalize",
				})
			else
				coroutine.yield({
					step = "optimization",
					result = "No optimization needed",
					next_step = "finalize",
				})
			end
		end)
	end

	-- Workflow executor
	local function execute_workflow(context)
		local co = coroutine.create(function()
			-- Step 1: Analysis
			local analysis_co = analyze_step(context)
			local _, analysis_result = coroutine.resume(analysis_co)

			-- Step 2: Optimization (if needed)
			local optimize_co = optimize_step(context, analysis_result)
			local _, optimize_result = coroutine.resume(optimize_co)

			-- Final result
			coroutine.yield({
				workflow_complete = true,
				analysis = analysis_result,
				optimization = optimize_result,
				execution_time = os.clock() - workflow_state.start_time,
			})
		end)

		workflow_state.start_time = os.clock()
		return co
	end

	return execute_workflow
end

-- Example: Metatable-based Action Registry with inheritance
local ActionRegistry = {}
ActionRegistry.__index = ActionRegistry

function ActionRegistry:new()
	local instance = {
		actions = {},
		categories = {},
		execution_history = {},
		performance_cache = setmetatable({}, { __mode = "v" }), -- Weak table
	}
	return setmetatable(instance, self)
end

function ActionRegistry:register(name, config)
	-- Enhanced registration with metadata
	local action_meta = {
		name = name,
		config = config,
		registered_at = os.time(),
		execution_count = 0,
		average_execution_time = 0,
		last_execution = nil,
	}

	self.actions[name] = action_meta

	-- Category tracking
	local category = config.category or "general"
	if not self.categories[category] then
		self.categories[category] = {}
	end
	table.insert(self.categories[category], name)

	-- Register with main action system
	actions.register_action(name, config)
end

function ActionRegistry:execute_with_metrics(name, context)
	local action_meta = self.actions[name]
	if not action_meta then
		error("Action not found: " .. name)
	end

	local start_time = os.clock()
	local result = actions.execute_action(name, context)
	local execution_time = os.clock() - start_time

	-- Update metrics
	action_meta.execution_count = action_meta.execution_count + 1
	action_meta.last_execution = os.time()

	-- Calculate rolling average
	local old_avg = action_meta.average_execution_time
	local count = action_meta.execution_count
	action_meta.average_execution_time = ((old_avg * (count - 1)) + execution_time) / count

	-- Store in history
	table.insert(self.execution_history, {
		action = name,
		timestamp = os.time(),
		execution_time = execution_time,
		context_info = {
			filetype = context.filetype,
			filename = vim.fn.fnamemodify(context.filename, ":t"),
		},
	})

	-- Trim history to last 100 executions
	if #self.execution_history > 100 then
		table.remove(self.execution_history, 1)
	end

	return result
end

function ActionRegistry:get_performance_report()
	local report = {
		total_actions = vim.tbl_count(self.actions),
		total_executions = #self.execution_history,
		categories = {},
		top_performers = {},
		slowest_actions = {},
	}

	-- Category statistics
	for category, action_names in pairs(self.categories) do
		local category_stats = {
			count = #action_names,
			total_executions = 0,
			average_time = 0,
		}

		local total_time = 0
		for _, name in ipairs(action_names) do
			local action_meta = self.actions[name]
			category_stats.total_executions = category_stats.total_executions + action_meta.execution_count
			total_time = total_time + (action_meta.average_execution_time * action_meta.execution_count)
		end

		if category_stats.total_executions > 0 then
			category_stats.average_time = total_time / category_stats.total_executions
		end

		report.categories[category] = category_stats
	end

	-- Top performers (fastest average execution time)
	local sorted_actions = {}
	for name, meta in pairs(self.actions) do
		if meta.execution_count > 0 then
			table.insert(sorted_actions, { name = name, avg_time = meta.average_execution_time })
		end
	end

	table.sort(sorted_actions, function(a, b)
		return a.avg_time < b.avg_time
	end)
	report.top_performers = vim.list_slice(sorted_actions, 1, 5)

	table.sort(sorted_actions, function(a, b)
		return a.avg_time > b.avg_time
	end)
	report.slowest_actions = vim.list_slice(sorted_actions, 1, 5)

	return report
end

-- Metamethod for string representation
function ActionRegistry:__tostring()
	return string.format(
		"ActionRegistry[%d actions, %d executions]",
		vim.tbl_count(self.actions),
		#self.execution_history
	)
end

-- Example: Closure-based action factory with persistent state
local function create_stateful_action_factory()
	-- Persistent state across action creations
	local factory_state = {
		created_actions = 0,
		action_templates = {},
		global_config = {},
	}

	-- Return factory function (closure)
	return function(template_name, custom_config)
		factory_state.created_actions = factory_state.created_actions + 1

		local action_id = "generated_" .. factory_state.created_actions
		local base_template = factory_state.action_templates[template_name] or {}

		local final_config = vim.tbl_deep_extend("force", base_template, factory_state.global_config, custom_config or {})

		-- Add factory metadata
		final_config.metadata = final_config.metadata or {}
		final_config.metadata.factory_generated = true
		final_config.metadata.generation_time = os.time()
		final_config.metadata.factory_id = factory_state.created_actions

		return action_id, final_config
	end,
	-- Return state accessor
	function()
		return factory_state
	end
end

-- Example: Advanced error handling with custom error objects
local LuaActionError = {}
LuaActionError.__index = LuaActionError

function LuaActionError:new(message, context, error_type)
	local instance = {
		message = message,
		context = context,
		error_type = error_type or "general",
		timestamp = os.time(),
		stack_trace = debug.traceback(),
	}
	return setmetatable(instance, self)
end

function LuaActionError:__tostring()
	return string.format("[%s] %s (at %s)", self.error_type, self.message, os.date("%H:%M:%S", self.timestamp))
end

-- Safe action executor with comprehensive error handling
local function safe_execute_action(action_name, context, options)
	options = options or {}

	local function execute_with_recovery()
		local success, result = pcall(function()
			return actions.execute_action(action_name, context)
		end)

		if success then
			return result, nil
		else
			-- Create detailed error object
			local error_obj = LuaActionError:new(result, context, "execution_error")

			-- Attempt recovery if specified
			if options.recovery_action then
				local recovery_success, recovery_result = pcall(function()
					return actions.execute_action(options.recovery_action, context)
				end)

				if recovery_success then
					return recovery_result, error_obj -- Return both result and original error
				end
			end

			return nil, error_obj
		end
	end

	-- Retry logic
	local max_retries = options.max_retries or 1
	local retry_delay = options.retry_delay or 0

	for attempt = 1, max_retries do
		local result, error_obj = execute_with_recovery()

		if result then
			return result, error_obj -- May include recovered error info
		end

		if attempt < max_retries then
			if retry_delay > 0 then
				vim.defer_fn(function() end, retry_delay * 1000)
			end
		else
			return nil, error_obj
		end
	end
end

-- Integration setup function
function M.setup_advanced_integration()
	-- Create global action registry
	local registry = ActionRegistry:new()

	-- Create action factory
	local action_factory, get_factory_state = create_stateful_action_factory()

	-- Register some example actions using advanced patterns
	registry:register("lua_metatable_wizard", {
		description = "Advanced metatable implementation wizard",
		template = [[
Transform this Lua code into a sophisticated object-oriented structure using metatables:

```lua
{code}
```

Create:
1. Proper constructor with validation
2. Metamethods for common operations (__tostring, __eq, __add if applicable)
3. Private method access control
4. Inheritance support if beneficial
5. Method chaining where appropriate
6. Documentation comments

Provide the complete metatable-enhanced version.
]],
		strategy = "replace",
		requires_selection = true,
		category = "lua_advanced",
		priority = 5,
		validate = function(context)
			return context.filetype == "lua" and context:get_selected_text():match("function") and not context
				:get_selected_text()
				:match("setmetatable"),
				"Select Lua code with functions that could benefit from metatable enhancement"
		end,
	})

	-- Create workflow action
	local refactoring_workflow = create_lua_refactoring_workflow()

	registry:register("lua_refactoring_workflow", {
		description = "Complete Lua refactoring workflow",
		template = "Internal workflow action", -- Not used directly
		strategy = "display",
		requires_selection = true,
		category = "workflow",
		priority = 5,
		validate = function(context)
			return context.filetype == "lua", "Lua refactoring workflow requires Lua code"
		end,
		transform = function(context)
			-- Execute the workflow
			local workflow_co = refactoring_workflow(context)
			local _, result = coroutine.resume(workflow_co)

			context.metadata.workflow_result = result
			return context
		end,
	})

	-- Register commands with advanced features
	vim.api.nvim_create_user_command("WindsurfRegistryStats", function()
		local report = registry:get_performance_report()

		-- Create formatted display
		local lines = {
			"=== Action Registry Performance Report ===",
			"",
			string.format("Total Actions: %d", report.total_actions),
			string.format("Total Executions: %d", report.total_executions),
			"",
			"=== Category Statistics ===",
		}

		for category, stats in pairs(report.categories) do
			table.insert(
				lines,
				string.format(
					"%s: %d actions, %d executions, %.3fs avg",
					category,
					stats.count,
					stats.total_executions,
					stats.average_time
				)
			)
		end

		table.insert(lines, "")
		table.insert(lines, "=== Top Performers ===")
		for i, action in ipairs(report.top_performers) do
			table.insert(lines, string.format("%d. %s (%.3fs)", i, action.name, action.avg_time))
		end

		-- Display in new buffer
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(bufnr, "filetype", "text")
		vim.api.nvim_open_win(bufnr, true, {
			relative = "editor",
			width = 80,
			height = 20,
			col = 10,
			row = 5,
			style = "minimal",
			border = "rounded",
			title = " Registry Performance Report ",
			title_pos = "center",
		})
	end, {
		desc = "Show action registry performance statistics",
	})

	vim.api.nvim_create_user_command("WindsurfSafeExecute", function(opts)
		local action_name = opts.fargs[1]
		if not action_name then
			vim.notify("Usage: :WindsurfSafeExecute <action_name>", vim.log.levels.ERROR)
			return
		end

		local context = require("codeium.actions").ActionContext:new({})
		local result, error_obj = safe_execute_action(action_name, context, {
			max_retries = 2,
			retry_delay = 1,
			recovery_action = "explain_code", -- Fallback action
		})

		if result then
			vim.notify("Action executed successfully", vim.log.levels.INFO)
			if error_obj then
				vim.notify("Note: Recovered from error: " .. tostring(error_obj), vim.log.levels.WARN)
			end
		else
			vim.notify("Action failed: " .. tostring(error_obj), vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		complete = function()
			return vim.tbl_keys(actions.list_actions())
		end,
		desc = "Execute action with advanced error handling",
	})

	-- Store registry globally for access
	_G.windsurf_action_registry = registry

	return registry
end

return M
