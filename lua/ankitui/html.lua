local M = {}
local ts = vim.treesitter

M.render = function(html)
  local query = ts.query.parse("html", [[
    (text) @text
    (element (start_tag (tag_name) @tag))
    (self_closing_tag (tag_name) @self_tag)
  ]])

  -- a temporary buffer for Treesitter
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(html, "\n"))

  local parser = ts.get_parser(bufnr, "html")
  local tree = parser:parse()[1]
  local root = tree:root()

  local result = {}

  local function add_line(s)
    if s == "\n" then
      table.insert(result, "")
    elseif s:match("\n") then
      for line in s:gmatch("[^\n]+") do
        table.insert(result, line)
      end
    else
      -- if result is empty or the last line is just a line break
      if #result == 0 then
        table.insert(result, s)
      else
        result[#result] = result[#result] .. s
      end
    end
  end

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]

    if name == "text" then
      local text = ts.get_node_text(node, bufnr)
      if text and text:match("%S") then
        add_line(text)
      end

    elseif name == "tag" or name == "self_tag" then
      local tagname = ts.get_node_text(node, bufnr)
      if tagname == "br" then
        add_line("\n")
      elseif tagname == "hr" then
        add_line("\n")
        add_line("----")
        add_line("\n")
      elseif tagname == "div" then
        add_line("\n")
      elseif tagname == "img" then
        add_line("[Image]")
        add_line("\n")
      end
    end
  end

  vim.api.nvim_buf_delete(bufnr, { force = true })

  -- remove leading and trailing empty lines
  while #result > 0 and result[1] == "" do table.remove(result, 1) end
  while #result > 0 and result[#result] == "" do table.remove(result) end

  return result
end

return M
