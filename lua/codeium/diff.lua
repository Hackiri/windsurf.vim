local api = vim.api
local notify = require("codeium.notify")
local util = require("codeium.util")

local M = {}

-- Diff modes
M.DIFF_MODES = {
  REPLACE = "replace",
  INSERT = "insert", 
  APPEND = "append",
  SMART_MERGE = "smart_merge"
}

-- Parse code blocks from AI response
function M.parse_code_blocks(response)
  local code_blocks = {}
  local current_block = nil
  
  for line in response:gmatch("[^\r\n]+") do
    -- Start of code block
    local lang = line:match("^```(%w*)")
    if lang then
      current_block = {
        language = lang ~= "" and lang or "text",
        content = {},
        raw_content = "",
      }
    -- End of code block
    elseif line:match("^```$") and current_block then
      current_block.raw_content = table.concat(current_block.content, "\n")
      table.insert(code_blocks, current_block)
      current_block = nil
    -- Content inside code block
    elseif current_block then
      table.insert(current_block.content, line)
    end
  end
  
  return code_blocks
end

-- Extract file path from code block or context
function M.extract_file_info(code_block, context)
  local file_path = nil
  local line_start = nil
  local line_end = nil
  
  -- Look for file path in the first few lines of the code block
  local content_lines = code_block.content
  if #content_lines > 0 then
    local first_line = content_lines[1]
    
    -- Check for common file path patterns
    local patterns = {
      "^// File: (.+)$",
      "^# File: (.+)$", 
      "^-- File: (.+)$",
      "^<!-- File: (.+) -->$",
      "^// (.+)$",
      "^# (.+)$"
    }
    
    for _, pattern in ipairs(patterns) do
      local match = first_line:match(pattern)
      if match and match:match("%.%w+$") then -- Has file extension
        file_path = match
        table.remove(content_lines, 1) -- Remove the file path line
        break
      end
    end
    
    -- Look for line range indicators
    if #content_lines > 0 then
      local second_line = content_lines[1]
      local start_line, end_line = second_line:match("^// Lines (%d+)-(%d+)$")
      if start_line and end_line then
        line_start = tonumber(start_line)
        line_end = tonumber(end_line)
        table.remove(content_lines, 1) -- Remove the line range indicator
      end
    end
  end
  
  -- If no file path found, try to infer from context
  if not file_path and context and context.current_file then
    file_path = context.current_file
  end
  
  return file_path, line_start, line_end
end

