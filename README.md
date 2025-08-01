# ankitui.nvim

⚠️ **Warning**: This plugin, including this README, was entirely built by the Gemini CLI. While efforts were made to ensure accuracy, there might be errors or missing details. Please review the content critically and refer to the code for precise information.

A Neovim plugin for reviewing Anki cards directly within your editor, powered by AnkiConnect.

## Features

- **Seamless Anki Integration**: Connects to your Anki instance via AnkiConnect to fetch and update cards.
- **Configurable Fields**: Define which fields from your Anki notes should be used as the "question" and "answer" for each deck, supporting multiple fields per part.
- **Interactive Review Sessions**: Start a review session for new cards in a selected deck, presented one by one in a floating window.
- **Ease Rating**: Rate cards (Again, Hard, Good, Easy) using intuitive keybindings (1, 2, 3, 4).
- **Session Management**: Easily exit review sessions with a confirmation prompt.
- **Configuration Reset**: Clear all saved deck configurations with a simple command.

## Prerequisites

- **Neovim**: Version 0.7 or higher.
- **curl**: Command-line tool for transferring data with URLs.
- **Anki**: Desktop application installed and running.
- **AnkiConnect**: An Anki add-on that allows external applications to interact with Anki. You can install it from Anki's Add-ons browser (Code: `2055492159`).

## Installation

Install with your favorite plugin manager. For `lazy.nvim`:

```lua
-- init.lua
{
  'Zhuxy/ankitui.nvim', -- Replace with your actual GitHub username and repo name
  dependencies = {
    'nvim-telescope/telescope.nvim', -- For deck and field selection
    'folke/snacks.nvim', -- For floating windows
  },
  config = function()
    -- Optional: Your AnkiTUI configuration here if any in the future
  end
}
```

## Configuration

You can customize the plugin's behavior by calling the `setup` function. The following options are available:

- `new_cards_per_session`: The number of new cards to fetch per session (default: `5`).
- `max_cards_per_session`: The maximum number of cards to review in a session (default: `20`).
- `log_to_file`: Whether to log AnkiConnect calls to a file (default: `false`).
- `keymaps`: A table of keymappings for the review session. The defaults are:

```lua
keymaps = {
  again = "1",
  hard = "2",
  good = "3",
  easy = "4",
  show_session_cards = "<leader>s",
  toggle_qa = "<space>",
}
```

Example configuration with `lazy.nvim`:

```lua
{
  'Zhuxy/ankitui.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'folke/snacks.nvim',
  },
  config = function()
    require('ankitui').setup({
      keymaps = {
        again = 'a',
        hard = 's',
        good = 'd',
        easy = 'f',
        show_session_cards = '<leader>l',
      }
    })
  end
}
```

## Usage

### Start a Learning Session

To begin reviewing cards, run the following command in Neovim:

```vim
:AnkiStartLearning
```

This will open a Telescope picker allowing you to select an Anki deck. If it's the first time you're reviewing cards from that deck, you will be prompted to configure which fields correspond to the "question" and "answer" parts of your cards.

#### Configuring Deck Fields

When prompted to select fields:

- Use `<Tab>` to select multiple fields.
- The order in which you select fields will be the order in which their content is concatenated (separated by newlines).
- Press `<CR>` (Enter) to confirm your selection for question fields, and then again for answer fields.

Your selections will be saved for future sessions with that deck.

### Reviewing Cards

- **Toggle Question/Answer**: Press `<Space>` to switch between the question and answer view.
- **Rate Card Ease**: After revealing the answer, use the following keys to rate the card:
    - `1`: Again (Hardest)
    - `2`: Hard
    - `3`: Good
    - `4`: Easy (Easiest)

After rating, the current card will be submitted to Anki, and the next card in your session will be displayed.

### Editing Cards

- **Initiate Edit**: While viewing the **answer** of a card, press `e` to open the edit interface.
- **Edit Interface**: This will open multiple floating windows, one for each field of the note. The window corresponding to the answer field will be automatically focused.
- **Save Changes**: In any edit window, press `<leader>s` to save all changes to Anki. The edit windows will close, and focus will return to the main review window.
- **Quit Without Saving**: In any edit window, press `q` to close all edit windows without saving any changes. Focus will return to the main review window.



### Exiting a Session

- **Exit Session**: Press `<ESC>` at any time during a review session. You will be prompted to confirm if you wish to end the session.

### Clearing Configuration

To reset all saved deck configurations (e.g., if you've changed your Anki note types or want to reconfigure a deck):

```vim
:AnkiClearConfig
```

## Troubleshooting

- **"AnkiConnect request failed"**: Ensure Anki is running and the AnkiConnect add-on is installed and enabled. Check Anki's console for any AnkiConnect errors.
- **"No new cards found"**: This might mean there are genuinely no new cards in the selected deck, or your query for new cards is incorrect (though the plugin uses a standard `is:new` query).
- **Floating window issues**: Ensure `nvim-snacks` is correctly installed and its dependencies are met.

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. (You'll need to create a LICENSE file in your repository if you haven't already.)
