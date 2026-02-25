local html = require("hackernews.html")

local M = {}

--- Split HTML into blocks by finding all occurrences of a marker string
local function split_html_blocks(html, marker)
  local blocks, positions = {}, {}
  local search_start = 1
  while true do
    local s = html:find(marker, search_start, true)
    if not s then break end
    table.insert(positions, s)
    search_start = s + 1
  end
  for i, pos in ipairs(positions) do
    local end_pos = positions[i + 1] or #html
    table.insert(blocks, html:sub(pos, end_pos - 1))
  end
  return blocks
end

function M.parse_frontpage(page_html)
  local stories = {}

  local blocks = split_html_blocks(page_html, '<tr class="athing submission"')

  for _, block in ipairs(blocks) do
    local story = {}

    -- Item ID from the athing row
    story.item_id = block:match('<tr class="athing submission" id="(%d+)"')

    -- Rank
    story.rank = block:match('<span class="rank">(%d+)%.')

    -- Title and URL from titleline
    local titleline = block:match('<span class="titleline">(.-)</span>')
    if titleline then
      story.url = titleline:match('<a[^>]-href="([^"]*)"')
      story.title = titleline:match('<a[^>]->(.-)</a>')
      if story.title then
        story.title = html.decode_entities(story.title)
      end
      if story.url then
        story.url = html.decode_entities(story.url)
      end
    end

    -- Domain
    story.domain = block:match('<span class="sitestr">(.-)</span>')

    -- Subtext row — points, user, time, comments
    local subtext = block:match('<td class="subtext">(.-)</td>')
    if subtext then
      story.points = subtext:match('<span class="score"[^>]*>(%d+) point')
      story.user = subtext:match('<a href="user%?id=[^"]*" class="hnuser">(.-)</a>')
      story.time_ago = subtext:match('<span class="age"[^>]*><a[^>]*>(.-)</a></span>')

      -- Comments count — last <a> in subtext with item?id= link
      local last_comment_text
      for comment_text in subtext:gmatch('<a href="item%?id=%d+">(.-)</a>') do
        last_comment_text = comment_text
      end
      if last_comment_text then
        -- Handle &nbsp; in comment count
        last_comment_text = html.decode_entities(last_comment_text)
        story.comment_count = last_comment_text:match("(%d+)%s*comment")
        if not story.comment_count and last_comment_text:match("discuss") then
          story.comment_count = "0"
        end
      end
    end

    -- Handle self-posts (Ask HN, Show HN, etc.) — relative URL
    if story.url and story.url:match("^item%?id=") then
      story.url = "https://news.ycombinator.com/" .. story.url
      story.domain = nil
    end

    -- Skip entries without a title (malformed)
    if story.title and story.title ~= "" then
      -- Default missing fields for job posts etc.
      story.rank = story.rank or ""
      story.points = story.points or "0"
      story.user = story.user or ""
      story.time_ago = story.time_ago or ""
      story.comment_count = story.comment_count or "0"
      story.item_id = story.item_id or ""
      table.insert(stories, story)
    end
  end

  return stories
end

function M.parse_story_header(page_html)
  local header = {}

  -- Extract the fatitem area (up to comment-tree, since fatitem has nested tables)
  local fatitem = page_html:match('<table class="fatitem"(.-)class="comment%-tree"')
  if not fatitem then return nil end

  -- Item ID from the athing submission row
  header.item_id = fatitem:match('<tr class="athing submission" id="(%d+)"')

  -- Title and URL from titleline
  local titleline = fatitem:match('<span class="titleline">(.-)</span>')
  if not titleline then return nil end

  header.url = titleline:match('<a[^>]-href="([^"]*)"')
  header.title = titleline:match('<a[^>]->(.-)</a>')
  if header.title then
    header.title = html.decode_entities(header.title)
  end
  if header.url then
    header.url = html.decode_entities(header.url)
  end

  -- Domain
  header.domain = fatitem:match('<span class="sitestr">(.-)</span>')

  -- Subtext row
  local subtext = fatitem:match('<td class="subtext">(.-)</td>')
  if subtext then
    header.points = subtext:match('<span class="score"[^>]*>(%d+) point')
    header.user = subtext:match('<a href="user%?id=[^"]*" class="hnuser">(.-)</a>')
    header.time_ago = subtext:match('<span class="age"[^>]*><a[^>]*>(.-)</a></span>')

    local last_comment_text
    for comment_text in subtext:gmatch('<a href="item%?id=%d+">(.-)</a>') do
      last_comment_text = comment_text
    end
    if last_comment_text then
      last_comment_text = html.decode_entities(last_comment_text)
      header.comment_count = last_comment_text:match("(%d+)%s*comment")
      if not header.comment_count and last_comment_text:match("discuss") then
        header.comment_count = "0"
      end
    end
  end

  -- Handle self-posts
  if header.url and header.url:match("^item%?id=") then
    header.url = "https://news.ycombinator.com/" .. header.url
    header.domain = nil
  end

  -- Body text from toptext div (Ask HN, Show HN, etc.)
  local toptext = fatitem:match('<div class="toptext"[^>]*>(.-)</div>')
  if toptext then
    header.body = html.strip_tags(toptext)
  else
    header.body = ""
  end

  -- Default missing fields
  header.item_id = header.item_id or ""
  header.points = header.points or "0"
  header.user = header.user or ""
  header.time_ago = header.time_ago or ""
  header.comment_count = header.comment_count or "0"

  return header
end

function M.parse_comments(page_html)
  local comments = {}

  local blocks = split_html_blocks(page_html, '<tr class="athing comtr"')

  for _, block in ipairs(blocks) do
    local comment = {}

    -- Comment ID
    comment.id = block:match('<tr class="athing comtr" id="(%d+)"')

    -- Indent level from the indent attribute on the img spacer
    local indent_str = block:match('indent="(%d+)"')
    comment.indent = indent_str and tonumber(indent_str) or 0

    -- User
    comment.user = block:match('<a href="user%?id=[^"]*" class="hnuser">(.-)</a>')

    -- Time
    comment.time_ago = block:match('<span class="age"[^>]*><a[^>]*>(.-)</a></span>')

    -- Comment text from commtext div/span
    local commtext = block:match('<div class="commtext[^"]*">(.-)</div>%s*<div class="reply"')
      or block:match('<div class="commtext[^"]*">(.-)</div>')
      or block:match('<span class="commtext[^"]*">(.-)</span>')

    if commtext then
      comment.text = html.strip_tags(commtext)
    else
      comment.text = ""
    end

    -- Handle deleted/dead comments
    if not comment.user then
      comment.user = "[deleted]"
      if comment.text == "" then
        comment.text = "[deleted]"
      end
    end

    comment.id = comment.id or ""
    comment.time_ago = comment.time_ago or ""

    table.insert(comments, comment)
  end

  return comments
end

return M
