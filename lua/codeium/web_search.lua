local M = {}
local curl = require("plenary.curl")
local notify = require("codeium.notify")

-- Default configuration
M.config = {
	provider = "tavily", -- tavily, serpapi, google, kagi, brave, searxng
	proxy = nil,
	timeout = 30000,
}

-- Environment variable mappings for each provider
local env_vars = {
	tavily = "TAVILY_API_KEY",
	serpapi = "SERPAPI_API_KEY",
	google = { "GOOGLE_SEARCH_API_KEY", "GOOGLE_SEARCH_ENGINE_ID" },
	kagi = "KAGI_API_KEY",
	brave = "BRAVE_API_KEY",
	searxng = "SEARXNG_API_URL",
}

-- API endpoints for each provider
local endpoints = {
	tavily = "https://api.tavily.com/search",
	serpapi = "https://serpapi.com/search",
	google = "https://www.googleapis.com/customsearch/v1",
	kagi = "https://kagi.com/api/v0/search",
	brave = "https://api.search.brave.com/res/v1/web/search",
	searxng = nil, -- Will be set from env var
}

-- Setup function
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Check if provider is available (has required API keys)
function M.is_provider_available(provider)
	local required_vars = env_vars[provider]
	if not required_vars then
		return false
	end

	if type(required_vars) == "table" then
		for _, var in ipairs(required_vars) do
			if not vim.env[var] then
				return false
			end
		end
		return true
	else
		return vim.env[required_vars] ~= nil
	end
end

-- Get available providers
function M.get_available_providers()
	local available = {}
	for provider, _ in pairs(env_vars) do
		if M.is_provider_available(provider) then
			table.insert(available, provider)
		end
	end
	return available
end

-- Format search query for different providers
local function format_query_for_provider(query, provider)
	local formatted = {
		query = query,
		max_results = 5,
	}

	if provider == "tavily" then
		formatted.search_depth = "advanced"
		formatted.include_answer = true
		formatted.include_raw_content = false
	elseif provider == "google" then
		formatted.cx = vim.env.GOOGLE_SEARCH_ENGINE_ID
		formatted.key = vim.env.GOOGLE_SEARCH_API_KEY
		formatted.q = query
		formatted.num = 5
	elseif provider == "kagi" then
		formatted.limit = 5
	elseif provider == "brave" then
		formatted.count = 5
	elseif provider == "searxng" then
		formatted.format = "json"
		formatted.engines = "google,bing,duckduckgo"
	end

	return formatted
end

-- Parse search results from different providers
local function parse_results(response_body, provider)
	local ok, data = pcall(vim.fn.json_decode, response_body)
	if not ok then
		return nil, "Failed to parse JSON response"
	end

	local results = {}

	if provider == "tavily" then
		if data.results then
			for _, result in ipairs(data.results) do
				table.insert(results, {
					title = result.title or "",
					url = result.url or "",
					snippet = result.content or "",
					score = result.score or 0,
				})
			end
		end
	elseif provider == "google" then
		if data.items then
			for _, item in ipairs(data.items) do
				table.insert(results, {
					title = item.title or "",
					url = item.link or "",
					snippet = item.snippet or "",
					score = 1.0,
				})
			end
		end
	elseif provider == "kagi" then
		if data.data then
			for _, result in ipairs(data.data) do
				table.insert(results, {
					title = result.title or "",
					url = result.url or "",
					snippet = result.snippet or "",
					score = 1.0,
				})
			end
		end
	elseif provider == "brave" then
		if data.web and data.web.results then
			for _, result in ipairs(data.web.results) do
				table.insert(results, {
					title = result.title or "",
					url = result.url or "",
					snippet = result.description or "",
					score = 1.0,
				})
			end
		end
	elseif provider == "searxng" then
		if data.results then
			for _, result in ipairs(data.results) do
				table.insert(results, {
					title = result.title or "",
					url = result.url or "",
					snippet = result.content or "",
					score = 1.0,
				})
			end
		end
	end

	return results, nil
end

-- Perform web search
function M.search(query, callback, provider)
	provider = provider or M.config.provider

	if not M.is_provider_available(provider) then
		local err = "Provider " .. provider .. " is not available (missing API keys)"
		if callback then
			callback(nil, err)
		end
		return
	end

	local endpoint = endpoints[provider]
	if provider == "searxng" then
		endpoint = vim.env.SEARXNG_API_URL
		if not endpoint then
			local err = "SearXNG API URL not configured"
			if callback then
				callback(nil, err)
			end
			return
		end
	end

	local formatted_query = format_query_for_provider(query, provider)
	local headers = {
		["Content-Type"] = "application/json",
	}

	-- Add authentication headers based on provider
	if provider == "tavily" then
		headers["Authorization"] = "Bearer " .. vim.env.TAVILY_API_KEY
	elseif provider == "kagi" then
		headers["Authorization"] = "Bot " .. vim.env.KAGI_API_KEY
	elseif provider == "brave" then
		headers["X-Subscription-Token"] = vim.env.BRAVE_API_KEY
	end

	local request_opts = {
		url = endpoint,
		method = provider == "google" and "GET" or "POST",
		headers = headers,
		timeout = M.config.timeout,
	}

	if provider == "google" then
		-- For Google, use query parameters
		local params = {}
		for k, v in pairs(formatted_query) do
			table.insert(params, k .. "=" .. vim.uri_encode(tostring(v)))
		end
		request_opts.url = endpoint .. "?" .. table.concat(params, "&")
	else
		request_opts.body = vim.fn.json_encode(formatted_query)
	end

	if M.config.proxy then
		request_opts.proxy = M.config.proxy
	end

	curl.request(request_opts, function(response)
		if response.status ~= 200 then
			local err = "Search request failed with status: " .. response.status
			if callback then
				callback(nil, err)
			end
			return
		end

		local results, parse_err = parse_results(response.body, provider)
		if parse_err then
			if callback then
				callback(nil, parse_err)
			end
			return
		end

		if callback then
			callback(results, nil)
		end
	end)
end

-- Format search results for display
function M.format_results(results, max_results)
	max_results = max_results or 5
	if not results or #results == 0 then
		return "No search results found."
	end

	local formatted = {}
	table.insert(formatted, "🔍 **Web Search Results:**\n")

	for i, result in ipairs(results) do
		if i > max_results then
			break
		end

		table.insert(formatted, string.format("**%d. %s**", i, result.title))
		table.insert(formatted, string.format("🔗 %s", result.url))
		if result.snippet and result.snippet ~= "" then
			table.insert(formatted, string.format("📝 %s", result.snippet))
		end
		table.insert(formatted, "")
	end

	return table.concat(formatted, "\n")
end

-- Search and format results (convenience function)
function M.search_and_format(query, callback, provider, max_results)
	M.search(query, function(results, err)
		if err then
			if callback then
				callback(nil, err)
			end
			return
		end

		local formatted = M.format_results(results, max_results)
		if callback then
			callback(formatted, nil)
		end
	end, provider)
end

-- Show provider selection menu
function M.show_provider_menu()
	local available = M.get_available_providers()
	if #available == 0 then
		notify.warn("No web search providers available. Please configure API keys.")
		return
	end

	vim.ui.select(available, {
		prompt = "Select web search provider:",
		format_item = function(item)
			local current = item == M.config.provider and " (current)" or ""
			return item .. current
		end,
	}, function(choice)
		if choice then
			M.config.provider = choice
			notify.info("Web search provider set to: " .. choice)
		end
	end)
end

return M
