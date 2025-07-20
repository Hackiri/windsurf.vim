local api = vim.api
local notify = require("codeium.notify")
local util = require("codeium.util")

local M = {}

-- Parse @mentions from text
function M.parse_mentions(text)
	local mentions = {}
	local patterns = {
		"@file",
		"@codebase",
		"@diagnostics",
		"@quickfix",
		"@buffers",
	}

	for _, pattern in ipairs(patterns) do
		if text:find(pattern) then
			table.insert(mentions, pattern:sub(2)) -- Remove @ symbol
		end
	end

	return mentions
end

-- Get current file context
function M.get_file_context(bufnr)
	bufnr = bufnr or 0
	local filename = api.nvim_buf_get_name(bufnr)

	if filename == "" then
		return nil
	end

	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	local filetype = api.nvim_buf_get_option(bufnr, "filetype")

	return {
		type = "file",
		filename = filename,
		relative_path = vim.fn.fnamemodify(filename, ":."),
		content = content,
		filetype = filetype,
		line_count = #lines,
		cursor_pos = api.nvim_win_get_cursor(0),
	}
end

-- Get codebase context (project files)
function M.get_codebase_context()
	local project_root = util.get_project_root()
	if not project_root then
		return nil
	end

	-- Get list of relevant files (limit to avoid overwhelming context)
	local files = {}
	local extensions = {
		".lua",
		".py",
		".js",
		".ts",
		".go",
		".rs",
		".c",
		".cpp",
		".h",
		".hpp",
		".java",
		".kt",
		".swift",
		".rb",
		".php",
		".cs",
		".scala",
		".clj",
		".hs",
		".ml",
		".elm",
		".dart",
		".r",
		".jl",
	}

	local function scan_directory(dir, max_files)
		if #files >= max_files then
			return
		end

		local handle = vim.loop.fs_scandir(dir)
		if not handle then
			return
		end

		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			local full_path = dir .. "/" .. name

			if type == "directory" and not name:match("^%.") and name ~= "node_modules" and name ~= ".git" then
				scan_directory(full_path, max_files)
			elseif type == "file" then
				local ext = name:match("%.([^%.]+)$")
				if ext and vim.tbl_contains(extensions, "." .. ext) then
					table.insert(files, {
						path = full_path,
						relative_path = vim.fn.fnamemodify(full_path, ":."),
						name = name,
						extension = ext,
					})
					if #files >= max_files then
						break
					end
				end
			end
		end
	end

	scan_directory(project_root, 50) -- Limit to 50 files

	return {
		type = "codebase",
		project_root = project_root,
		files = files,
		file_count = #files,
	}
end

-- Get diagnostics context
function M.get_diagnostics_context(bufnr)
	bufnr = bufnr or 0
	local diagnostics = vim.diagnostic.get(bufnr)

	if #diagnostics == 0 then
		return nil
	end

	local context = {
		type = "diagnostics",
		filename = api.nvim_buf_get_name(bufnr),
		diagnostics = {},
	}

	for _, diag in ipairs(diagnostics) do
		table.insert(context.diagnostics, {
			line = diag.lnum + 1,
			column = diag.col + 1,
			severity = vim.diagnostic.severity[diag.severity],
			message = diag.message,
			source = diag.source,
			code = diag.code,
		})
	end

	return context
end

-- Get quickfix context
function M.get_quickfix_context()
	local qflist = vim.fn.getqflist()

	if #qflist == 0 then
		return nil
	end

	local context = {
		type = "quickfix",
		items = {},
	}

	for _, item in ipairs(qflist) do
		if item.valid == 1 then
			table.insert(context.items, {
				filename = item.bufnr > 0 and api.nvim_buf_get_name(item.bufnr) or "",
				line = item.lnum,
				column = item.col,
				text = item.text,
				type = item.type,
			})
		end
	end

	return context
end

-- Get all open buffers context
function M.get_buffers_context()
	local buffers = {}

	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "buflisted") then
			local filename = api.nvim_buf_get_name(bufnr)
			if filename ~= "" then
				local filetype = api.nvim_buf_get_option(bufnr, "filetype")
				local modified = api.nvim_buf_get_option(bufnr, "modified")

				table.insert(buffers, {
					bufnr = bufnr,
					filename = filename,
					relative_path = vim.fn.fnamemodify(filename, ":."),
					filetype = filetype,
					modified = modified,
					line_count = api.nvim_buf_line_count(bufnr),
				})
			end
		end
	end

	return {
		type = "buffers",
		buffers = buffers,
		count = #buffers,
	}
