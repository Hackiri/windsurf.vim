local M = {}
local curl = require("plenary.curl")
local notify = require("codeium.notify")
local util = require("codeium.util")

-- Default RAG configuration
M.config = {
  enabled = false,
  host_mount = vim.env.HOME or "/tmp",
  runner = "docker", -- docker or nix
  container_name = "windsurf-rag-service",
  port = 8080,
  llm = {
    provider = "openai",
    endpoint = "https://api.openai.com/v1",
    api_key = "OPENAI_API_KEY",
    model = "gpt-4o-mini",
    extra = nil,
  },
  embed = {
    provider = "openai", 
    endpoint = "https://api.openai.com/v1",
    api_key = "OPENAI_API_KEY",
    model = "text-embedding-3-large",
    extra = nil,
  },
  docker_extra_args = "",
  timeout = 30000,
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Check if RAG service is available
function M.is_available()
  return M.config.enabled and M.is_docker_available()
end

-- Check if Docker is available
function M.is_docker_available()
  if M.config.runner ~= "docker" then
    return true -- Assume other runners are available
  end
  
  local handle = io.popen("docker --version 2>/dev/null")
  if not handle then
    return false
  end
  
  local result = handle:read("*a")
  handle:close()
  
  return result and result:match("Docker version") ~= nil
end

-- Check if RAG service container is running
function M.is_service_running()
  if not M.is_docker_available() then
    return false
  end
  
  local cmd = string.format("docker ps --filter name=%s --format '{{.Names}}'", M.config.container_name)
  local handle = io.popen(cmd)
  if not handle then
    return false
  end
  
  local result = handle:read("*a")
  handle:close()
  
  return result and result:match(M.config.container_name) ~= nil
end

-- Start RAG service container
function M.start_service()
  if not M.is_available() then
    notify.error("RAG service is not available or not enabled")
    return false
  end
  
  if M.is_service_running() then
    notify.info("RAG service is already running")
    return true
  end
  
  -- Build docker run command
  local docker_cmd = {
    "docker", "run", "-d",
    "--name", M.config.container_name,
    "-p", string.format("%d:8080", M.config.port),
    "-v", string.format("%s:/workspace:ro", M.config.host_mount),
    "-e", string.format("LLM_PROVIDER=%s", M.config.llm.provider),
    "-e", string.format("LLM_ENDPOINT=%s", M.config.llm.endpoint),
    "-e", string.format("LLM_API_KEY=%s", vim.env[M.config.llm.api_key] or ""),
    "-e", string.format("LLM_MODEL=%s", M.config.llm.model),
    "-e", string.format("EMBED_PROVIDER=%s", M.config.embed.provider),
    "-e", string.format("EMBED_ENDPOINT=%s", M.config.embed.endpoint),
    "-e", string.format("EMBED_API_KEY=%s", vim.env[M.config.embed.api_key] or ""),
    "-e", string.format("EMBED_MODEL=%s", M.config.embed.model),
  }
  
  -- Add extra docker arguments
  if M.config.docker_extra_args and M.config.docker_extra_args ~= "" then
    for arg in M.config.docker_extra_args:gmatch("%S+") do
      table.insert(docker_cmd, arg)
    end
  end
  
  -- Use a lightweight RAG service image (placeholder - would need actual implementation)
  table.insert(docker_cmd, "windsurf/rag-service:latest")
  
  local cmd_str = table.concat(docker_cmd, " ")
  notify.info("Starting RAG service...")
  
  local handle = io.popen(cmd_str .. " 2>&1")
  if not handle then
    notify.error("Failed to start RAG service")
    return false
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success then
    notify.info("RAG service started successfully")
    return true
  else
    notify.error("Failed to start RAG service: " .. (result or "unknown error"))
    return false
  end
end

-- Stop RAG service container
function M.stop_service()
  if not M.is_service_running() then
    notify.info("RAG service is not running")
    return true
  end
  
  local cmd = string.format("docker stop %s && docker rm %s", M.config.container_name, M.config.container_name)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    notify.error("Failed to stop RAG service")
    return false
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success then
    notify.info("RAG service stopped successfully")
    return true
  else
    notify.error("Failed to stop RAG service: " .. (result or "unknown error"))
    return false
  end
end

-- Restart RAG service (useful after config changes)
function M.restart_service()
  M.stop_service()
  vim.defer_fn(function()
    M.start_service()
  end, 1000)
end

-- Query RAG service for context
function M.query_context(query, files, callback)
  if not M.is_available() then
    if callback then callback(nil, "RAG service is not available") end
    return
  end
  
  if not M.is_service_running() then
    notify.warn("RAG service is not running, attempting to start...")
    if not M.start_service() then
      if callback then callback(nil, "Failed to start RAG service") end
      return
    end
    
    -- Wait a bit for service to be ready
    vim.defer_fn(function()
      M.query_context(query, files, callback)
    end, 3000)
    return
  end
  
  local request_data = {
    query = query,
    files = files or {},
    max_results = 10,
    workspace_root = util.get_project_root(),
  }
  
  local endpoint = string.format("http://localhost:%d/query", M.config.port)
  
  curl.post(endpoint, {
    body = vim.fn.json_encode(request_data),
    headers = {
      ["Content-Type"] = "application/json",
    },
    timeout = M.config.timeout,
    callback = function(response)
      if response.status ~= 200 then
        local err = "RAG query failed with status: " .. response.status
        if callback then callback(nil, err) end
        return
      end
      
      local ok, data = pcall(vim.fn.json_decode, response.body)
      if not ok then
        if callback then callback(nil, "Failed to parse RAG response") end
        return
      end
      
      if callback then callback(data, nil) end
    end,
  })
end

-- Index files in RAG service
function M.index_files(files, callback)
  if not M.is_available() then
    if callback then callback(false, "RAG service is not available") end
    return
  end
  
  if not M.is_service_running() then
    if callback then callback(false, "RAG service is not running") end
    return
  end
  
  local request_data = {
    files = files,
    workspace_root = util.get_project_root(),
  }
  
  local endpoint = string.format("http://localhost:%d/index", M.config.port)
  
  curl.post(endpoint, {
    body = vim.fn.json_encode(request_data),
    headers = {
      ["Content-Type"] = "application/json",
    },
    timeout = M.config.timeout,
    callback = function(response)
      if response.status ~= 200 then
        local err = "RAG indexing failed with status: " .. response.status
        if callback then callback(false, err) end
        return
      end
      
      if callback then callback(true, nil) end
    end,
  })
end

-- Get RAG service status
function M.get_service_status()
  if not M.is_available() then
    return {
      available = false,
      running = false,
      message = "RAG service is not enabled or Docker is not available"
    }
  end
  
  local running = M.is_service_running()
  return {
    available = true,
    running = running,
    message = running and "RAG service is running" or "RAG service is not running"
  }
end

-- Format RAG results for display
function M.format_results(results, max_results)
  max_results = max_results or 5
  if not results or not results.contexts or #results.contexts == 0 then
    return "No relevant context found."
  end
  
  local formatted = {}
  table.insert(formatted, "🧠 **RAG Context Results:**\n")
  
  for i, context in ipairs(results.contexts) do
    if i > max_results then break end
    
    table.insert(formatted, string.format("**%d. %s**", i, context.file or "Unknown file"))
    if context.line_start and context.line_end then
      table.insert(formatted, string.format("📍 Lines %d-%d", context.line_start, context.line_end))
    end
    if context.content and context.content ~= "" then
      table.insert(formatted, string.format("```%s\n%s\n```", context.language or "", context.content))
    end
    if context.score then
      table.insert(formatted, string.format("🎯 Relevance: %.2f", context.score))
    end
    table.insert(formatted, "")
  end
  
  return table.concat(formatted, "\n")
end

-- Query and format RAG results (convenience function)
function M.query_and_format(query, files, callback, max_results)
  M.query_context(query, files, function(results, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    
    local formatted = M.format_results(results, max_results)
    if callback then callback(formatted, nil) end
  end)
end

-- Show RAG service management menu
function M.show_service_menu()
  local status = M.get_service_status()
  local options = {}
  
  if status.available then
    if status.running then
      table.insert(options, "Stop RAG Service")
      table.insert(options, "Restart RAG Service")
      table.insert(options, "Query Context")
    else
      table.insert(options, "Start RAG Service")
    end
    table.insert(options, "Service Status")
  else
    table.insert(options, "Enable RAG Service")
  end
  
  vim.ui.select(options, {
    prompt = "RAG Service Management:",
  }, function(choice)
    if choice == "Start RAG Service" then
      M.start_service()
    elseif choice == "Stop RAG Service" then
      M.stop_service()
    elseif choice == "Restart RAG Service" then
      M.restart_service()
    elseif choice == "Service Status" then
      notify.info(status.message)
    elseif choice == "Query Context" then
      vim.ui.input({ prompt = "Enter query: " }, function(query)
        if query and query ~= "" then
          M.query_and_format(query, {}, function(formatted, err)
            if err then
              notify.error("RAG query failed: " .. err)
            else
              -- Display results in a new buffer
              local buf = vim.api.nvim_create_buf(false, true)
              vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(formatted, "\n"))
              vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
              vim.api.nvim_win_set_buf(0, buf)
            end
          end)
        end
      end)
    elseif choice == "Enable RAG Service" then
      notify.info("To enable RAG service, set enabled = true in your windsurf.nvim configuration")
    end
  end)
end

return M
