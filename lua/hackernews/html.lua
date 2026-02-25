local M = {}

local named_entities = {
  amp = "&",
  lt = "<",
  gt = ">",
  quot = '"',
  apos = "'",
  nbsp = " ",
}

function M.decode_entities(s)
  if not s then
    return ""
  end
  -- Named entities
  s = s:gsub("&(%w+);", function(name)
    return named_entities[name] or ("&" .. name .. ";")
  end)
  -- Hex numeric entities &#xHH;
  s = s:gsub("&#x(%x+);", function(hex)
    return vim.fn.nr2char(tonumber(hex, 16), true)
  end)
  -- Decimal numeric entities &#NNN;
  s = s:gsub("&#(%d+);", function(dec)
    return vim.fn.nr2char(tonumber(dec), true)
  end)
  return s
end

function M.strip_tags(html)
  if not html then
    return ""
  end

  -- Normalize line endings
  html = html:gsub("\r\n", "\n")

  -- Handle <p> tags as paragraph separators
  html = html:gsub("<p>", "\n\n")
  html = html:gsub("</p>", "")

  -- Handle <br> tags
  html = html:gsub("<br%s*/?>", "\n")

  -- Handle <pre><code>...</code></pre> — preserve content
  html = html:gsub("<pre><code>(.-)</code></pre>", function(code)
    return "\n" .. M.decode_entities(code) .. "\n"
  end)

  -- Handle <a href="URL">text</a>
  html = html:gsub('<a[^>]-href="([^"]*)"[^>]*>(.-)</a>', function(href, text)
    -- Strip any nested tags from text
    text = text:gsub("<[^>]+>", "")
    text = M.decode_entities(text)
    href = M.decode_entities(href)
    -- If the link text is basically the URL, just show the URL
    local clean_text = text:gsub("^https?://", ""):gsub("/$", "")
    local clean_href = href:gsub("^https?://", ""):gsub("/$", "")
    if clean_text == clean_href then
      return "<u>" .. href .. "</u>"
    else
      return text .. " (<u>" .. href .. "</u>)"
    end
  end)

  -- Normalize <strong> to <b>
  html = html:gsub("<strong>", "<b>")
  html = html:gsub("</strong>", "</b>")

  -- Protect formatting tags from generic strip
  html = html:gsub("<(/?[ibu])>", "\127%1\127")

  -- Strip all remaining tags
  html = html:gsub("<[^>]+>", "")

  -- Restore formatting tags
  html = html:gsub("\127(/?[ibu])\127", "<%1>")

  -- Decode entities
  html = M.decode_entities(html)

  -- Clean up excessive blank lines
  html = html:gsub("\n\n\n+", "\n\n")

  -- Trim leading/trailing whitespace
  html = html:match("^%s*(.-)%s*$")

  return html
end

return M
