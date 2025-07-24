local config = require("codeium.config")
local notify = require("codeium.notify")
local providers = require("codeium.providers")
local util = require("codeium.util")

local M = {}

-- Action execution strategies
local strategies = {
    replace = function(content, result)
        return result
    end,
    
    append = function(content, result)
        return content .. "\n" .. result
    end,
    
    prepend = function(content, result)
        return result .. "\n" .. content
    end,
    
    edit = function(content, result)
        -- Integration with diff system for smart edits
        local diff = require("codeium.diff")
        return diff.apply_edit(content, result)
    end,
    
    display = function(content, result)
        -- Display result in a new buffer/window
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
        vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
        vim.api.nvim_open_win(bufnr, true, {
            relative = "editor",
            width = math.floor(vim.o.columns * 0.8),
            height = math.floor(vim.o.lines * 0.8),
            col = math.floor(vim.o.columns * 0.1),
            row = math.floor(vim.o.lines * 0.1),
            style = "minimal",
            border = "rounded",
            title = " AI Result ",
            title_pos = "center"
        })
        return content -- Original content unchanged
    end,
    
    insert_below = function(content, result)
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local lines = vim.split(result, "\n")
        vim.api.nvim_buf_set_lines(0, cursor_pos[1], cursor_pos[1], false, lines)
        return content
    end
}

-- Action registry
local actions = {}

-- Action execution context
local ActionContext = {}
ActionContext.__index = ActionContext

function ActionContext:new(opts)
    local instance = {
        bufnr = opts.bufnr or vim.api.nvim_get_current_buf(),
        winid = opts.winid or vim.api.nvim_get_current_win(),
        range = opts.range,
        selected_text = opts.selected_text,
        cursor_pos = opts.cursor_pos or vim.api.nvim_win_get_cursor(0),
        filetype = opts.filetype or vim.bo.filetype,
        filename = opts.filename or vim.api.nvim_buf_get_name(0),
        workspace_root = opts.workspace_root or vim.fn.getcwd(),
        metadata = opts.metadata or {}
    }
    return setmetatable(instance, ActionContext)
end

function ActionContext:get_buffer_content()
    return table.concat(vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false), "\n")
end

function ActionContext:get_selected_text()
    if self.selected_text then
        return self.selected_text
    end
    
    if self.range then
        local lines = vim.api.nvim_buf_get_lines(
            self.bufnr, 
            self.range.start.line, 
            self.range["end"].line + 1, 
            false
        )
        return table.concat(lines, "\n")
    end
    
    return ""
end

function ActionContext:get_surrounding_context(lines_before, lines_after)
    lines_before = lines_before or 5
    lines_after = lines_after or 5
    
    local current_line = self.cursor_pos[1] - 1 -- Convert to 0-based
    local start_line = math.max(0, current_line - lines_before)
    local end_line = math.min(
        vim.api.nvim_buf_line_count(self.bufnr) - 1,
        current_line + lines_after
    )
    
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, start_line, end_line + 1, false)
    return table.concat(lines, "\n")
end

-- Action definition structure
local Action = {}
Action.__index = Action

function Action:new(config)
    local instance = {
        name = config.name,
        description = config.description or "",
        template = config.template,
        strategy = config.strategy or "replace",
        mode = config.mode or "chat", -- chat, completion, edit
        validate = config.validate or function() return true end,
        transform = config.transform or function(ctx) return ctx end,
        post_process = config.post_process or function(result) return result end,
        requires_selection = config.requires_selection or false,
        supports_range = config.supports_range or false,
        category = config.category or "general",
        priority = config.priority or 1,
        keybind = config.keybind,
        api_params = config.api_params or {}
    }
    return setmetatable(instance, Action)
end

function Action:can_execute(context)
    local valid, reason = self.validate(context)
    if not valid then
        return false, reason
    end
    
    if self.requires_selection and not context:get_selected_text() then
        return false, "This action requires text selection"
    end
    
    return true, nil
end

function Action:execute(context)
    -- Validate execution
    local can_exec, reason = self:can_execute(context)
    if not can_exec then
        return nil, reason
    end
    
    -- Transform context
    local transformed_context = self.transform(context)
    
    -- Build prompt from template
    local prompt = self:build_prompt(transformed_context)
    
    -- Execute AI request based on mode
    local success, result = self:execute_ai_request(prompt, transformed_context)
    if not success then
        return nil, result
    end
    
    -- Post-process result
    result = self.post_process(result)
    
    -- Apply strategy
    local strategy_func = strategies[self.strategy]
    if not strategy_func then
        return nil, "Unknown strategy: " .. self.strategy
    end
    
    local final_result = strategy_func(transformed_context:get_selected_text(), result)
    
    return final_result, nil
