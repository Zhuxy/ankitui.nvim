local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local Snacks = require("snacks")
local config = require("ankitui.config")
local api = require("ankitui.api")

math.randomseed(os.time())

local M = {}

M.config = {
  new_cards_per_session = 5,
  max_cards_per_session = 20,
  log_to_file = false,
  keymaps = {
    again = "1",
    hard = "2",
    good = "3",
    easy = "4",
    show_session_cards = "<leader>s",
    toggle_qa = "<space>",
    edit_card = "e",
  },
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
  api.send_request("deckNames", {}, callback)
end

function M.get_field_names(deck_name, callback)
  api.send_request("findNotes", { query = "deck:\"" .. deck_name .. "\"" }, function(notes)
    if not notes or #notes == 0 then
      callback(nil)
      return
    end

    local note_id = notes[1]
    api.send_request("notesInfo", { notes = { note_id } }, function(note_info_result)
      if not note_info_result or #note_info_result == 0 then
        callback(nil)
        return
      end

      local note_info = note_info_result[1]
      local field_names = {}
      for k, _ in pairs(note_info.fields) do
        table.insert(field_names, k)
      end
      callback(field_names)
    end)
  end)
end

function M.answer_cards(answers, callback)
  api.send_request("answerCards", { answers = answers }, function(result)
    callback(result ~= nil)
  end)
end

function M.show_next_card_in_session()
  if #M.current_session.card_ids == 0 then
    vim.notify("No more new cards in this deck. Session finished!")
    return
  end

  local card_id = table.remove(M.current_session.card_ids, 1)
  api.send_request("cardsInfo", { cards = { card_id } }, function(card_info_result)
    if not card_info_result or #card_info_result == 0 then
      vim.notify("Failed to get card info for card ID: " .. card_id, vim.log.levels.ERROR)
      return
    end

    local card_info = card_info_result[1]
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
    M.show_question_in_float_window(card_id, card_info.note, cleaned_question, cleaned_answer)
  end)
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
    api.send_request("findCards", { query = query }, function(result)
      if result and type(result) == "table" then
        for _, card_id in ipairs(result) do
          table.insert(all_card_ids, card_id)
        end
      end
      callback()
    end)
  end

  local queries = {
    string.format("deck:\"%s\" is:new", deck_name), -- new
    string.format("deck:\"%s\" is:learn", deck_name), -- learning
    string.format("deck:\"%s\" is:due -is:learn", deck_name), -- due
  }

  local function fetch_all_cards(index)
    if index > #queries then
      if #all_card_ids == 0 then
        vim.notify("No cards to study in deck: " .. deck_name, vim.log.levels.INFO)
        return
      end

      local new_cards_query = string.format("deck:\"%s\" is:new", deck_name)
      api.send_request("findCards", { query = new_cards_query }, function(new_cards_result)
        local new_cards = new_cards_result or {}
        local limited_new_cards = {}
        for i = 1, math.min(M.config.new_cards_per_session, #new_cards) do
          table.insert(limited_new_cards, new_cards[i])
        end

        local other_cards = {}
        for _, card_id in ipairs(all_card_ids) do
          if not vim.tbl_contains(new_cards, card_id) then
            table.insert(other_cards, card_id)
          end
        end

        local combined_cards = vim.list_extend(other_cards, limited_new_cards)
        local final_cards = {}
        for i = 1, math.min(M.config.max_cards_per_session, #combined_cards) do
          table.insert(final_cards, combined_cards[i])
        end

        M.current_session.deck_name = deck_name
        M.current_session.deck_config = deck_config
        M.current_session.card_ids = shuffle_table(get_unique_cards(final_cards))
        M.show_next_card_in_session()
      end)
      return
    end

    fetch_cards(queries[index], function()
      fetch_all_cards(index + 1)
    end)
  end

  fetch_all_cards(1)
end

function M.get_note_info(note_id, callback)
  api.send_request("notesInfo", { notes = { note_id } }, function(result)
    if not result or #result == 0 then
      callback(nil)
      return
    end
    callback(result[1])
  end)
end

function M.update_note_fields(note_id, fields, callback)
  api.send_request("updateNoteFields", { note = { id = note_id, fields = fields } }, function(result)
    if result then
      vim.notify("Card updated successfully!", vim.log.levels.INFO)
      callback(true)
    else
      vim.notify("AnkiConnect updateNoteFields failed.", vim.log.levels.ERROR)
      callback(false)
    end
  end)
end

function M.set_save_and_close(fn)
  M.save_and_close = fn
end

function M.set_cancel_and_close(fn)
  M.cancel_and_close = fn
end

function M.show_edit_window(note_info, focused_field, original_win_id)
  local bufs = {}
  local wins = {}
  local field_keys = {}
  for k, _ in pairs(note_info.fields) do
    table.insert(field_keys, k)
  end
  table.sort(field_keys)

  local win_heights = {}
  local total_height = 0
  local min_field_height = 5 -- Minimum lines for each field
  local field_padding = 2 -- Lines between fields

  for _, field_name in ipairs(field_keys) do
    local content_lines = #M.split_into_lines(note_info.fields[field_name].value)
    local height = math.max(min_field_height, content_lines + 4) -- +4 for padding/border
    table.insert(win_heights, height)
    total_height = total_height + height + field_padding
  end

  -- Adjust total height to fit within 80% of screen height
  local max_total_height = math.floor(vim.o.lines * 0.8)
  if total_height > max_total_height then
    local scale_factor = max_total_height / total_height
    total_height = 0
    for i, height in ipairs(win_heights) do
      win_heights[i] = math.max(min_field_height, math.floor(height * scale_factor))
      total_height = total_height + win_heights[i] + field_padding
    end
  end

  local current_row = math.floor(vim.o.lines * 0.1)
  local focused_win = nil

  local function save_and_close()
    local new_fields = {}
    for i, field_name in ipairs(field_keys) do
      local lines = vim.api.nvim_buf_get_lines(bufs[i], 0, -1, false)
      new_fields[field_name] = table.concat(lines, "\n")
    end

    M.update_note_fields(note_info.noteId, new_fields, function(success)
      if success then
        for _, win_id in ipairs(wins) do
          vim.api.nvim_win_close(win_id, true)
        end
        for _, buf in ipairs(bufs) do
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        vim.api.nvim_set_current_win(original_win_id)
      end
    end)
  end

  local function cancel_and_close()
    for _, win_id in ipairs(wins) do
      vim.api.nvim_win_close(win_id, true)
    end
    for _, buf in ipairs(bufs) do
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.api.nvim_set_current_win(original_win_id)
  end

  for i, field_name in ipairs(field_keys) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.split_into_lines(note_info.fields[field_name].value))
    table.insert(bufs, buf)

    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = math.floor(vim.o.columns * 0.8),
      height = win_heights[i],
      row = current_row,
      col = math.floor(vim.o.columns * 0.1),
      border = "rounded",
      title = field_name,
      zindex = 101,
    })
    table.insert(wins, win)
    if field_name == focused_field then
      focused_win = win
    end
    vim.api.nvim_buf_set_keymap(buf, "n", "<leader>S", ":lua require('ankitui').save_and_close()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('ankitui').cancel_and_close()<CR>", { noremap = true, silent = true })
    current_row = current_row + win_heights[i] + field_padding
  end

  local hint_text = "<leader>S (Save) | q (Quit without saving)"
  local hint_win = Snacks.win({
    text = hint_text,
    border = "rounded",
    width = math.floor(vim.o.columns * 0.8),
    height = 3,
    relative = "editor",
    row = current_row + 1,
    col = math.floor(vim.o.columns * 0.1),
    focusable = false,
    zindex = 101,
  })
  table.insert(wins, hint_win.win)

  if focused_win then
    vim.api.nvim_set_current_win(focused_win)
  end

  M.set_save_and_close(save_and_close)
  M.set_cancel_and_close(cancel_and_close)
