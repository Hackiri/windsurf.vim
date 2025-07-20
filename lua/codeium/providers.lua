local config = require("codeium.config")
local notify = require("codeium.notify")

local M = {}

-- Available providers
M.providers = {
	windsurf = {
		name = "Windsurf",
		endpoint = "server.codeium.com",
		port = "443",
		path = "/",
		model = "windsurf-chat",
		supports_chat = true,
		supports_completion = true,
		supports_fast_apply = true,
	},
	claude = {
		name = "Claude",
		endpoint = "https://api.anthropic.com/v1",
		model = "claude-3-5-sonnet-20241022",
		api_key_env = "ANTHROPIC_API_KEY",
		supports_chat = true,
		supports_completion = true,
		supports_fast_apply = false,
	},
	openai = {
		name = "OpenAI",
		endpoint = "https://api.openai.com/v1",
		model = "gpt-4o",
		api_key_env = "OPENAI_API_KEY",
		supports_chat = true,
		supports_completion = true,
		supports_fast_apply = false,
	},
	gemini = {
		name = "Gemini",
		endpoint = "https://generativelanguage.googleapis.com/v1beta",
		model = "gemini-1.5-pro",
		api_key_env = "GEMINI_API_KEY",
		supports_chat = true,
		supports_completion = true,
		supports_fast_apply = false,
	},
}

-- Current active provider
M.current_provider = "windsurf"

-- Get current provider config
function M.get_current_provider()
	return M.providers[M.current_provider]
end

-- Switch to a different provider
function M.switch_provider(provider_name)
	if not M.providers[provider_name] then
		notify.error("Unknown provider: " .. provider_name)
		return false
	end

	local provider = M.providers[provider_name]

	-- Check if API key is available for external providers
	if provider.api_key_env then
		local api_key = vim.env[provider.api_key_env] or vim.env["AVANTE_" .. provider.api_key_env]
		if not api_key then
			notify.error(
				string.format(
					"API key not found for %s. Please set %s or AVANTE_%s environment variable.",
					provider.name,
					provider.api_key_env,
					provider.api_key_env
				)
			)
			return false
		end
	end

	M.current_provider = provider_name
	notify.info("Switched to " .. provider.name .. " provider")
	return true
end

-- Get list of available providers
function M.get_available_providers()
	local providers = {}
	for name, provider in pairs(M.providers) do
		table.insert(providers, {
			name = name,
			display_name = provider.name,
			supports_chat = provider.supports_chat,
			supports_completion = provider.supports_completion,
			supports_fast_apply = provider.supports_fast_apply,
		})
	end
	return providers
end

-- Show provider selection menu
function M.show_provider_menu()
	local providers = M.get_available_providers()
	local items = {}

	for _, provider in ipairs(providers) do
		local status = provider.name == M.current_provider and " (current)" or ""
		local features = {}
		if provider.supports_chat then
			table.insert(features, "chat")
		end
		if provider.supports_completion then
			table.insert(features, "completion")
		end
		if provider.supports_fast_apply then
			table.insert(features, "fast-apply")
		end

		table.insert(items, string.format("%s%s - %s", provider.display_name, status, table.concat(features, ", ")))
	end

	vim.ui.select(items, {
		prompt = "Select AI Provider:",
	}, function(choice, idx)
		if choice and idx then
			local selected_provider = providers[idx]
			M.switch_provider(selected_provider.name)
		end
	end)
end

-- Make external API request (for non-windsurf providers)
function M.make_external_request(provider, messages, callback)
	local curl = require("plenary.curl")
	local provider_config = M.providers[provider]

	if not provider_config then
		callback(nil, { message = "Unknown provider: " .. provider })
		return
	end

	-- Get API key
	local api_key = vim.env[provider_config.api_key_env] or vim.env["AVANTE_" .. provider_config.api_key_env]
	if not api_key then
		callback(nil, { message = "API key not found for " .. provider_config.name })
		return
	end

	-- Prepare request based on provider
	local headers = {}
	local body = {}

	if provider == "claude" then
		headers = {
			["Content-Type"] = "application/json",
			["x-api-key"] = api_key,
			["anthropic-version"] = "2023-06-01",
		}
		body = {
			model = provider_config.model,
			max_tokens = 4096,
			messages = messages,
		}
	elseif provider == "openai" then
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. api_key,
		}
		body = {
			model = provider_config.model,
			messages = messages,
			max_tokens = 4096,
			temperature = 0.7,
		}
	elseif provider == "gemini" then
		headers = {
			["Content-Type"] = "application/json",
		}
		body = {
			contents = vim.tbl_map(function(msg)
				return {
					role = msg.role == "assistant" and "model" or "user",
					parts = { { text = msg.content } },
				}
			end, messages),
			generationConfig = {
				maxOutputTokens = 4096,
				temperature = 0.7,
			},
		}
	end

	-- Make request
	local url = provider_config.endpoint
	if provider == "gemini" then
		url = url .. "/models/" .. provider_config.model .. ":generateContent?key=" .. api_key
	else
		url = url .. "/chat/completions"
	end

	curl.post(url, {
		headers = headers,
		body = vim.json.encode(body),
		callback = function(response)
			if response.status ~= 200 then
				callback(nil, {
					message = "API request failed",
					status = response.status,
					body = response.body,
				})
				return
			end

			local ok, result = pcall(vim.json.decode, response.body)
			if not ok then
				callback(nil, { message = "Failed to decode response" })
				return
			end

			-- Extract response based on provider
			local content = ""
			if provider == "claude" then
				if result.content and #result.content > 0 then
					content = result.content[1].text
				end
			elseif provider == "openai" then
				if result.choices and #result.choices > 0 then
					content = result.choices[1].message.content
				end
			elseif provider == "gemini" then
				if result.candidates and #result.candidates > 0 then
					local candidate = result.candidates[1]
					if candidate.content and candidate.content.parts and #candidate.content.parts > 0 then
						content = candidate.content.parts[1].text
					end
				end
			end

			callback({
				completionItems = { {
					completion = { text = content },
				} },
			}, nil)
		end,
	})
end

-- Initialize providers
function M.setup()
	-- Set default provider based on config
	local default_provider = config.options.default_provider or "windsurf"
	if M.providers[default_provider] then
		M.current_provider = default_provider
	end
end

return M