end

function Action:build_prompt(context)
    local template = self.template
    local replacements = {
        code = context:get_selected_text(),
        buffer = context:get_buffer_content(),
        filetype = context.filetype,
        filename = vim.fn.fnamemodify(context.filename, ":t"),
        surrounding = context:get_surrounding_context(),
        cursor_line = context.cursor_pos[1],
        workspace = context.workspace_root
    }
    
    -- Add metadata replacements
    for key, value in pairs(context.metadata) do
        replacements[key] = value
    end
    
    -- Replace template variables
    for key, value in pairs(replacements) do
        template = template:gsub("{" .. key .. "}", tostring(value))
    end
    
    return template
end

function Action:execute_ai_request(prompt, context)
    local messages = {{role = "user", content = prompt}}
    
    if self.mode == "chat" then
        return pcall(function()
            local response = providers.chat_completion(messages, self.api_params)
            return response.content or response.text or ""
        end)
    elseif self.mode == "completion" then
        return pcall(function()
            local response = providers.completion(prompt, self.api_params)
            return response.text or ""
        end)
    else
        return false, "Unknown mode: " .. self.mode
    end
end

-- Action System Manager
function M.register_action(name, config)
    config.name = name
    actions[name] = Action:new(config)
    
    -- Register keybinding if specified
    if config.keybind then
        vim.keymap.set("n", config.keybind, function()
            M.execute_action(name)
        end, { desc = config.description or name })
    end
end

function M.execute_action(name, opts)
    opts = opts or {}
    
    local action = actions[name]
    if not action then
        notify.error("Unknown action: " .. name)
        return
    end
    
    -- Create execution context
    local context = ActionContext:new(opts)
    
    -- Execute action
    local result, err = action:execute(context)
    if err then
        notify.error("Action failed: " .. err)
        return
    end
    
    notify.info("Action '" .. name .. "' completed successfully")
    return result
end

function M.get_action(name)
    return actions[name]
end

function M.list_actions(category)
    local action_list = {}
    for name, action in pairs(actions) do
        if not category or action.category == category then
            table.insert(action_list, {
                name = name,
                description = action.description,
                category = action.category,
                requires_selection = action.requires_selection
            })
        end
    end
    
    -- Sort by priority and name
    table.sort(action_list, function(a, b)
        local action_a = actions[a.name]
        local action_b = actions[b.name]
        if action_a.priority ~= action_b.priority then
            return action_a.priority > action_b.priority
        end
        return a.name < b.name
    end)
    
    return action_list
end

function M.get_categories()
    local categories = {}
    for _, action in pairs(actions) do
        categories[action.category] = true
    end
    return vim.tbl_keys(categories)
end

-- Action picker using vim.ui.select
function M.pick_action(category)
    local action_list = M.list_actions(category)
    
    if #action_list == 0 then
        notify.warn("No actions available" .. (category and " in category: " .. category or ""))
        return
    end
    
    local display_items = {}
    for _, action in ipairs(action_list) do
        local display = action.name
        if action.description then
            display = display .. " - " .. action.description
        end
        if action.requires_selection then
            display = display .. " (requires selection)"
        end
        table.insert(display_items, display)
    end
    
    vim.ui.select(display_items, {
        prompt = "Select action:",
        format_item = function(item) return item end
    }, function(choice, idx)
        if choice and idx then
            M.execute_action(action_list[idx].name)
        end
    end)
end