end


function M.show_confirmation_dialog(prompt, callback)
  local confirm_win

  local function close_win()
    if confirm_win and confirm_win.win and vim.api.nvim_win_is_valid(confirm_win.win) then
      confirm_win:close()
    end
  end

  confirm_win = Snacks.win({
    text = { prompt, "", "(y)es / (n)o" },
    border = "rounded",
    width = 0.4,
    height = 5,
    relative = "editor",
    row = 0.4,
    col = 0.3,
    focusable = true,
    zindex = 102,
    keys = {
      ["y"] = function()
        close_win()
        callback(true)
      end,
      ["n"] = function()
        close_win()
        callback(false)
      end,
      ["<esc>"] = function()
        close_win()
        callback(false)
      end,
    },
  })
end


function M.show_session_cards()
  if #M.current_session.card_ids == 0 then
    vim.notify("No cards in the current session.", vim.log.levels.INFO)
    return
  end

  api.send_request("cardsInfo", { cards = M.current_session.card_ids }, function(cards_info)
    if not cards_info then
      vim.notify("Failed to get session cards info.", vim.log.levels.ERROR)
      return
    end

    local card_names = {}
    for i, card_info in ipairs(cards_info) do
      local question_parts = {}
      for _, field_name in ipairs(M.current_session.deck_config.question_fields) do
        table.insert(question_parts, card_info.fields[field_name].value)
      end
      local question_text = table.concat(question_parts, " ")
      local cleaned_question = M.decode_unicode_escapes(M.strip_html_tags(M.decode_html_entities(question_text)))
      cleaned_question = cleaned_question:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
      table.insert(card_names, string.format("%d. %s", i, cleaned_question))
    end

    local session_win
    session_win = Snacks.win({
      text = card_names,
      border = "rounded",
      width = 0.8,
      height = 0.8,
      relative = "editor",
      row = 0.1,
      col = 0.1,
      focusable = true,
      zindex = 101,
      wo = {
        wrap = true,
      },
      keys = {
        ["q"] = function()
          session_win:close()
        end,
        ["<esc>"] = function()
          session_win:close()
        end,
      },
    })
  end)
