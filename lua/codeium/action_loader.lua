local actions = require("codeium.actions")
local notify = require("codeium.notify")
local util = require("codeium.util")

local M = {}

-- Default action definitions directory
local default_actions_dir = vim.fn.stdpath("config") .. "/windsurf/actions"

-- Load actions from JSON file
function M.load_actions_from_file(filepath)
    if vim.fn.filereadable(filepath) == 0 then
        return false, "File not readable: " .. filepath
    end
    
    local content = vim.fn.readfile(filepath)
    if #content == 0 then
        return false, "Empty file: " .. filepath
    end
    
    local success, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if not success then
        return false, "Invalid JSON in file: " .. filepath
    end
    
    -- Validate and load actions
    local loaded_count = 0
    for name, config in pairs(data.actions or {}) do
        local valid, err = M.validate_action_config(config)
        if valid then
            actions.register_action(name, config)
            loaded_count = loaded_count + 1
        else
            notify.warn(string.format("Invalid action '%s' in %s: %s", name, filepath, err))
        end
    end
    
    return true, string.format("Loaded %d actions from %s", loaded_count, filepath)
end

-- Load all actions from a directory
function M.load_actions_from_directory(directory)
    if vim.fn.isdirectory(directory) == 0 then
        return false, "Directory not found: " .. directory
    end
    
    local files = vim.fn.glob(directory .. "/*.json", false, true)
    local total_loaded = 0
    local errors = {}
    
    for _, file in ipairs(files) do
        local success, result = M.load_actions_from_file(file)
        if success then
            local count = result:match("Loaded (%d+)")
            total_loaded = total_loaded + (tonumber(count) or 0)
        else
            table.insert(errors, result)
        end
    end
    
    if #errors > 0 then
        for _, error in ipairs(errors) do
            notify.warn(error)
        end
    end
    
    return true, string.format("Loaded %d total actions from %s", total_loaded, directory)
end

-- Validate action configuration
function M.validate_action_config(config)
    if type(config) ~= "table" then
        return false, "Action config must be a table"
    end
    
    if not config.template or type(config.template) ~= "string" then
        return false, "Action must have a template string"
    end
    
    if config.strategy and not vim.tbl_contains(
        {"replace", "append", "prepend", "edit", "display", "insert_below"}, 
        config.strategy
    ) then
        return false, "Invalid strategy: " .. config.strategy
    end
    
    if config.mode and not vim.tbl_contains({"chat", "completion", "edit"}, config.mode) then
        return false, "Invalid mode: " .. config.mode
    end
    
    if config.validate and type(config.validate) ~= "string" then
        return false, "Validate function must be a string (Lua code)"
    end
    
    return true, nil
end

-- Create example action files
function M.create_example_actions()
    local actions_dir = default_actions_dir
    
    -- Ensure directory exists
    if vim.fn.isdirectory(actions_dir) == 0 then
        vim.fn.mkdir(actions_dir, "p")
    end
    
    -- Lua-specific actions
    local lua_actions = {
        actions = {
            optimize_lua_performance = {
                description = "Optimize Lua code for performance",
                template = "Optimize this Lua code for better performance, focusing on:\n- Local variable usage\n- Table operations\n- Memory management\n- Algorithm efficiency\n\n```lua\n{code}\n```\n\nProvide the optimized version with detailed explanations.",
                strategy = "replace",
                requires_selection = true,
                category = "lua",
                priority = 5,
                validate = "return context.filetype == 'lua'",
                api_params = {
                    temperature = 0.3,
                    max_tokens = 2000
                }
            },
            
            add_lua_error_handling = {
                description = "Add comprehensive error handling to Lua code",
                template = "Add robust error handling to this Lua code using pcall/xpcall patterns:\n\n```lua\n{code}\n```\n\nInclude proper error messages and recovery strategies.",
                strategy = "replace",
                requires_selection = true,
                category = "lua",
                priority = 4,
                validate = "return context.filetype == 'lua'"
            },
            
            create_lua_module = {
                description = "Convert code to proper Lua module",
                template = "Convert this Lua code into a proper module following best practices:\n\n```lua\n{code}\n```\n\nUse local M = {} pattern, proper scoping, and module documentation.",
                strategy = "replace",
                requires_selection = true,
                category = "lua",
                priority = 4,
                validate = "return context.filetype == 'lua'"
            }
        }
    }
    
    -- Neovim-specific actions
    local nvim_actions = {
        actions = {
            create_nvim_command = {
                description = "Create Neovim user command",
                template = "Create a Neovim user command for this functionality:\n\n```lua\n{code}\n```\n\nInclude proper command definition with completion, validation, and documentation.",
                strategy = "insert_below",
                requires_selection = true,
                category = "neovim",
                priority = 4,
                validate = "return context.filetype == 'lua' and context.filename:match('nvim') or context.filename:match('%.lua$')"
            },
            
            add_nvim_keymaps = {
                description = "Add Neovim keymaps for functionality",
                template = "Create appropriate Neovim keymaps for this functionality:\n\n```lua\n{code}\n```\n\nUse vim.keymap.set with proper descriptions and modes.",
                strategy = "insert_below",
                requires_selection = true,
                category = "neovim",
                priority = 3,
                validate = "return context.filetype == 'lua'"
            },
            
            create_nvim_autocmd = {
                description = "Create Neovim autocommands",
                template = "Create appropriate Neovim autocommands for this functionality:\n\n```lua\n{code}\n```\n\nUse vim.api.nvim_create_autocmd with proper events and patterns.",
                strategy = "insert_below",
                requires_selection = true,
                category = "neovim",
                priority = 3,
                validate = "return context.filetype == 'lua'"
            }
        }
    }
    
    -- Git/Version control actions
    local git_actions = {
        actions = {
            generate_commit_message = {
                description = "Generate commit message from diff",
                template = "Generate a conventional commit message for these changes:\n\n{code}\n\nFollow conventional commits format (feat:, fix:, docs:, etc.) and be descriptive but concise.",
                strategy = "display",
                requires_selection = true,
                category = "git",
                priority = 3
            },
            
            create_pr_description = {
                description = "Create pull request description",
                template = "Create a comprehensive pull request description for these changes:\n\n{code}\n\nInclude:\n- Summary of changes\n- Motivation and context\n- Testing done\n- Breaking changes (if any)",
                strategy = "display",
                requires_selection = true,
                category = "git",
                priority = 3
            }
        }
    }
    
    -- Write example files
    local files = {
        {name = "lua_actions.json", content = lua_actions},
        {name = "neovim_actions.json", content = nvim_actions},
        {name = "git_actions.json", content = git_actions}
    }
    
    for _, file in ipairs(files) do
        local filepath = actions_dir .. "/" .. file.name
        local json_content = vim.json.encode(file.content)
        vim.fn.writefile(vim.split(json_content, "\n"), filepath)
    end
    
    notify.info("Created example action files in " .. actions_dir)
    return actions_dir