end

-- Get context based on mention type
function M.get_context_for_mention(mention_type, bufnr)
	if mention_type == "file" then
		return M.get_file_context(bufnr)
	elseif mention_type == "codebase" then
		return M.get_codebase_context()
	elseif mention_type == "diagnostics" then
		return M.get_diagnostics_context(bufnr)
	elseif mention_type == "quickfix" then
		return M.get_quickfix_context()
	elseif mention_type == "buffers" then
		return M.get_buffers_context()
	else
		return nil
	end
end

-- Process message with mentions and return context
function M.process_message_context(message, bufnr)
	local mentions = M.parse_mentions(message)
	local context = {}

	for _, mention in ipairs(mentions) do
		local mention_context = M.get_context_for_mention(mention, bufnr)
		if mention_context then
			table.insert(context, mention_context)
		else
			notify.warn("No context available for @" .. mention)
		end
	end

	return context, mentions
end

-- Format context for AI prompt
function M.format_context_for_prompt(context)
	local formatted = {}

	for _, ctx in ipairs(context) do
		if ctx.type == "file" then
			table.insert(
				formatted,
				string.format(
					[[
## Current File: %s
```%s
%s
```
Cursor position: Line %d, Column %d
]],
					ctx.relative_path,
					ctx.filetype,
					ctx.content,
					ctx.cursor_pos[1],
					ctx.cursor_pos[2]
				)
			)
		elseif ctx.type == "codebase" then
			table.insert(formatted, "## Codebase Structure:")
			table.insert(formatted, string.format("Project root: %s", ctx.project_root))
			table.insert(formatted, string.format("Found %d relevant files:", ctx.file_count))

			for _, file in ipairs(ctx.files) do
				table.insert(formatted, string.format("- %s (%s)", file.relative_path, file.extension))
			end
		elseif ctx.type == "diagnostics" then
			table.insert(formatted, "## Current Diagnostics:")
			if ctx.filename then
				table.insert(formatted, string.format("File: %s", vim.fn.fnamemodify(ctx.filename, ":.")))
			end

			for _, diag in ipairs(ctx.diagnostics) do
				table.insert(
					formatted,
					string.format("- Line %d:%d [%s] %s", diag.line, diag.column, diag.severity, diag.message)
				)
			end
		elseif ctx.type == "quickfix" then
			table.insert(formatted, "## Quickfix List:")
			for _, item in ipairs(ctx.items) do
				local filename = item.filename ~= "" and vim.fn.fnamemodify(item.filename, ":.") or "unknown"
				table.insert(formatted, string.format("- %s:%d:%d %s", filename, item.line, item.column, item.text))
			end
		elseif ctx.type == "buffers" then
			table.insert(formatted, string.format("## Open Buffers (%d):", ctx.count))
			for _, buf in ipairs(ctx.buffers) do
				local status = buf.modified and " [modified]" or ""
				table.insert(
					formatted,
					string.format("- %s (%s, %d lines)%s", buf.relative_path, buf.filetype, buf.line_count, status)
				)
			end
		end

		table.insert(formatted, "")
	end

	return table.concat(formatted, "\n")
end

-- Get smart context (automatically determine relevant context)
function M.get_smart_context(message, bufnr)
	local context = {}

	-- Always include current file if available
	local file_context = M.get_file_context(bufnr)
	if file_context then
		table.insert(context, file_context)
	end

	-- Include diagnostics if there are any
	local diag_context = M.get_diagnostics_context(bufnr)
	if diag_context and #diag_context.diagnostics > 0 then
		table.insert(context, diag_context)
	end

	-- Include quickfix if message seems related to errors/issues
	if message:lower():match("error") or message:lower():match("issue") or message:lower():match("problem") then
		local qf_context = M.get_quickfix_context()
		if qf_context and #qf_context.items > 0 then
			table.insert(context, qf_context)
		end
	end

	return context
end

return M
