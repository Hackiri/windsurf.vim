-- Complete Chatbox Setup for windsurf.nvim
-- Integrates all advanced Action System components with browser and sidebar chat

local M = {}

-- Setup function that integrates everything
function M.setup_complete_chatbox_system(options)
    options = options or {}
    
    -- Initialize all components in correct order
    local actions = require("codeium.actions")
    local action_loader = require("codeium.action_loader")
    local advanced_actions = require("codeium.advanced_actions")
    local chatbox_integration = require("codeium.chatbox_integration")
    local integration_example = require("codeium.integration_example")
    
    -- 1. Setup core action system
    actions.setup(options.actions or {})
    
    -- 2. Setup action loader with examples
    action_loader.setup(vim.tbl_extend("force", {
        create_examples = true,
        actions_dir = vim.fn.stdpath("config") .. "/windsurf/actions"
    }, options.action_loader or {}))
    
    -- 3. Setup advanced Lua actions
    advanced_actions.setup()
    
    -- 4. Setup advanced integration patterns
    integration_example.setup_advanced_integration()
    
    -- 5. Setup chatbox integration (this enhances existing chat functions)
    chatbox_integration.setup(vim.tbl_extend("force", {
        enhance_existing = true
    }, options.chatbox_integration or {}))
    
    -- Create unified command interface
    vim.api.nvim_create_user_command("WindsurfChatSystem", function(cmd_opts)
        local args = cmd_opts.fargs
        local command = args[1] or "help"
        
        if command == "help" then
            M.show_help()
        elseif command == "browser" then
            chatbox_integration.open_browser_chat_enhanced()
        elseif command == "sidebar" then
            chatbox_integration.open_sidebar_chat_enhanced()
        elseif command == "smart" then
            chatbox_integration.smart_chat_switch()
        elseif command == "actions" then
            chatbox_integration.show_quick_actions_menu()
        elseif command == "context" then
            chatbox_integration.show_contextual_actions()
        elseif command == "stats" then
            chatbox_integration.show_action_stats()
        elseif command == "advanced" then
            advanced_actions.advanced_action_picker()
        else
            vim.notify("Unknown command: " .. command, vim.log.levels.ERROR)
            M.show_help()
        end
    end, {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local commands = {
                "help", "browser", "sidebar", "smart", 
                "actions", "context", "stats", "advanced"
            }
            return vim.tbl_filter(function(cmd)
                return cmd:find(arglead, 1, true) == 1
            end, commands)
        end,
        desc = "Windsurf Chat System - unified interface"
    })
    
    -- Setup master keybinding
    vim.keymap.set("n", "<leader>aw", function()
        chatbox_integration.enhanced_chat_interface()
    end, { desc = "Windsurf Chat System" })
    
    return true
end

-- Help system
function M.show_help()
    local help_lines = {
        "=== Windsurf AI Chat System ===",
        "",
        "🌐 Browser Chat Integration:",
        "  • Full Windsurf AI interface with context",
        "  • Automatic context copying to clipboard",
        "  • Best for complex, multi-file tasks",
        "",
        "💬 Sidebar Chat Integration:",
        "  • Quick in-editor chat interface",
        "  • Context-aware suggestions",
        "  • Best for focused, single-file tasks",
        "",
        "⚡ Action System Features:",
        "  • 15+ built-in actions (explain, optimize, test, etc.)",
        "  • Advanced Lua-specific actions",
        "  • JSON-based custom action loading",
        "  • Performance monitoring and statistics",
        "",
        "🎯 Smart Features:",
        "  • Context-aware action suggestions",
        "  • Automatic chat mode selection",
        "  • Real-time code analysis",
        "  • Metatable and coroutine enhancements",
        "",
        "📋 Commands:",
        "  :WindsurfChatSystem browser   - Open browser chat",
        "  :WindsurfChatSystem sidebar   - Open sidebar chat", 
        "  :WindsurfChatSystem smart     - Smart mode selection",
        "  :WindsurfChatSystem actions   - Quick actions menu",
        "  :WindsurfChatSystem context   - Context-aware actions",
        "  :WindsurfChatSystem advanced  - Advanced Lua actions",
        "  :WindsurfChatSystem stats     - Performance statistics",
        "",
        "⌨️  Key Bindings:",
        "  <leader>aw  - Main chat interface",
        "  <leader>aC  - Enhanced chat interface",
        "  <leader>aS  - Smart chat mode",
        "  <leader>aQ  - Quick actions",
        "  <leader>aX  - Context actions",
        "  <leader>aL  - Advanced Lua actions",
        "  <leader>aa  - General action picker",
        "",
        "📁 File Structure:",
        "  ~/.config/nvim/windsurf/actions/  - Custom actions",
        "  lua/codeium/actions.lua           - Core action system",
        "  lua/codeium/advanced_actions.lua  - Advanced Lua actions",
        "  lua/codeium/chatbox_integration.lua - Chat integration",
        "",
        "Press 'q' to close this help."
    }
    
    -- Create help buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, help_lines)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "help")
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    
    -- Create floating window
    local width = 80
    local height = math.min(#help_lines + 4, vim.o.lines - 6)
    local winid = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = width,
        height = height,
        col = (vim.o.columns - width) / 2,
        row = (vim.o.lines - height) / 2,
        style = "minimal",
        border = "rounded",
        title = " Windsurf AI Chat System Help ",
        title_pos = "center"
    })
    
    -- Close on 'q'
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(winid, true)
    end, { buffer = bufnr, nowait = true })
end

-- Configuration validation
function M.validate_setup()
    local issues = {}
    
    -- Check if required modules are available
    local required_modules = {
        "codeium.actions",
        "codeium.action_loader", 
        "codeium.advanced_actions",
        "codeium.chatbox_integration"
    }
    
    for _, module in ipairs(required_modules) do
        local ok, _ = pcall(require, module)
        if not ok then
            table.insert(issues, "Missing module: " .. module)
        end
    end
    
    -- Check actions directory
    local actions_dir = vim.fn.stdpath("config") .. "/windsurf/actions"
    if vim.fn.isdirectory(actions_dir) == 0 then
        table.insert(issues, "Actions directory not found: " .. actions_dir)
    end
    
    -- Check for example action files
    local example_files = {"lua_actions.json", "neovim_actions.json", "git_actions.json"}
    for _, file in ipairs(example_files) do
        local filepath = actions_dir .. "/" .. file
        if vim.fn.filereadable(filepath) == 0 then
            table.insert(issues, "Example file missing: " .. file)
        end
    end
    
    if #issues > 0 then
        vim.notify("Setup issues found:\n" .. table.concat(issues, "\n"), vim.log.levels.WARN)
        return false
    else
        vim.notify("Windsurf Chat System setup validated successfully!", vim.log.levels.INFO)
        return true
    end
end

-- Example configuration for init.lua
function M.get_example_config()
    return {
        actions = {
            load_defaults = true,
            custom_actions = {
                -- Add your custom actions here
            }
        },
        action_loader = {
            create_examples = true,
            actions_dir = vim.fn.stdpath("config") .. "/windsurf/actions",
            load_from_directory = true
        },
        chatbox_integration = {
            enhance_existing = true,
            auto_context_update = true,
            smart_mode_detection = true
        }
    }
end

return M
