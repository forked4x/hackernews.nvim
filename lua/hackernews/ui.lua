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

--- Get the effective textwidth based on config and window size
local function get_textwidth()
  local config = require("hackernews").config
  local effective = math.floor(vim.api.nvim_win_get_width(0) * 0.95)
  if config.textwidth and config.textwidth > 0 then
    return math.min(effective, config.textwidth)
  end
  return effective
end

--- Set a keymap on a buffer, skipping if key is empty
local function set_keymap(buf, key, fn, desc)
  if key == "" then return end
  vim.keymap.set("n", key, fn, { buffer = buf, desc = desc })
end

--- Get indent level of a comment header line, or nil if not a header
local function get_comment_indent(line)
  if not line:match("%[%d+%] {{{$") then return nil end
  local prefix = line:match("^(%s*)")
  return #prefix / 2
end

--- Navigate between comments in a comment buffer
local function navigate_comment(buf, direction, mode)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Find current comment's indent by searching upward for nearest header
  local current_indent = nil
  for row = cursor_row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    local indent = get_comment_indent(line)
    if indent ~= nil then
      current_indent = indent
      break
    end
  end

  if current_indent == nil then
    if direction == "forward" then
      current_indent = 0
    else
      return
    end
  end

  -- Determine target indent
  local target_indent
  if mode == "any" then
    target_indent = nil
  elseif mode == "sibling" then
    target_indent = current_indent
  elseif mode == "parent" then
    target_indent = current_indent - 1
    if target_indent < 0 then return end
  elseif mode == "root" then
    target_indent = 0
  end

  -- Search forward or backward
  local start_row, end_row, step
  if direction == "forward" then
    start_row = cursor_row + 1
    end_row = line_count
    step = 1
  else
    start_row = cursor_row - 1
    end_row = 1
    step = -1
  end

  for row = start_row, end_row, step do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    local indent = get_comment_indent(line)
    if indent ~= nil then
      if target_indent == nil or indent == target_indent then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return
      end
      -- For sibling search, stop if we've left the subtree
      if mode == "sibling" and indent < current_indent then
        return
      end
    end
  end
end

--- Set up keymaps for frontpage buffer
local function setup_frontpage_keymaps(buf)
  local keymaps = require("hackernews").config.keymaps

  set_keymap(buf, keymaps.open, function()
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
  end, "Open story/comments")

  set_keymap(buf, keymaps.open_in_browser, function()
    local line = vim.api.nvim_get_current_line()
    local value = get_concealed_value(line)
    if not value then return end
    if value:match("^https?://") then
      browser.open(value)
    elseif value:match("^%d+$") then
      browser.open("https://news.ycombinator.com/item?id=" .. value)
    end
  end, "Open in browser")

  set_keymap(buf, keymaps.close, function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, "Close buffer")
end

--- Set up keymaps for comments buffer
local function setup_comments_keymaps(buf)
  local keymaps = require("hackernews").config.keymaps

  set_keymap(buf, keymaps.open, function()
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
  end, "Open comment in browser")

  set_keymap(buf, keymaps.open_in_browser, function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    for row = cursor_row, 1, -1 do
      local l = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      local item_id = l:match("%[(%d+)%]")
      if item_id then
        browser.open("https://news.ycombinator.com/item?id=" .. item_id)
        return
      end
    end
  end, "Open in browser")

  set_keymap(buf, keymaps.close, function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, "Close buffer")

  -- Comment navigation keymaps
  set_keymap(buf, keymaps.next_comment, function()
    navigate_comment(buf, "forward", "any")
  end, "Next comment")

  set_keymap(buf, keymaps.prev_comment, function()
    navigate_comment(buf, "backward", "any")
  end, "Previous comment")

  set_keymap(buf, keymaps.next_sibling, function()
    navigate_comment(buf, "forward", "sibling")
  end, "Next sibling comment")

  set_keymap(buf, keymaps.prev_sibling, function()
    navigate_comment(buf, "backward", "sibling")
  end, "Previous sibling comment")

  set_keymap(buf, keymaps.next_parent, function()
    navigate_comment(buf, "forward", "parent")
  end, "Next parent comment")

  set_keymap(buf, keymaps.prev_parent, function()
    navigate_comment(buf, "backward", "parent")
  end, "Previous parent comment")

  set_keymap(buf, keymaps.next_root, function()
    navigate_comment(buf, "forward", "root")
  end, "Next root comment")

  set_keymap(buf, keymaps.prev_root, function()
    navigate_comment(buf, "backward", "root")
  end, "Previous root comment")
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

local resize_autocmd_created = false

local function ensure_resize_autocmd()
  if resize_autocmd_created then return end
  resize_autocmd_created = true
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      M.rewrap_all_comment_buffers()
    end,
  })
end

function M.create_comments_buf(item_id)
  return create_buf(item_id .. ".hackernews", setup_comments_keymaps, function(buf)
    vim.api.nvim_buf_call(buf, function()
      vim.wo[0].foldmethod = "marker"
      vim.wo[0].foldmarker = "{{{,}}}"
      vim.wo[0].foldlevel = 99
      vim.wo[0].foldtext = "v:lua.require'hackernews.ui'.comment_foldtext()"
    end)
    ensure_resize_autocmd()
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

--- Apply OP username highlights to comment header lines
local function reapply_op_highlights(buf, lines)
  if #lines < 2 then return end
  local subtitle = lines[2]
  local op_user = subtitle:match("by (%S+)")
  if not op_user then return end

  local ns = vim.api.nvim_create_namespace("hackernews_op")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_set_hl(0, "hnOP", { fg = "#ff6600", ctermfg = 166 })

  for idx, line in ipairs(lines) do
    if line:match("%[%d+%] {{{$") then
      local prefix = line:match("^(%s*)")
      local user = line:match("^%s*(%S+)")
      if user == op_user then
        vim.api.nvim_buf_set_extmark(buf, ns, idx - 1, #prefix, {
          end_col = #prefix + #user,
          hl_group = "hnOP",
        })
      end
    end
  end
