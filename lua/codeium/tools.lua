local M = {}
local curl = require("plenary.curl")
local notify = require("codeium.notify")
local util = require("codeium.util")

-- Available tools configuration
M.config = {
  enabled = true,
  disabled_tools = {}, -- List of tools to disable
  timeout = 30000,
}

-- Tool definitions
local tools = {
  rag_search = {
    name = "rag_search",
    description = "Search for relevant code context using RAG",
    enabled = true,
  },
  web_search = {
    name = "web_search", 
    description = "Search the web for information",
    enabled = true,
  },
  git_diff = {
    name = "git_diff",
    description = "Get git diff for current changes",
    enabled = true,
  },
  git_commit = {
    name = "git_commit",
    description = "Get recent git commits",
    enabled = true,
  },
  bash = {
    name = "bash",
    description = "Execute bash commands",
    enabled = true,
  },
  python = {
    name = "python",
    description = "Execute Python code",
    enabled = true,
  },
  read_file = {
    name = "read_file",
    description = "Read file contents",
    enabled = true,
  },
  create_file = {
    name = "create_file",
    description = "Create new files",
    enabled = true,
  },
  glob = {
    name = "glob",
    description = "Find files using glob patterns",
    enabled = true,
  },
  search_keyword = {
    name = "search_keyword",
    description = "Search for keywords in files",
    enabled = true,
  },
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Disable specified tools
  for _, tool_name in ipairs(M.config.disabled_tools) do
    if tools[tool_name] then
      tools[tool_name].enabled = false
    end
  end
end

-- Check if tools are enabled
function M.are_tools_enabled()
  return M.config.enabled
end

-- Get list of available tools
function M.get_available_tools()
  local available = {}
  for name, tool in pairs(tools) do
    if tool.enabled then
      table.insert(available, {
        name = name,
        description = tool.description,
      })
    end
  end
  return available
end

-- Execute git diff tool
function M.execute_git_diff(args)
  args = args or {}
  local cmd = "git diff"
  
  if args.staged then
    cmd = cmd .. " --staged"
  end
  
  if args.file then
    cmd = cmd .. " " .. vim.fn.shellescape(args.file)
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute git diff"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then
    return nil, "Git diff command failed"
  end
  
  return result, nil
end

-- Execute git commit log tool
function M.execute_git_commit(args)
  args = args or {}
  local limit = args.limit or 10
  local format = args.format or "--oneline"
  
  local cmd = string.format("git log %s -%d", format, limit)
  
  if args.file then
    cmd = cmd .. " " .. vim.fn.shellescape(args.file)
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute git log"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then
    return nil, "Git log command failed"
  end
  
  return result, nil
end

-- Execute bash command tool
function M.execute_bash(command, args)
  args = args or {}
  
  if not command or command == "" then
    return nil, "No command provided"
  end
  
  -- Security check - basic command validation
  local dangerous_patterns = {
    "rm%s+-rf%s+/",
    "sudo%s+rm",
    "format%s+",
    "mkfs",
    "dd%s+if=",
  }
  
  for _, pattern in ipairs(dangerous_patterns) do
    if command:match(pattern) then
      return nil, "Potentially dangerous command blocked"
    end
  end
  
  local timeout = args.timeout or M.config.timeout
  local cmd = command
  
  if args.cwd then
    cmd = string.format("cd %s && %s", vim.fn.shellescape(args.cwd), cmd)
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute command"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  return result, success and nil or "Command execution failed"
end

-- Execute Python code tool
function M.execute_python(code, args)
  args = args or {}
  
  if not code or code == "" then
    return nil, "No Python code provided"
  end
  
  -- Create temporary file for Python code
  local temp_file = vim.fn.tempname() .. ".py"
  local file = io.open(temp_file, "w")
  if not file then
    return nil, "Failed to create temporary file"
  end
  
  file:write(code)
  file:close()
  
  local cmd = "python3 " .. vim.fn.shellescape(temp_file)
  
  if args.cwd then
    cmd = string.format("cd %s && %s", vim.fn.shellescape(args.cwd), cmd)
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    vim.fn.delete(temp_file)
    return nil, "Failed to execute Python code"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  -- Clean up temporary file
  vim.fn.delete(temp_file)
  
  return result, success and nil or "Python execution failed"
end

-- Read file tool
function M.execute_read_file(filepath, args)
  args = args or {}
  
  if not filepath or filepath == "" then
    return nil, "No file path provided"
  end
  
  -- Security check - ensure file is within workspace
  local workspace_root = util.get_project_root()
  local abs_path = vim.fn.fnamemodify(filepath, ":p")
  
  if not abs_path:match("^" .. vim.pesc(workspace_root)) then
    return nil, "File access outside workspace not allowed"
  end
  
  local file = io.open(abs_path, "r")
  if not file then
    return nil, "Failed to open file: " .. filepath
  end
  
  local content = file:read("*a")
  file:close()
  
  -- Apply line limits if specified
  if args.start_line or args.end_line then
    local lines = vim.split(content, "\n")
    local start_idx = args.start_line or 1
    local end_idx = args.end_line or #lines
    
    local selected_lines = {}
    for i = start_idx, math.min(end_idx, #lines) do
      table.insert(selected_lines, lines[i])
    end
    
    content = table.concat(selected_lines, "\n")
  end
  
  return content, nil
end

-- Create file tool
function M.execute_create_file(filepath, content, args)
  args = args or {}
  
  if not filepath or filepath == "" then
    return nil, "No file path provided"
  end
  
  -- Security check - ensure file is within workspace
  local workspace_root = util.get_project_root()
  local abs_path = vim.fn.fnamemodify(filepath, ":p")
  
  if not abs_path:match("^" .. vim.pesc(workspace_root)) then
    return nil, "File creation outside workspace not allowed"
  end
  
  -- Create directory if it doesn't exist
  local dir = vim.fn.fnamemodify(abs_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    if vim.fn.mkdir(dir, "p") == 0 then
      return nil, "Failed to create directory: " .. dir
    end
  end
  
  local file = io.open(abs_path, "w")
  if not file then
    return nil, "Failed to create file: " .. filepath
  end
  
  file:write(content or "")
  file:close()
  
  return "File created successfully: " .. filepath, nil
end

-- Glob search tool
function M.execute_glob(pattern, args)
  args = args or {}
  
  if not pattern or pattern == "" then
    return nil, "No glob pattern provided"
  end
  
  local workspace_root = args.cwd or util.get_project_root()
  local cmd = string.format("find %s -name %s -type f", 
    vim.fn.shellescape(workspace_root), 
    vim.fn.shellescape(pattern))
  
  if args.max_results then
    cmd = cmd .. " | head -" .. args.max_results
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute glob search"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then
    return nil, "Glob search failed"
  end
  
  return result, nil
end

-- Keyword search tool
function M.execute_search_keyword(keyword, args)
  args = args or {}
  
  if not keyword or keyword == "" then
    return nil, "No keyword provided"
  end
  
  local workspace_root = args.cwd or util.get_project_root()
  local cmd = string.format("grep -r %s %s", 
    vim.fn.shellescape(keyword), 
    vim.fn.shellescape(workspace_root))
  
  if args.file_pattern then
    cmd = cmd .. " --include=" .. vim.fn.shellescape(args.file_pattern)
  end
  
  if args.max_results then
    cmd = cmd .. " | head -" .. args.max_results
  end
  
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute keyword search"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  return result, success and nil or "Keyword search failed"
end

-- Execute tool by name
function M.execute_tool(tool_name, args)
  if not M.are_tools_enabled() then
    return nil, "Tools are disabled"
  end
  
  if not tools[tool_name] or not tools[tool_name].enabled then
    return nil, "Tool not available: " .. tool_name
  end
  
  args = args or {}
  
  if tool_name == "rag_search" then
    local rag = require("codeium.rag")
    if not rag.is_available() then
      return nil, "RAG service is not available"
    end
    -- This would be handled by the RAG module
    return "RAG search functionality available", nil
    
  elseif tool_name == "web_search" then
    local web_search = require("codeium.web_search")
    if not web_search.get_available_providers()[1] then
      return nil, "No web search providers available"
    end
    -- This would be handled by the web search module
    return "Web search functionality available", nil
    
  elseif tool_name == "git_diff" then
    return M.execute_git_diff(args)
    
  elseif tool_name == "git_commit" then
    return M.execute_git_commit(args)
    
  elseif tool_name == "bash" then
    return M.execute_bash(args.command, args)
    
  elseif tool_name == "python" then
    return M.execute_python(args.code, args)
    
  elseif tool_name == "read_file" then
    return M.execute_read_file(args.filepath, args)
    
  elseif tool_name == "create_file" then
    return M.execute_create_file(args.filepath, args.content, args)
    
  elseif tool_name == "glob" then
    return M.execute_glob(args.pattern, args)
    
  elseif tool_name == "search_keyword" then
    return M.execute_search_keyword(args.keyword, args)
    
  else
    return nil, "Unknown tool: " .. tool_name
  end
end

-- Show tools menu
function M.show_tools_menu()
  local available = M.get_available_tools()
  if #available == 0 then
    notify.warn("No tools are available")
    return
  end
  
  local options = {}
  for _, tool in ipairs(available) do
    table.insert(options, tool.name .. " - " .. tool.description)
  end
  
  vim.ui.select(options, {
    prompt = "Available Tools:",
  }, function(choice)
    if choice then
      local tool_name = choice:match("^([^%s]+)")
      notify.info("Selected tool: " .. tool_name)
      -- Could add interactive tool execution here
    end
  end)
end

return M
