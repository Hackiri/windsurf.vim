-- Luacheck configuration for windsurf.nvim
std = "luajit"
cache = true

-- Global variables allowed
globals = {
  "vim",
}

-- Read-only globals
read_globals = {
  "vim",
}

-- Ignore certain warnings
ignore = {
  "212/_.*",     -- unused argument, for vars with "_" prefix
  "213",         -- unused loop variable
  "631",         -- line is too long
}

-- Files to exclude
exclude_files = {
  ".luarocks",
  ".install",
}

-- Maximum line length
max_line_length = 120

-- Maximum cyclomatic complexity
max_cyclomatic_complexity = 10