-- Smart merge algorithm for code changes
function M.smart_merge(original_lines, new_lines, start_line, end_line)
  local result = {}
  
  -- Copy lines before the change
  for i = 1, (start_line or 1) - 1 do
    if original_lines[i] then
      table.insert(result, original_lines[i])
    end
  end
  
  -- Add new lines
  for _, line in ipairs(new_lines) do
    table.insert(result, line)
  end
  
  -- Copy lines after the change
  local after_line = (end_line or #original_lines) + 1
  for i = after_line, #original_lines do
    if original_lines[i] then
      table.insert(result, original_lines[i])
    end
  end
  
  return result
end

-- Apply code block to file
function M.apply_code_block(code_block, options)
  options = options or {}
  local mode = options.mode or M.DIFF_MODES.SMART_MERGE
  local context = options.context or {}
  
  -- Extract file information
  local file_path, line_start, line_end = M.extract_file_info(code_block, context)
  
  if not file_path then
    notify.error("Could not determine target file for code application")
    return false
  end
  
  -- Convert to absolute path if relative
  if not vim.startswith(file_path, "/") then
    local cwd = vim.fn.getcwd()
    file_path = cwd .. "/" .. file_path
  end
  
  -- Check if file exists or if we should create it
  local file_exists = vim.fn.filereadable(file_path) == 1
  local bufnr = nil
  
  if file_exists then
    -- Find existing buffer or load file
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(buf) then
        local buf_name = api.nvim_buf_get_name(buf)
        if buf_name == file_path then
          bufnr = buf
          break
        end
      end
    end
    
    if not bufnr then
      -- Open file in new buffer
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
      bufnr = api.nvim_get_current_buf()
    end
  else
    -- Create new file
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    bufnr = api.nvim_get_current_buf()
  end
  
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    notify.error("Failed to open file: " .. file_path)
    return false
  end
  
  -- Get current file content
  local original_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_content_lines = vim.split(code_block.raw_content, "\n")
  
  -- Apply changes based on mode
  local result_lines = {}
  
  if mode == M.DIFF_MODES.REPLACE then
    result_lines = new_content_lines
  elseif mode == M.DIFF_MODES.INSERT then
    local cursor_line = options.cursor_line or api.nvim_win_get_cursor(0)[1]
    result_lines = M.smart_merge(original_lines, new_content_lines, cursor_line, cursor_line - 1)
  elseif mode == M.DIFF_MODES.APPEND then
    result_lines = vim.list_extend(vim.deepcopy(original_lines), new_content_lines)
  elseif mode == M.DIFF_MODES.SMART_MERGE then
    result_lines = M.smart_merge(original_lines, new_content_lines, line_start, line_end)
  end
  
  -- Apply changes to buffer
  api.nvim_buf_set_lines(bufnr, 0, -1, false, result_lines)
  
  -- Show diff if requested
  if options.show_diff then
    M.show_diff_preview(original_lines, result_lines, file_path)
  end
  
  notify.info(string.format("Applied code changes to %s (%s mode)", 
    vim.fn.fnamemodify(file_path, ":t"), mode))
  
  return true
end

-- Show diff preview in a floating window
function M.show_diff_preview(original_lines, new_lines, file_path)
  -- Create diff content
  local diff_lines = {}
  table.insert(diff_lines, "--- " .. file_path .. " (original)")
  table.insert(diff_lines, "+++ " .. file_path .. " (modified)")
  table.insert(diff_lines, "")
  
  -- Simple diff algorithm
  local max_lines = math.max(#original_lines, #new_lines)
  for i = 1, max_lines do
    local orig = original_lines[i] or ""
    local new = new_lines[i] or ""
    
    if orig ~= new then
      if orig ~= "" then
        table.insert(diff_lines, "- " .. orig)
      end
      if new ~= "" then
        table.insert(diff_lines, "+ " .. new)
      end
    else
      table.insert(diff_lines, "  " .. orig)
    end
  end
  
  -- Create floating window
  local width = math.min(120, vim.o.columns - 4)
  local height = math.min(30, #diff_lines + 2)
  
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_lines)
  api.nvim_buf_set_option(bufnr, "filetype", "diff")
  api.nvim_buf_set_option(bufnr, "modifiable", false)
  
  local winid = api.nvim_open_win(bufnr, false, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Diff Preview ",
    title_pos = "center",
  })
  
  -- Auto-close after 10 seconds
  vim.defer_fn(function()
    if api.nvim_win_is_valid(winid) then
      api.nvim_win_close(winid, true)
    end
  end, 10000)
end

-- Apply multiple code blocks with conflict resolution
function M.apply_multiple_blocks(code_blocks, options)
  options = options or {}
  local applied_count = 0
  local failed_count = 0
  
  for i, block in ipairs(code_blocks) do
    local block_options = vim.tbl_extend("force", options, {
      show_diff = i == 1, -- Only show diff for first block
    })
    
    if M.apply_code_block(block, block_options) then
      applied_count = applied_count + 1
    else
      failed_count = failed_count + 1
    end
  end
  
  if applied_count > 0 then
    notify.info(string.format("Applied %d code block(s)", applied_count))
  end
  
  if failed_count > 0 then
    notify.warn(string.format("Failed to apply %d code block(s)", failed_count))
  end
  
  return applied_count, failed_count
end

-- Interactive code application with user confirmation
function M.apply_with_confirmation(response, context)
  local code_blocks = M.parse_code_blocks(response)
  
  if #code_blocks == 0 then
    notify.warn("No code blocks found in response")
    return
  end
  
  if #code_blocks == 1 then
    -- Single block - apply directly
    M.apply_code_block(code_blocks[1], {
      mode = M.DIFF_MODES.SMART_MERGE,
      context = context,
      show_diff = true,
    })
  else
    -- Multiple blocks - show selection menu
    local items = {}
    for i, block in ipairs(code_blocks) do
      local file_path, line_start, line_end = M.extract_file_info(block, context)
      local preview = table.concat(vim.list_slice(block.content, 1, 3), " ")
      if #preview > 50 then
        preview = preview:sub(1, 50) .. "..."
      end
      
      table.insert(items, string.format("%d. %s (%s) - %s", 
        i, file_path or "unknown", block.language, preview))
    end
    
    table.insert(items, "Apply All")
    
    vim.ui.select(items, {
      prompt = "Select code block to apply:",
    }, function(choice, idx)
      if not choice or not idx then return end
      
      if idx == #items then
        -- Apply all
        M.apply_multiple_blocks(code_blocks, {
          mode = M.DIFF_MODES.SMART_MERGE,
          context = context,
        })
      else
        -- Apply selected block
        M.apply_code_block(code_blocks[idx], {
          mode = M.DIFF_MODES.SMART_MERGE,
          context = context,
          show_diff = true,
        })
      end
    end)
  end
end

return M
