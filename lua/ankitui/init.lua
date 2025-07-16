local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local Snacks = require("snacks")
local config = require("ankitui.config")

math.randomseed(os.time())

local M = {}

M.config = {
  new_cards_per_session = 20,
  log_to_file = false,
}

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.config, user_config or {})
end

-- Session state
M.current_session = {
  deck_name = nil,
  deck_config = nil,
  card_ids = {},
}

-- Log file path
local LOG_FILE = vim.fn.stdpath("cache") .. "/ankitui_anki_connect.log"

-- Helper function to shuffle a table
local function shuffle_table(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

-- Helper function for logging AnkiConnect calls
function M.log_anki_connect_call(type, details)
  if not M.config.log_to_file then
    return
  end
  local log_entry = os.date("%Y-%m-%d %H:%M:%S") .. " [" .. type .. "]\n"
  for k, v in pairs(details) do
    log_entry = log_entry .. "  " .. tostring(k) .. ": " .. tostring(v) .. "\n"
  end
  log_entry = log_entry .. "\n"
  vim.fn.writefile({ log_entry }, LOG_FILE, "a")
end

-- Helper function to strip HTML tags
function M.strip_html_tags(text)
  text = text:gsub("<br%s*/>", "\n")
  text = text:gsub("<br>", "\n")
  text = text:gsub("<div>", "\n")
  text = text:gsub("</div>", "")
  text = text:gsub("<[^>]+>", "")
  return text
end

-- Helper function to decode HTML entities
function M.decode_html_entities(text)
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&quot;", "\"")
  text = text:gsub("&#39;", "'")
  return text
end

-- Helper function to decode Unicode escape sequences
function M.decode_unicode_escapes(text)
  return text:gsub("\\u(%x%x%x%x)", function(hex)
    return vim.fn.nr2char(tonumber(hex, 16))

  end)
end

-- Helper function to split string into lines
function M.split_into_lines(text)
  local lines = {}
  for line in text:gmatch("([^\n]*)") do
    table.insert(lines, line)
  end
  return lines
end

function M.get_deck_names(callback)
  local command = {
    "curl",
    "-s",
    "http://localhost:8765",
    "-X",
    "POST",
    "-d",
    '{"action": "deckNames", "version": 6}',
  }
  local stdout_chunks = {}
  local stderr_chunks = {}
  M.log_anki_connect_call("REQUEST", { action = "deckNames", command = table.concat(command, " ") })
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
      local response_body = table.concat(stdout_chunks)
      M.log_anki_connect_call("RESPONSE", { action = "deckNames", exit_code = exit_code, stdout = response_body, stderr = table.concat(stderr_chunks) })
      if exit_code ~= 0 then
        vim.notify("AnkiConnect request failed: " .. table.concat(stderr_chunks), vim.log.levels.ERROR)
        callback(nil)
        return
      end
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

function M.get_field_names(deck_name, callback)
  local find_notes_command = { "curl", "-s", "http://localhost:8765", "-X", "POST", "-d", vim.fn.json_encode({ action = "findNotes", version = 6, params = { query = "deck:\"" .. deck_name .. "\"" } }) }
  local stdout = {}
  vim.fn.jobstart(find_notes_command, {
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stdout, chunk)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        callback(nil)
        return
      end
      local response = vim.fn.json_decode(table.concat(stdout))
      if not response or not response.result or #response.result == 0 then
        callback(nil)
        return
      end
      local note_id = response.result[1]
      local notes_info_command = { "curl", "-s", "http://localhost:8765", "-X", "POST", "-d", vim.fn.json_encode({ action = "notesInfo", version = 6, params = { notes = { note_id } } }) }
      local info_stdout = {}
      vim.fn.jobstart(notes_info_command, {
        on_stdout = function(_, data)
          for _, chunk in ipairs(data) do
            if chunk ~= "" then
              table.insert(info_stdout, chunk)
            end
          end
        end,
        on_exit = function(_, info_exit_code)
          if info_exit_code ~= 0 then
            callback(nil)
            return
          end
          local note_info_response = vim.fn.json_decode(table.concat(info_stdout, "\n"))
          if not note_info_response or not note_info_response.result or #note_info_response.result == 0 then
            callback(nil)
            return
          end
          local note_info = note_info_response.result[1]
          local field_names = {}
          for k, _ in pairs(note_info.fields) do
            table.insert(field_names, k)
          end
          callback(field_names)
        end,
      })
    end,
  })
end

function M.answer_cards(answers, callback)
  local command = { "curl", "-s", "http://localhost:8765", "-X", "POST", "-d", vim.fn.json_encode({ action = "answerCards", version = 6, params = { answers = answers } }) }
  vim.fn.jobstart(command, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        callback(true)
      else
        vim.notify("AnkiConnect answerCards failed.", vim.log.levels.ERROR)
        callback(false)
      end
    end,
  })
end

