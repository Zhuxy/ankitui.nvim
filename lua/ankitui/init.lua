local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local Snacks = require("snacks")
local EditPanel = require("ankitui.ui.edit_panel")
local api = require("ankitui.api")
local html = require("ankitui.html")

local M = {}

---@class Config
M.config = {
  anki_connect_url = "http://localhost:8765",
  anki_connect_api_key = "",
  new_cards_per_session = 5,
  max_cards_per_session = 20,
  log_to_file = false,
  keymaps = {
    again = "1",
    hard = "2",
    good = "3",
    easy = "4",
    show_session_cards = "<leader>s",
    flip_card = "<space>",
    edit_card = "e",
  },
}

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.config, user_config or {})
  api.setup(M.config)
end

-- Session state
M.current_session = {
  deck_name = nil,
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

-- Helper function to decode HTML entities
function M.decode_html_entities(lines)
  for i, line in ipairs(lines) do
    local text = line
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", "\"")
    text = text:gsub("&#39;", "'")
    lines[i] = text
  end
  return lines
end

-- Helper function to decode Unicode escape sequences
function M.decode_unicode_escapes(lines)
  for i, line in ipairs(lines) do
    local text = line
    text = text:gsub("\\u(%x%x%x%x)", function(hex)
      return vim.fn.nr2char(tonumber(hex, 16))

    end)
    lines[i] = text
  end
  return lines
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

    local question_parts = html.render(card_info.question)
    local answer_parts = html.render(card_info.answer)
    local question_text = table.concat(M.decode_unicode_escapes(M.decode_html_entities(question_parts)), "\n")
    local answer_text = table.concat(M.decode_unicode_escapes(M.decode_html_entities(answer_parts)), "\n")
    M.show_question_in_float_window(card_id, card_info.note, question_text, answer_text)
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

function M.start_review_session(deck_name)
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
  local function build_footer_hint(is_scroll_locked)
    local lock_state = is_scroll_locked and "on" or "off"
    return string.format("<leader>S (Save) | q (Quit without saving) | [L] Scroll lock: %s", lock_state)
  end

  local panel = EditPanel.create({
    question = { title = "Question", lines = M.split_into_lines(note_info.fields.Front.value or "") },
    answer = { title = "Answer", lines = M.split_into_lines(note_info.fields.Back.value or "") },
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.75),
    inner_width = math.floor(vim.o.columns * 0.76),
    pane_height = math.floor(vim.o.lines * 0.28),
    footer = { lines = { build_footer_hint(false) } },
  })

  panel.get_values = function()
    local question_lines = vim.api.nvim_buf_get_lines(panel.question, 0, -1, false)
    local answer_lines = vim.api.nvim_buf_get_lines(panel.answer, 0, -1, false)
    return {
      Front = { value = table.concat(question_lines, "\n") },
      Back = { value = table.concat(answer_lines, "\n") },
    }
  end

  local function save_and_close()
    local values = panel.get_values()
    local new_fields = {}
    for field_name, field_info in pairs(values) do
      new_fields[field_name] = field_info.value
    end

    M.update_note_fields(note_info.noteId, new_fields, function(success)
      if success then
        panel:close()
        vim.api.nvim_set_current_win(original_win_id)
      end
    end)
  end

  local function cancel_and_close()
    panel:close()
    vim.api.nvim_set_current_win(original_win_id)
  end

  panel.scroll_lock = false

  local function update_footer_hint()
    panel:set_footer({ build_footer_hint(panel.scroll_lock) })
  end

  local function sync_question_to_answer()
    if not panel.scroll_lock then
      return
    end
    local pos = vim.api.nvim_win_get_cursor(panel.question_win)[1]
    local ratio = pos / math.max(1, vim.api.nvim_buf_line_count(panel.question))
    local target = math.max(1, math.floor(ratio * vim.api.nvim_buf_line_count(panel.answer)))
    vim.api.nvim_win_set_cursor(panel.answer_win, { target, 0 })
  end

  local function sync_answer_to_question()
    if not panel.scroll_lock then
      return
    end
    local pos = vim.api.nvim_win_get_cursor(panel.answer_win)[1]
    local ratio = pos / math.max(1, vim.api.nvim_buf_line_count(panel.answer))
    local target = math.max(1, math.floor(ratio * vim.api.nvim_buf_line_count(panel.question)))
    vim.api.nvim_win_set_cursor(panel.question_win, { target, 0 })
  end

  local function focus_window(win)
    local mode = vim.api.nvim_get_mode().mode
    local was_insert = mode:sub(1, 1) == "i"
    vim.api.nvim_set_current_win(win)
    if was_insert then
      vim.cmd("startinsert!")
    end
  end

  local function focus_question_window()
    focus_window(panel.question_win)
  end

  local function focus_answer_window()
    focus_window(panel.answer_win)
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = panel.question,
    callback = sync_question_to_answer,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = panel.answer,
    callback = sync_answer_to_question,
  })

  local function toggle_focus()
    local current_win = vim.api.nvim_get_current_win()
    if current_win == panel.question_win then
      focus_answer_window()
    else
      focus_question_window()
    end
  end

  vim.keymap.set("n", "<Tab>", function()
    toggle_focus()
  end, { buffer = panel.question, nowait = true })
  vim.keymap.set("n", "<Tab>", function()
    toggle_focus()
  end, { buffer = panel.answer, nowait = true })
  vim.keymap.set("i", "<Tab>", function()
    toggle_focus()
    return ""
  end, { buffer = panel.question, nowait = true, expr = true })
  vim.keymap.set("i", "<Tab>", function()
    toggle_focus()
    return ""
  end, { buffer = panel.answer, nowait = true, expr = true })

  vim.keymap.set("n", "L", function()
    panel.scroll_lock = not panel.scroll_lock
    update_footer_hint()
  end, { buffer = panel.question, nowait = true })
  vim.keymap.set("n", "L", function()
    panel.scroll_lock = not panel.scroll_lock
    update_footer_hint()
  end, { buffer = panel.answer, nowait = true })

  vim.keymap.set("n", "<leader>S", save_and_close, { buffer = panel.question })
  vim.keymap.set("n", "<leader>S", save_and_close, { buffer = panel.answer })
  vim.keymap.set("n", "q", cancel_and_close, { buffer = panel.question })
  vim.keymap.set("n", "q", cancel_and_close, { buffer = panel.answer })

  if focused_field == "Back" then
    vim.api.nvim_set_current_win(panel.answer_win)
  else
    vim.api.nvim_set_current_win(panel.question_win)
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
      local question_parts = html.render(card_info.question)
      local question_text = M.decode_unicode_escapes(M.decode_html_entities(question_parts))
      local function strip_question_text(lines)
        local text = table.concat(lines, " ")
        text = text:gsub("%[Image%]", "")
        if #text > 100 then
          text = text:sub(1, 97) .. "..."
        end
        return text
      end
      local stripped_question_text = strip_question_text(question_text)
      table.insert(card_names, string.format("%d. %s", i, stripped_question_text))
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
    M.config.keymaps.flip_card,
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
        M.show_edit_window(note_info, nil, win.win)
      end
    end)
  end
  keys[M.config.keymaps.flip_card] = function()
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
    height = 0.7,
    relative = "editor",
    row = 0.15,
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
    row = 0.85,
    col = 0.1,
    focusable = false,
    zindex = 100,
  })
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
          M.start_review_session(selected_deck)
        end)
        return true
      end,
    }):find()
  end)
end

return M
