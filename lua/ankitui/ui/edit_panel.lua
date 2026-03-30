local Snacks = require("snacks")
local M = {}

---@param opts {question:{title:string,lines:string[]}, answer:{title:string,lines:string[]}, width:number, height:number, inner_width:number, pane_height:number, footer:{lines:string[], keys:table}}
function M.create(opts)
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
  panel.question = vim.api.nvim_create_buf(true, false)
  panel.answer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(panel.question, 0, -1, false, opts.question.lines)
  vim.api.nvim_buf_set_lines(panel.answer, 0, -1, false, opts.answer.lines)

  panel.question_win = vim.api.nvim_open_win(panel.question, true, {
    relative = "win",
    win = wrapper.win,
    row = 1,
    col = 2,
    width = opts.inner_width,
    height = opts.pane_height,
    border = "rounded",
    title = opts.question.title,
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
    title = opts.answer.title,
    zindex = 121,
  })

  panel.footer = Snacks.win({
    text = opts.footer.lines,
    border = "rounded",
    width = opts.inner_width,
    height = 3,
    relative = "win",
    win = wrapper.win,
    row = opts.height - 4,
    col = 2,
    focusable = false,
    zindex = 121,
    keys = opts.footer.keys,
  })

  function panel:set_footer(lines)
    vim.api.nvim_buf_set_lines(self.footer.buf, 0, -1, false, lines)
  end

  function panel:get_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  function panel:close()
    wrapper:close()
    Snacks.safe_close(self.footer)
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