-- Load default actions
function M.load_default_actions()
    -- Code explanation action
    M.register_action("explain_code", {
        description = "Explain selected code",
        template = "Explain this {filetype} code in detail:\n\n```{filetype}\n{code}\n```\n\nProvide a clear explanation of what this code does, how it works, and any important details.",
        strategy = "display",
        requires_selection = true,
        category = "analysis",
        priority = 5,
        keybind = "<leader>ae"
    })
    
    -- Code optimization action
    M.register_action("optimize_code", {
        description = "Optimize selected code for performance",
        template = "Optimize this {filetype} code for better performance and readability:\n\n```{filetype}\n{code}\n```\n\nProvide the optimized version with explanations of the improvements made.",
        strategy = "replace",
        requires_selection = true,
        category = "refactor",
        priority = 4
    })
    
    -- Add comments action
    M.register_action("add_comments", {
        description = "Add detailed comments to code",
        template = "Add comprehensive comments to this {filetype} code:\n\n```{filetype}\n{code}\n```\n\nAdd inline comments explaining the logic and purpose of each section.",
        strategy = "replace",
        requires_selection = true,
        category = "documentation",
        priority = 3
    })
    
    -- Generate tests action
    M.register_action("generate_tests", {
        description = "Generate unit tests for code",
        template = "Generate comprehensive unit tests for this {filetype} code:\n\n```{filetype}\n{code}\n```\n\nCreate tests that cover normal cases, edge cases, and error conditions. Use appropriate testing framework for {filetype}.",
        strategy = "insert_below",
        requires_selection = true,
        category = "testing",
        priority = 4
    })
    
    -- Fix bugs action
    M.register_action("fix_bugs", {
        description = "Identify and fix potential bugs",
        template = "Analyze this {filetype} code for potential bugs and fix them:\n\n```{filetype}\n{code}\n```\n\nIdentify any issues and provide the corrected version with explanations.",
        strategy = "replace",
        requires_selection = true,
        category = "debugging",
        priority = 5
    })
    
    -- Refactor action
    M.register_action("refactor_code", {
        description = "Refactor code for better structure",
        template = "Refactor this {filetype} code to improve its structure, readability, and maintainability:\n\n```{filetype}\n{code}\n```\n\nApply best practices and design patterns where appropriate.",
        strategy = "replace",
        requires_selection = true,
        category = "refactor",
        priority = 4
    })
    
    -- Documentation action
    M.register_action("generate_docs", {
        description = "Generate documentation for code",
        template = "Generate comprehensive documentation for this {filetype} code:\n\n```{filetype}\n{code}\n```\n\nInclude function/class descriptions, parameter explanations, return values, and usage examples.",
        strategy = "prepend",
        requires_selection = true,
        category = "documentation",
        priority = 3
    })
    
    -- Code review action
    M.register_action("code_review", {
        description = "Perform a code review",
        template = "Perform a thorough code review of this {filetype} code:\n\n```{filetype}\n{code}\n```\n\nProvide feedback on:\n- Code quality and style\n- Potential improvements\n- Security considerations\n- Performance issues\n- Best practices",
        strategy = "display",
        requires_selection = true,
        category = "analysis",
        priority = 4
    })
end

-- Setup function
function M.setup(opts)
    opts = opts or {}
    
    -- Load default actions unless disabled
    if opts.load_defaults ~= false then
        M.load_default_actions()
    end
    
    -- Load custom actions from config
    if opts.custom_actions then
        for name, config in pairs(opts.custom_actions) do
            M.register_action(name, config)
        end
    end
    
    -- Register commands
    vim.api.nvim_create_user_command("WindsurfAction", function(cmd_opts)
        local args = cmd_opts.fargs
        if #args == 0 then
            M.pick_action()
        elseif #args == 1 then
            if actions[args[1]] then
                M.execute_action(args[1])
            else
                -- Try as category
                M.pick_action(args[1])
            end
        else
            notify.error("Usage: :WindsurfAction [action_name|category]")
        end
    end, {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local completions = {}
            
            -- Add action names
            for name in pairs(actions) do
                if name:find(arglead, 1, true) == 1 then
                    table.insert(completions, name)
                end
            end
            
            -- Add categories
            for _, category in ipairs(M.get_categories()) do
                if category:find(arglead, 1, true) == 1 then
                    table.insert(completions, category)
                end
            end
            
            return completions
        end,
        desc = "Execute or select Windsurf actions"
    })
    
    -- Register global keybinding for action picker
    vim.keymap.set("n", "<leader>aa", function()
        M.pick_action()
    end, { desc = "Windsurf Action Picker" })
    
    -- Register category-specific keybindings
    vim.keymap.set("n", "<leader>ar", function()
        M.pick_action("refactor")
    end, { desc = "Refactor Actions" })
    
    vim.keymap.set("n", "<leader>ad", function()
        M.pick_action("documentation")
    end, { desc = "Documentation Actions" })
    
    vim.keymap.set("n", "<leader>at", function()
        M.pick_action("testing")
    end, { desc = "Testing Actions" })
end

return M