end

function M.render_comments(buf, comments, header)
  local lines = {}
  local tw = get_textwidth()

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
        local wrapped = wrap_text(paragraph, tw)
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
    local max_width = tw - #prefix
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
  reapply_op_highlights(buf, lines)
end

--- Join wrapped lines back into paragraphs (un-wrap)
local function unwrap_paragraphs(lines)
  local paragraphs = {}
  local current = {}
  for _, line in ipairs(lines) do
    if line == "" then
      if #current > 0 then
        table.insert(paragraphs, table.concat(current, " "))
        current = {}
      end
      table.insert(paragraphs, "")
    else
      table.insert(current, line)
    end
  end
  if #current > 0 then
    table.insert(paragraphs, table.concat(current, " "))
  end
  return paragraphs
end

--- Re-wrap a single comment buffer to a new textwidth
local function rewrap_comment_buffer(buf, tw)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end

  local new_lines = {}
  local i = 1
  local n = #lines

  -- Title line — keep as-is
  table.insert(new_lines, lines[i])
  i = i + 1
  if i > n then apply_render(buf, new_lines); return end

  -- Subtitle line — keep as-is
  table.insert(new_lines, lines[i])
  i = i + 1
  if i > n then apply_render(buf, new_lines); return end

  -- Blank line after header
  if i <= n and lines[i] == "" then
    table.insert(new_lines, "")
    i = i + 1
  end

  -- Body text (for Ask HN posts) — lines before first comment header
  local body_parts = {}
  local has_body = false
  while i <= n and not lines[i]:match("%[%d+%] {{{$") do
    if lines[i] == "" then
      -- Peek: if next non-empty line is a comment header, body is done
      local peek = i + 1
      while peek <= n and lines[peek] == "" do peek = peek + 1 end
      if peek > n or lines[peek]:match("%[%d+%] {{{$") then
        break
      end
    end
    table.insert(body_parts, lines[i])
    has_body = true
    i = i + 1
  end

  if has_body then
    local paragraphs = unwrap_paragraphs(body_parts)
    for _, p in ipairs(paragraphs) do
      if p == "" then
        table.insert(new_lines, "")
      else
        for _, wl in ipairs(wrap_text(p, tw)) do
          table.insert(new_lines, wl)
        end
      end
    end
  end

  -- Blank separator between body/header and comments
  if i <= n and lines[i] == "" then
    table.insert(new_lines, "")
    i = i + 1
  end

  -- Process comment blocks
  while i <= n do
    local line = lines[i]

    if line:match("%[%d+%] {{{$") then
      -- Comment header — keep as-is
      table.insert(new_lines, line)
      local prefix = line:match("^(%s*)")
      i = i + 1

      -- Collect body lines until inter-comment separator
      local body = {}
      while i <= n do
        if lines[i] == "" then
          local peek = i + 1
          while peek <= n and lines[peek] == "" do peek = peek + 1 end
          if peek > n or lines[peek]:match("%[%d+%] {{{$") then
            break
          end
        end
        table.insert(body, lines[i])
        i = i + 1
      end

      -- Strip fold close markers from last body line
      local fold_closes = 0
      if #body > 0 then
        local last = body[#body]
        while last:match(" }}}$") do
          fold_closes = fold_closes + 1
          last = last:sub(1, -5)
        end
        body[#body] = last
      end

      -- Strip prefix from body lines
      local stripped = {}
      for _, bl in ipairs(body) do
        local content = bl
        if #prefix > 0 and bl:sub(1, #prefix) == prefix then
          content = bl:sub(#prefix + 1)
        end
        table.insert(stripped, content)
      end

      -- Un-wrap into paragraphs (prefix-only lines become "" after stripping)
      local paragraphs = unwrap_paragraphs(stripped)

      -- Re-wrap
      local max_w = tw - #prefix
      local rewrapped = {}
      for _, p in ipairs(paragraphs) do
        if p == "" then
          table.insert(rewrapped, prefix)
        else
          for _, wl in ipairs(wrap_text(p, max_w)) do
            table.insert(rewrapped, prefix .. wl)
          end
        end
      end

      -- Re-add fold close markers to last line
      if fold_closes > 0 and #rewrapped > 0 then
        rewrapped[#rewrapped] = rewrapped[#rewrapped] .. string.rep(" }}}", fold_closes)
      end

      for _, rl in ipairs(rewrapped) do
        table.insert(new_lines, rl)
      end

      -- Blank separator after comment
      if i <= n and lines[i] == "" then
        table.insert(new_lines, "")
        i = i + 1
      end
    else
      -- Other lines (blank separators, etc.)
      table.insert(new_lines, line)
      i = i + 1
    end
  end

  apply_render(buf, new_lines)
  reapply_op_highlights(buf, new_lines)
end

function M.rewrap_all_comment_buffers()
  local tw = get_textwidth()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name:match("%d+%.hackernews$") then
        rewrap_comment_buffer(b, tw)
      end
    end
  end
end

return M