end

-- Action template generator
function M.generate_action_template(name, description)
    local template = {
        actions = {
            [name] = {
                description = description or "Custom action",
                template = "Your prompt template here. Use {code}, {filetype}, {filename} variables.",
                strategy = "replace",
                requires_selection = true,
                category = "custom",
                priority = 3,
                validate = "return true -- Add validation logic here",
                api_params = {
                    temperature = 0.7,
                    max_tokens = 1500
                }
            }
        }
    }
    
    return vim.json.encode(template)
end

-- Interactive action creator
function M.create_action_interactive()
    local function get_input(prompt, default)
        local result = vim.fn.input(prompt, default or "")
        return result ~= "" and result or nil
    end
    
    local name = get_input("Action name: ")
    if not name then return end
    
    local description = get_input("Description: ")
    local template = get_input("Template (use {code}, {filetype} variables): ")
    if not template then return end
    
    local strategy = get_input("Strategy (replace/append/prepend/display): ", "replace")
    local category = get_input("Category: ", "custom")
    
    local action_config = {
        description = description,
        template = template,
        strategy = strategy,
        requires_selection = true,
        category = category,
        priority = 3
    }
    
    -- Register the action
    actions.register_action(name, action_config)
    
    -- Ask if user wants to save to file
    local save = vim.fn.confirm("Save action to file?", "&Yes\n&No", 1)
    if save == 1 then
        local filename = get_input("Filename (without .json): ", name)
        if filename then
            local filepath = default_actions_dir .. "/" .. filename .. ".json"
            local content = {actions = {[name] = action_config}}
            
            -- Ensure directory exists
            vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
            
            local json_content = vim.json.encode(content)
            vim.fn.writefile(vim.split(json_content, "\n"), filepath)
            notify.info("Action saved to " .. filepath)
        end
    end
    
    notify.info("Action '" .. name .. "' created and registered")
end

-- Setup function
function M.setup(opts)
    opts = opts or {}
    
    -- Set custom actions directory
    if opts.actions_dir then
        default_actions_dir = opts.actions_dir
    end
    
    -- Load actions from default directory
    if opts.load_from_directory ~= false then
        local success, result = M.load_actions_from_directory(default_actions_dir)
        if success then
            notify.info(result)
        end
    end
    
    -- Load specific action files
    if opts.action_files then
        for _, file in ipairs(opts.action_files) do
            local success, result = M.load_actions_from_file(file)
            if not success then
                notify.warn(result)
            end
        end
    end
    
    -- Create example actions if requested
    if opts.create_examples then
        M.create_example_actions()
    end
    
    -- Register commands
    vim.api.nvim_create_user_command("WindsurfCreateAction", function()
        M.create_action_interactive()
    end, {
        desc = "Create a new Windsurf action interactively"
    })
    
    vim.api.nvim_create_user_command("WindsurfLoadActions", function(cmd_opts)
        local path = cmd_opts.args
        if path == "" then
            path = default_actions_dir
        end
        
        local success, result
        if vim.fn.isdirectory(path) == 1 then
            success, result = M.load_actions_from_directory(path)
        else
            success, result = M.load_actions_from_file(path)
        end
        
        if success then
            notify.info(result)
        else
            notify.error(result)
        end
    end, {
        nargs = "?",
        complete = "file",
        desc = "Load actions from file or directory"
    })
    
    vim.api.nvim_create_user_command("WindsurfCreateExamples", function()
        local dir = M.create_example_actions()
        vim.cmd("edit " .. dir)
    end, {
        desc = "Create example action files"
    })
end

return M
