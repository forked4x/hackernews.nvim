local browser = require("hackernews.browser")

local M = {}

--- Word-wrap text to a given max width
local function display_width(s)
  local tag_chars = 0
  for tag in s:gmatch("</?[ibu]>") do
    tag_chars = tag_chars + #tag
  end
  return #s - tag_chars
end

local function wrap_text(text, max_width)
  if max_width < 1 then
    max_width = 1
  end
  local result = {}
  local current_line = ""
  local current_width = 0
  for word in text:gmatch("%S+") do
    local word_width = display_width(word)
    if current_line == "" then
      current_line = word
      current_width = word_width
    elseif current_width + 1 + word_width <= max_width then
      current_line = current_line .. " " .. word
      current_width = current_width + 1 + word_width
    else
      table.insert(result, current_line)
      current_line = word
      current_width = word_width
    end
  end
  if current_line ~= "" then
    table.insert(result, current_line)
  end
  if #result == 0 then
    table.insert(result, "")
  end
  return result
end

local function is_empty_buffer(buf)
  if vim.api.nvim_buf_get_name(buf) ~= "" then return false end
  if vim.bo[buf].modified then return false end
  if vim.bo[buf].buftype ~= "" then return false end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return #lines <= 1 and (lines[1] or "") == ""
end

local function set_buf_options(buf)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "hackernews"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_call(buf, function()
    vim.wo[0].conceallevel = 2
    vim.wo[0].concealcursor = "nc"
    vim.wo[0].wrap = false
  end)
end

local function set_loading(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Loading..." })
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Extract the concealed [...] text from the end of a line
local function get_concealed_value(line)
  return line:match("%[(.-)%]$")
end

local function map_close(buf)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, desc = "Close buffer" })
end

--- Set up keymaps for frontpage buffer
local function setup_frontpage_keymaps(buf)
  vim.keymap.set("n", "o", function()
    local line = vim.api.nvim_get_current_line()
    local value = get_concealed_value(line)
    if not value then
      return
    end

    -- If it looks like a URL, open in browser
    if value:match("^https?://") then
      browser.open(value)
    -- If it's just digits, it's an item_id — open comments
    elseif value:match("^%d+$") then
      require("hackernews").open_comments(value)
    end
  end, { buffer = buf, desc = "Open story/comments" })

  map_close(buf)
end

--- Set up keymaps for comments buffer
local function setup_comments_keymaps(buf)
  vim.keymap.set("n", "o", function()
    local line = vim.api.nvim_get_current_line()
    local value = get_concealed_value(line)
    if value then
      if value:match("^https?://") then
        browser.open(value)
        return
      elseif value:match("^%d+$") then
        browser.open("https://news.ycombinator.com/item?id=" .. value)
        return
      end
    end

    -- Fall back: search upward for a comment's [item_id]
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    for row = cursor_row, 1, -1 do
      local l = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      local item_id = l:match("%[(%d+)%]")
      if item_id then
        browser.open("https://news.ycombinator.com/item?id=" .. item_id)
        return
      end
    end
  end, { buffer = buf, desc = "Open comment in browser" })

  map_close(buf)
end

function M.comment_foldtext()
  local foldstart = vim.v.foldstart
  local foldend = vim.v.foldend
  local lines = vim.api.nvim_buf_get_lines(0, foldstart - 1, foldend, false)

  -- Count comment headers (lines ending with the fold open marker)
  local count = 0
  for _, line in ipairs(lines) do
    if line:match(" {{{$") then
      count = count + 1
    end
  end

  local first_line = lines[1]:gsub(" {{{$", "")
  local label = count == 1 and "comment" or "comments"
  local dashes = vim.v.foldlevel + 1
  return "+-" .. string.rep("-", dashes) .. " " .. count .. " " .. label .. ": " .. first_line .. " "
end

local function create_buf(buf_name, setup_keymaps_fn, extra_fn)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match(buf_name .. "$") then
      vim.api.nvim_set_current_buf(b)
      return b, true
    end
  end

  local cur = vim.api.nvim_get_current_buf()
  local buf = is_empty_buffer(cur) and cur or vim.api.nvim_create_buf(true, false)
  if buf ~= cur then vim.api.nvim_set_current_buf(buf) end

  set_buf_options(buf)
  vim.api.nvim_buf_set_name(buf, buf_name)
  set_loading(buf)
  setup_keymaps_fn(buf)
  if extra_fn then extra_fn(buf) end
  return buf, false
end

function M.create_frontpage_buf(page)
  local name = ((page and page ~= "") and page or "home") .. ".hackernews"
  return create_buf(name, setup_frontpage_keymaps)
end

function M.create_comments_buf(item_id)
  return create_buf(item_id .. ".hackernews", setup_comments_keymaps, function(buf)
    vim.api.nvim_buf_call(buf, function()
      vim.wo[0].foldmethod = "marker"
      vim.wo[0].foldmarker = "{{{,}}}"
      vim.wo[0].foldlevel = 99
      vim.wo[0].foldtext = "v:lua.require'hackernews.ui'.comment_foldtext()"
    end)
  end)
end

