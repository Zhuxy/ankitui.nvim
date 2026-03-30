local Snacks = require("snacks")
local M = {}

local function safe_close(target)
  if target and target.close then
    pcall(target.close, target)
  end
end

---@param opts {question:{title:string,lines:string[]}, answer:{title:string,lines:string[]}, width:number, height:number, inner_width:number, pane_height:number, footer:{lines:string[], keys:table}}
function M.create(opts)
  opts = opts or {}
  local question_opts = opts.question or {}
  local answer_opts = opts.answer or {}
  local footer_opts = opts.footer or { lines = {}, keys = {} }
  local question_lines = question_opts.lines or {}
  local answer_lines = answer_opts.lines or {}
  local footer_lines = footer_opts.lines or {}
  local footer_keys = footer_opts.keys or {}

  local wrapper = Snacks.win({
    border = "rounded",
    width = opts.width,
    height = opts.height,
    relative = "editor",
    row = math.floor((vim.o.lines - opts.height) / 2),
    col = math.floor((vim.o.columns - opts.width) / 2),
    focusable = true,
    zindex = 120,
  })

  local panel = { wrapper = wrapper }
  panel.question = vim.api.nvim_create_buf(false, true)
  panel.answer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(panel.question, 0, -1, false, question_lines)
  vim.api.nvim_buf_set_lines(panel.answer, 0, -1, false, answer_lines)
  vim.bo[panel.question].bufhidden = "wipe"
  vim.bo[panel.answer].bufhidden = "wipe"

  panel.question_win = vim.api.nvim_open_win(panel.question, true, {
    relative = "win",
    win = wrapper.win,
    row = 1,
    col = 2,
    width = opts.inner_width,
    height = opts.pane_height,
    border = "rounded",
    title = question_opts.title,
    zindex = 121,
  })
  panel.answer_win = vim.api.nvim_open_win(panel.answer, false, {
    relative = "win",
    win = wrapper.win,
    row = opts.pane_height + 3,
    col = 2,
    width = opts.inner_width,
    height = opts.pane_height,
    border = "rounded",
    title = answer_opts.title,
    zindex = 121,
  })

  panel.footer = Snacks.win({
    text = footer_lines,
    border = "rounded",
    width = opts.inner_width,
    height = 3,
    relative = "win",
    win = wrapper.win,
    row = opts.height - 4,
    col = 2,
    focusable = false,
    zindex = 121,
    keys = footer_keys,
  })

  function panel:set_footer(lines)
    vim.api.nvim_buf_set_lines(self.footer.buf, 0, -1, false, lines)
  end

  function panel:get_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  function panel:close()
    if self.question_win and vim.api.nvim_win_is_valid(self.question_win) then
      vim.api.nvim_win_close(self.question_win, true)
    end
    if self.answer_win and vim.api.nvim_win_is_valid(self.answer_win) then
      vim.api.nvim_win_close(self.answer_win, true)
    end
    safe_close(wrapper)
    safe_close(self.footer)
    if vim.api.nvim_buf_is_valid(self.question) then
      vim.api.nvim_buf_delete(self.question, { force = true })
    end
    if vim.api.nvim_buf_is_valid(self.answer) then
      vim.api.nvim_buf_delete(self.answer, { force = true })
    end
  end

  return panel
end

return M
