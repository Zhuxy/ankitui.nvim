vim.api.nvim_create_user_command(
  "AnkiStartLearning",
  function() require("ankitui").start_learning_flow() end,
  { nargs = 0, desc = "Start an Anki learning session" }
)

vim.api.nvim_create_user_command(
  "AnkiClearConfig",
  function() require("ankitui.config").clear_config() end,
  { nargs = 0, desc = "Clear AnkiTUI configuration" }
)