function M.show_next_card_in_session()
  if #M.current_session.card_ids == 0 then
    vim.notify("No more new cards in this deck. Session finished!")
    return
  end

  local card_id = table.remove(M.current_session.card_ids, 1)

  local cards_info_command = { "curl", "-s", "http://localhost:8765", "-X", "POST", "-d", vim.fn.json_encode({ action = "cardsInfo", version = 6, params = { cards = { card_id } } }) }
  local stdout = {}
  vim.fn.jobstart(cards_info_command, {
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stdout, chunk)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("AnkiConnect cardsInfo failed.", vim.log.levels.ERROR)
        return
      end
      local card_info_response = vim.fn.json_decode(table.concat(stdout, "\n"))
      if not card_info_response or not card_info_response.result or #card_info_response.result == 0 then
        vim.notify("Failed to get card info for card ID: " .. card_id, vim.log.levels.ERROR)
        return
      end
      local card_info = card_info_response.result[1]
      local question_parts = {}
      for _, field_name in ipairs(M.current_session.deck_config.question_fields) do
        table.insert(question_parts, card_info.fields[field_name].value)
      end
      local question_text = table.concat(question_parts, "\n\n")
      local answer_parts = {}
      for _, field_name in ipairs(M.current_session.deck_config.answer_fields) do
        table.insert(answer_parts, card_info.fields[field_name].value)
      end
      local answer_text = table.concat(answer_parts, "\n\n")
      local cleaned_question = M.decode_unicode_escapes(M.strip_html_tags(M.decode_html_entities(question_text)))
      local cleaned_answer = M.decode_unicode_escapes(M.strip_html_tags(M.decode_html_entities(answer_text)))
      M.show_question_in_float_window(card_id, cleaned_question, cleaned_answer)
    end,
  })
end

local function get_unique_cards(cards)
  local seen = {}
  local unique_cards = {}
  for _, card_id in ipairs(cards) do
    if not seen[card_id] then
      table.insert(unique_cards, card_id)
      seen[card_id] = true
    end
  end
  return unique_cards
end

function M.start_review_session(deck_name, deck_config)
  local all_card_ids = {}

  local function fetch_cards(query, callback)
    local params = { query = query }
    local find_cards_command = { "curl", "-s", "http://localhost:8765", "-X", "POST", "-d", vim.fn.json_encode({ action = "findCards", version = 6, params = params }) }
    local stdout = {}
    vim.fn.jobstart(find_cards_command, {
      on_stdout = function(_, data)
        for _, chunk in ipairs(data) do
          if chunk ~= "" then
            table.insert(stdout, chunk)
          end
        end
      end,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          vim.notify("AnkiConnect findCards failed for query: " .. query, vim.log.levels.ERROR)
          callback()
          return
        end
        local response_body = table.concat(stdout)
        if response_body == "" then
          callback()
          return
        end
        local ok, response = pcall(vim.fn.json_decode, response_body)
        if not ok then
          vim.notify("AnkiConnect: Failed to decode JSON for findCards: " .. tostring(response), vim.log.levels.ERROR)
          callback()
          return
        end
        if response.error and response.error ~= vim.NIL then
          vim.notify("AnkiConnect API error for findCards: " .. tostring(response.error), vim.log.levels.ERROR)
          callback()
          return
        end
        if response and response.result and type(response.result) == "table" then
          for _, card_id in ipairs(response.result) do
            table.insert(all_card_ids, card_id)
          end
        end
        callback()
      end,
    })
  end

  local queries = {
    string.format("deck:\"%s\" is:learn", deck_name),
    string.format("deck:\"%s\" is:review", deck_name),
    string.format("deck:\"%s\" is:new", deck_name),
  }

  local function fetch_all_cards(index)
    if index > #queries then
      if #all_card_ids == 0 then
        vim.notify("No cards to study in deck: " .. deck_name, vim.log.levels.INFO)
        return
      end

      local new_cards_query = string.format("deck:\"%s\" is:new", deck_name)
      if queries[index - 1] == new_cards_query then
        local new_cards = {}
        for _, card_id in ipairs(all_card_ids) do
          if vim.tbl_contains(M.current_session.card_ids, card_id) then
            -- card is not new
          else
            table.insert(new_cards, card_id)
          end
        end
        local limited_new_cards = {}
        for i = 1, math.min(M.config.new_cards_per_session, #new_cards) do
          table.insert(limited_new_cards, new_cards[i])
        end
        all_card_ids = vim.list_extend(M.current_session.card_ids, limited_new_cards)
      end

      M.current_session.deck_name = deck_name
      M.current_session.deck_config = deck_config
      M.current_session.card_ids = shuffle_table(get_unique_cards(all_card_ids))
      M.show_next_card_in_session()
      return
    end

    fetch_cards(queries[index], function()
      fetch_all_cards(index + 1)
    end)
  end

  fetch_all_cards(1)
end

function M.show_question_in_float_window(card_id, question_text, answer_text)
  if not Snacks then
    vim.notify("Error: snacks.nvim is not loaded.", vim.log.levels.ERROR)
    return
  end

  local card = { id = card_id, question = question_text, answer = answer_text, showing_question = true }
  local win

  local answer_lines = M.split_into_lines(card.answer)
  table.insert(answer_lines, "")
  table.insert(answer_lines, "1(again)  2(hard)  3(good)  4(easy)")

  local function handle_answer(ease)
    M.answer_cards({ { cardId = card.id, ease = ease } }, function(success)
      if success then
        win:close()
        M.show_next_card_in_session()
      end
    end)
  end

  win = Snacks.win({
    text = M.split_into_lines(question_text),
    border = "rounded",
    width = 0.8,
    height = 0.4,
    relative = "editor",
    row = 0.3,
    col = 0.1,
    focusable = true,
    zindex = 100,
    wo ={
      wrap = true,
    },
    keys = {
      ["<space>"] = function()
        if card.showing_question then
          vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, answer_lines)
          card.showing_question = false
        else
          vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, M.split_into_lines(card.question))
          card.showing_question = true
        end
      end,
      ["1"] = function() handle_answer(1) end,
      ["2"] = function() handle_answer(2) end,
      ["3"] = function() handle_answer(3) end,
      ["4"] = function() handle_answer(4) end,
      ["<esc>"] = function()
        local choice = vim.fn.confirm("Exit review session?", "&Yes\n&No", 2)
        if choice == 1 then
          win:close()
          M.current_session = {
            deck_name = nil,
            deck_config = nil,
            card_ids = {},
          }
          vim.notify("Review session ended.", vim.log.levels.INFO)
        end
      end,
    },
  })