local function apply_render(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local base_url = "https://news.ycombinator.com"

local page_paths = {
  new = "/newest",
  ask = "/ask",
  show = "/show",
  job = "/jobs",
  past = "/front",
}

local function make_header(page)
  local url = base_url
  local label = "Hacker News"
  if page and page ~= "" then
    if page:match("^%d%d%d%d%-%d%d%-%d%d$") then
      url = base_url .. "/front?day=" .. page
      label = label .. " > " .. page
    elseif page_paths[page] then
      url = base_url .. page_paths[page]
      label = label .. " > " .. page:sub(1, 1):upper() .. page:sub(2)
    end
  end
  return " Y  " .. label .. " [" .. url .. "]"
end

function M.render_frontpage(buf, stories, page)
  local lines = {}

  -- Header
  table.insert(lines, make_header(page))
  table.insert(lines, "")

  for _, story in ipairs(stories) do
    -- Title line: "NN. Title (domain) [url]"
    local title_line = string.format("%2s. %s", story.rank, story.title)
    if story.domain then
      title_line = title_line .. " (" .. story.domain .. ")"
    end
    if story.url then
      title_line = title_line .. " [" .. story.url .. "]"
    end

    -- Subtitle line: "    XXX points by user TIME | NN comments [item_id]"
    local subtitle_parts = {}
    if story.points ~= "0" then
      table.insert(subtitle_parts, story.points .. " points")
    end
    if story.user ~= "" then
      table.insert(subtitle_parts, "by " .. story.user)
    end
    if story.time_ago ~= "" then
      table.insert(subtitle_parts, story.time_ago)
    end
    local subtitle_line = "    " .. table.concat(subtitle_parts, " ")
    if story.comment_count and story.item_id ~= "" then
      subtitle_line = subtitle_line .. " | " .. story.comment_count .. " comments"
    end
    if story.item_id ~= "" then
      subtitle_line = subtitle_line .. " [" .. story.item_id .. "]"
    end

    table.insert(lines, title_line)
    table.insert(lines, subtitle_line)
    table.insert(lines, "")
  end

  apply_render(buf, lines)
end

function M.render_comments(buf, comments, header)
  local lines = {}

  if header then
    -- Title line: "Title (domain) [url]"
    local title_line = header.title
    if header.domain then
      title_line = title_line .. " (" .. header.domain .. ")"
    end
    if header.url then
      title_line = title_line .. " [" .. header.url .. "]"
    end
    table.insert(lines, title_line)

    -- Subtitle line: "XXX points by user time_ago | XXX comments [item_id]"
    local subtitle_parts = {}
    if header.points ~= "0" then
      table.insert(subtitle_parts, header.points .. " points")
    end
    if header.user ~= "" then
      table.insert(subtitle_parts, "by " .. header.user)
    end
    if header.time_ago ~= "" then
      table.insert(subtitle_parts, header.time_ago)
    end
    local subtitle_line = table.concat(subtitle_parts, " ")
    if header.comment_count and header.item_id ~= "" then
      subtitle_line = subtitle_line .. " | " .. header.comment_count .. " comments"
    end
    if header.item_id ~= "" then
      subtitle_line = subtitle_line .. " [" .. header.item_id .. "]"
    end
    table.insert(lines, subtitle_line)
    table.insert(lines, "")

    -- Body text (if any)
    if header.body ~= "" then
      local paragraphs = vim.split(header.body, "\n", { plain = true })
      for _, paragraph in ipairs(paragraphs) do
        local wrapped = wrap_text(paragraph, 88)
        for _, wl in ipairs(wrapped) do
          table.insert(lines, wl)
        end
      end
      table.insert(lines, "")
    end

  end

  for i, comment in ipairs(comments) do
    local prefix = string.rep("  ", comment.indent)

    -- Info line: "prefix user time_ago [item_id] {{{" (fold open marker)
    local info_line = prefix .. comment.user .. " " .. comment.time_ago
    if comment.id ~= "" then
      info_line = info_line .. " [" .. comment.id .. "]"
    end
    info_line = info_line .. " {{{"

    table.insert(lines, info_line)

    -- Content lines (word-wrapped)
    local max_width = 88 - #prefix
    local paragraphs = vim.split(comment.text, "\n", { plain = true })
    for _, paragraph in ipairs(paragraphs) do
      local wrapped = wrap_text(paragraph, max_width)
      for _, wl in ipairs(wrapped) do
        table.insert(lines, prefix .. wl)
      end
    end

    -- Calculate how many folds to close after this comment
    local next_indent = -1
    if i < #comments then
      next_indent = comments[i + 1].indent
    end
    local closes = 0
    if next_indent <= comment.indent then
      closes = comment.indent - next_indent + 1
    end

    -- Append close markers to the last content line
    if closes > 0 then
      local close_str = string.rep(" }}}", closes)
      lines[#lines] = lines[#lines] .. close_str
    end

    -- Blank line separator
    table.insert(lines, "")
  end

  apply_render(buf, lines)

  -- Highlight OP username in comment info lines
  if header and header.user ~= "" then
    local ns = vim.api.nvim_create_namespace("hackernews_op")
    vim.api.nvim_set_hl(0, "hnOP", { fg = "#ff6600", ctermfg = 166 })
    for idx, line in ipairs(lines) do
      -- Comment info lines end with [item_id] {{{
      if line:match("%[%d+%] {{{$") then
        local prefix = line:match("^(%s*)")
        local user = line:match("^%s*(%S+)")
        if user == header.user then
          vim.api.nvim_buf_set_extmark(buf, ns, idx - 1, #prefix, {
            end_col = #prefix + #user,
            hl_group = "hnOP",
          })
        end
      end
    end
  end
end

return M
