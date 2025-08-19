local ankitui = require("ankitui")

function ankitui.setup(config)
  ankitui.config = vim.tbl_deep_extend("force", ankitui.config, config or {})
end

vim.api.nvim_create_user_command(
  "AnkiStartLearning",
  function() ankitui.start_learning_flow() end,
  { nargs = 0, desc = "Start an Anki learning session" }
)

vim.api.nvim_create_user_command(
  "AnkiClearConfig",
  function() require("ankitui.config").clear_deck_config() end,
  { nargs = 0, desc = "Clear AnkiTUI configuration" }
)
