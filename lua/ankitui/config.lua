local M = {}

local config_dir = vim.fn.stdpath("data") .. "/ankitui"
vim.fn.mkdir(config_dir, "p")
local config_path = config_dir .. "/deck_config.json"

function M.load_config()
  local f = io.open(config_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, config = pcall(vim.fn.json_decode, content)
    if ok then
      return config
    end
  end
  return {}
end

function M.save_config(config)
  local f = io.open(config_path, "w")
  if f then
    f:write(vim.fn.json_encode(config))
    f:close()
  end
end

function M.clear_config()
  local f = io.open(config_path, "w")
  if f then
    f:write("{}") -- Write an empty JSON object to clear the config
    f:close()
    vim.notify("AnkiTUI configuration cleared.", vim.log.levels.INFO)
  else
    vim.notify("Failed to clear AnkiTUI configuration.", vim.log.levels.ERROR)
  end
end

return M