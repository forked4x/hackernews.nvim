# hackernews.nvim

Browse [Hacker News](https://news.ycombinator.com) from inside Neovim.

![](https://github.com/user-attachments/assets/377c1a37-e794-492c-9f97-11e6ae53d988)
![](https://github.com/user-attachments/assets/9345df72-34db-4ec5-996c-1ca854bdd7c2)

## Features

- Browse the front page and other pages (New, Ask, Show, Jobs, Past)
- View past front pages by date
- Read comment threads with foldable comments
- Open stories and comments in your browser
- Syntax highlighting with HN-style colors
- Async fetching via `curl`

## Requirements

- Neovim 0.10+ recommended (not tested on previous versions)
- `curl`

## Installation

### lazy.nvim

```lua
{
  "forked4x/hackernews.nvim",
  opts = {}, -- optional
}
```

### mini.deps

```lua
MiniDeps.add("forked4x/hackernews.nvim")
require("hackernews"):setup({}) -- optional
```

## Configuration

`setup()` is optional. The plugin works out of the box with sensible defaults. Call it only if you want to customize keymaps or text width.

With lazy.nvim, `setup()` is called automatically when `opts` is provided.

```lua
-- Default configuration (all optional)
require("hackernews").setup({
  keymaps = {
    open = "o",
    open_in_browser = "O",
    close = "q",
    next_comment = "]]",
    prev_comment = "[[",
    next_sibling = "]=",
    prev_sibling = "[=",
    next_parent = "]-",
    prev_parent = "[-",
    next_root = "]0",
    prev_root = "[0",
  },
  textwidth = 88,  -- set to 0 to use full window width
})
```

## Usage

```
:HackerNews            " Front page
:HackerNews new        " Newest stories
:HackerNews ask        " Ask HN
:HackerNews show       " Show HN
:HackerNews job        " Jobs
:HackerNews past       " Past front page
:HackerNews 2025-12-25 " Front page for a specific date
```

## Keybindings

These mappings are set in HackerNews buffers:

| Key | Action |
|-----|--------|
| `o` | Open story link in browser, or navigate to comments |
| `O` | Open in browser (story URL or HN comment link) |
| `q` | Close the buffer |
| `]]` / `[[` | Next/previous comment |
| `]=` / `[=` | Next/previous sibling comment |
| `]-` / `[-` | Next/previous parent comment |
| `]0` / `[0` | Next/previous root comment |
| `zc` / `zo` | Fold/unfold comment threads |

## Highlight Groups

All highlight groups can be overridden in your colorscheme or config.

| Group | Description | Default |
|-------|-------------|---------|
| `hnLogo` | The `Y` logo in the header | `guifg=#ffffff guibg=#ff6600 gui=bold` |
| `hnTitle` | "Hacker News" text in the header | `guifg=#ff6600 gui=bold` |
| `hnStoryHeader` | Story title in comment view | `guifg=#ff6600 gui=bold` |
| `hnOP` | OP username in comment threads | `guifg=#ff6600` |
| `hnRank` | Story rank number (e.g. `1.`) | links to `Comment` |
| `hnDomain` | Domain in parentheses | links to `Comment` |
| `hnSubtitle` | Story metadata line on front page | links to `Comment` |
| `hnStorySubtitle` | Story metadata line in comment view | links to `Comment` |
| `hnCommentInfo` | Comment author/time header | links to `Comment` |
| `hnItalic` | `<i>` text in comments | `gui=italic` |
| `hnBold` | `<b>` text in comments | `gui=bold` |
| `hnUnderline` | `<u>` text in comments | `gui=underline` |

## License

[MIT](LICENSE)
