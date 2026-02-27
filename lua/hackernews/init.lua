local http = require("hackernews.http")
local parser = require("hackernews.parser")
local ui = require("hackernews.ui")

local M = {}

M.config = {
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
  textwidth = 88,
}

function M.setup(opts)
  opts = opts or {}
  if opts.keymaps then
    for k, v in pairs(opts.keymaps) do
      M.config.keymaps[k] = v
    end
  end
  if opts.textwidth ~= nil then
    M.config.textwidth = opts.textwidth
  end
end

local base_url = "https://news.ycombinator.com"

local page_paths = {
  new = "/newest",
  ask = "/ask",
  show = "/show",
  job = "/jobs",
  past = "/front",
}

function M.open_frontpage(page)
  page = (page and page ~= "") and page or ""

  local url
  if page == "" then
    url = base_url
  elseif page:match("^%d%d%d%d%-%d%d%-%d%d$") then
    url = base_url .. "/front?day=" .. page
  elseif page_paths[page] then
    url = base_url .. page_paths[page]
  else
    vim.notify("HackerNews: unknown page '" .. page .. "'. Valid: new, ask, show, job, past, or YYYY-MM-DD", vim.log.levels.ERROR)
    return
  end

  local buf, already_loaded = ui.create_frontpage_buf(page)
  if already_loaded then
    return
  end

  http.fetch(url, function(body, err)
    if err then
      vim.notify("HackerNews: " .. err, vim.log.levels.ERROR)
      return
    end

    local stories = parser.parse_frontpage(body)
    if #stories == 0 then
      vim.notify("HackerNews: failed to parse stories", vim.log.levels.ERROR)
      return
    end

    ui.render_frontpage(buf, stories, page)
  end)
end

function M.open_comments(item_id)
  local buf, already_loaded = ui.create_comments_buf(item_id)
  if already_loaded then
    return
  end

  local url = "https://news.ycombinator.com/item?id=" .. item_id

  http.fetch(url, function(body, err)
    if err then
      vim.notify("HackerNews: " .. err, vim.log.levels.ERROR)
      return
    end

    local comments = parser.parse_comments(body)
    local header = parser.parse_story_header(body)
    if #comments == 0 and not header then
      vim.notify("HackerNews: no comments found", vim.log.levels.WARN)
    end

    ui.render_comments(buf, comments, header)
  end)
end

return M