end

function M.show_question_in_float_window(card_id, note_id, question_text, answer_text)
  if not Snacks then
    vim.notify("Error: snacks.nvim is not loaded.", vim.log.levels.ERROR)
    return
  end

  local card = { id = card_id, note_id = note_id, question = question_text, answer = answer_text, showing_question = true }
  local win
  local hint_win

  local hint_text = string.format(
    "%s(again)  %s(hard)  %s(good)  %s(easy) | %s(toggle) | %s(list cards) | %s(edit card)",
    M.config.keymaps.again,
    M.config.keymaps.hard,
    M.config.keymaps.good,
    M.config.keymaps.easy,
    M.config.keymaps.toggle_qa,
    M.config.keymaps.show_session_cards,
    M.config.keymaps.edit_card
  )

  local function handle_answer(ease)
    M.answer_cards({ { cardId = card.id, ease = ease } }, function(success)
      if success then
        win:close()
        if hint_win then
          hint_win:close()
        end
        M.show_next_card_in_session()
      end
    end)
  end

  local keys = {}
  keys[M.config.keymaps.show_session_cards] = function()
    M.show_session_cards()
  end
  keys[M.config.keymaps.edit_card] = function()
    M.get_note_info(card.note_id, function(note_info)
      if note_info then
        local focused_field = card.showing_question
            and M.current_session.deck_config.question_fields[1]
            or M.current_session.deck_config.answer_fields[1]
        M.show_edit_window(note_info, focused_field, win.win)
      end
    end)
  end
  keys[M.config.keymaps.toggle_qa] = function()
    if card.showing_question then
      vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, M.split_into_lines(card.answer))
      card.showing_question = false
    else
      vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, M.split_into_lines(card.question))
      card.showing_question = true
    end
  end
  keys[M.config.keymaps.again] = function() handle_answer(1) end
  keys[M.config.keymaps.hard] = function() handle_answer(2) end
  keys[M.config.keymaps.good] = function() handle_answer(3) end
  keys[M.config.keymaps.easy] = function() handle_answer(4) end
  keys["<esc>"] = function()
    M.show_confirmation_dialog("Exit review session?", function(confirmed)
      if confirmed then
        win:close()
        if hint_win then
          hint_win:close()
        end
        M.current_session = {
          deck_name = nil,
          deck_config = nil,
          card_ids = {},
        }
        vim.notify("Review session ended.", vim.log.levels.INFO)
        M.show_confirmation_dialog("Sync with Anki server?", function(sync_confirmed)
          if sync_confirmed then
            require("ankitui.api").sync()
          end
        end)
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
    wo = {
      wrap = true,
    },
    keys = keys,
  })


  hint_win = Snacks.win({
    text = hint_text,
    border = "rounded",
    width = 0.8,
    height = 3,
    relative = "editor",
    row = 0.7,
    col = 0.1,
    focusable = false,
    zindex = 100,
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
      attach_mappings = function(prompt_bufnr, _)
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
