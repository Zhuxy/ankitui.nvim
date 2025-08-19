local M = {}

local anki_connect_url = "http://localhost:8765"
local anki_connect_api_key = ""

function M.setup(config)
  anki_connect_url = config.anki_connect_url
  anki_connect_api_key = config.anki_connect_api_key
end

function M.send_request(action, params, callback)
  local final_params = params
  if next(params) == nil then
    final_params = vim.empty_dict()
  end

  local request_data = {
    action = action,
    version = 6,
    params = final_params,
  }

  if anki_connect_api_key and anki_connect_api_key ~= "" then
    request_data.key = anki_connect_api_key
  end

  local request_body = vim.fn.json_encode(request_data)

  local command = {
    "curl",
    "-s",
    "-X",
    "POST",
    "-d",
    request_body,
    "--connect-timeout",
    "5",
    "--retry",
    "3",
    "--retry-delay",
    "1",
    anki_connect_url,
  }

  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(command, {
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stdout_chunks, chunk)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stderr_chunks, chunk)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        if exit_code == 7 then
          vim.notify(
            "Failed to connect to Anki. Please ensure Anki is running and anki-connect is installed.",
            vim.log.levels.ERROR
          )
        else
          vim.notify("AnkiConnect request failed: " .. table.concat(stderr_chunks), vim.log.levels.ERROR)
        end
        callback(nil)
        return
      end

      local response_body = table.concat(stdout_chunks)
      if response_body == "" then
        vim.notify("AnkiConnect request failed: Empty response.", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, response_body)
      if not ok then
        vim.notify("AnkiConnect: Failed to decode JSON: " .. tostring(decoded), vim.log.levels.ERROR)
        callback(nil)
        return
      end

      if decoded.error and decoded.error ~= vim.NIL then
        vim.notify("AnkiConnect API error: " .. tostring(decoded.error), vim.log.levels.ERROR)
        callback(nil)
        return
      end

      callback(decoded.result)
    end,
  })
end

function M.sync(callback)
  M.send_request("sync", {}, function(result)
    if result then
      vim.notify("Anki sync completed successfully.", vim.log.levels.INFO)
    else
      vim.notify("Anki sync failed.", vim.log.levels.ERROR)
    end
    if callback then
      callback(result ~= nil)
    end
  end)
end

return M