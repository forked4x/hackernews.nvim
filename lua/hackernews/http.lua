local M = {}

function M.fetch(url, callback)
  vim.system(
    { "curl", "-s", "-L", "--max-time", "30", url },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        callback(nil, "curl failed (exit " .. result.code .. "): " .. (result.stderr or ""))
      elseif not result.stdout or result.stdout == "" then
        callback(nil, "empty response from " .. url)
      else
        callback(result.stdout, nil)
      end
    end)
  )
end

return M
