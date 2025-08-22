local ankitui = require("ankitui")

vim.api.nvim_create_user_command(
  "AnkiStartLearning",
  function() ankitui.start_learning_flow() end,
  { nargs = 0, desc = "Start an Anki learning session" }
)