end

function M.configure_deck(deck_name, callback)
  M.get_field_names(deck_name, function(field_names)
    if not field_names or #field_names == 0 then
      vim.notify("Could not get field names for deck: " .. deck_name, vim.log.levels.ERROR)
      callback(nil)
      return
    end
    pickers.new({
      prompt_title = "Select Question Fields for " .. deck_name .. " (use <Tab> to select multiple)",
      finder = finders.new_table({ results = field_names, entry_maker = function(entry) return { value = entry, display = entry, ordinal = entry } end }),
      sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
      attach_mappings = function(prompt_bufnr, map)
        map("i", "<Tab>", actions.toggle_selection + actions.move_selection_next)
        map("n", "<Tab>", actions.toggle_selection + actions.move_selection_next)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()
          actions.close(prompt_bufnr)
          if #selections == 0 then
            vim.notify("No fields selected for question.", vim.log.levels.WARN)
            callback(nil)
            return
          end
          local question_fields = {}
          for _, selection in ipairs(selections) do
            table.insert(question_fields, selection.value)
          end

          pickers.new({
            prompt_title = "Select Answer Fields for " .. deck_name .. " (use <Tab> to select multiple)",
            finder = finders.new_table({ results = field_names, entry_maker = function(entry) return { value = entry, display = entry, ordinal = entry } end }),
            sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
            attach_mappings = function(prompt_bufnr2, map2)
              map2("i", "<Tab>", actions.toggle_selection + actions.move_selection_next)
              map2("n", "<Tab>", actions.toggle_selection + actions.move_selection_next)
              actions.select_default:replace(function()
                local picker2 = action_state.get_current_picker(prompt_bufnr2)
                local selections2 = picker2:get_multi_selection()
                actions.close(prompt_bufnr2)
                if #selections2 == 0 then
                  vim.notify("No fields selected for answer.", vim.log.levels.WARN)
                  callback(nil)
                  return
                end
                local answer_fields = {}
                for _, selection in ipairs(selections2) do
                  table.insert(answer_fields, selection.value)
                end
                callback({ question_fields = question_fields, answer_fields = answer_fields })
              end)
              return true
            end,
          }):find()
        end)
        return true
      end,
    }):find()
  end)
end

function M.start_learning_flow()
  M.get_deck_names(function(decks)
    if not decks or #decks == 0 then
      vim.notify("No decks found.", vim.log.levels.INFO)
      return
    end
    pickers.new({}, {
      prompt_title = "Select Anki Deck",
      finder = finders.new_table({ results = decks, entry_maker = function(entry) return { value = entry, display = entry, ordinal = entry } end }),
      sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          local selected_deck = selection.value
          local all_configs = config.load_config()
          local deck_config = all_configs[selected_deck]
          if not deck_config then
            M.configure_deck(selected_deck, function(new_deck_config)
              if new_deck_config then
                all_configs[selected_deck] = new_deck_config
                config.save_config(all_configs)
                M.start_review_session(selected_deck, new_deck_config)
              end
            end)
          else
            M.start_review_session(selected_deck, deck_config)
          end
        end)
        return true
      end,
    }):find()
  end)
end

return M
