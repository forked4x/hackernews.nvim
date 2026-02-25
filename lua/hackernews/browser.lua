local M = {}

function M.open(url)
  -- Neovim 0.10+ has vim.ui.open
  if vim.ui.open then
    vim.ui.open(url)
    return
  end

  -- Fallback for older Neovim
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", url }
  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", url }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "cmd", "/c", "start", "", url }
  else
    vim.notify("Cannot open URL: unsupported platform", vim.log.levels.ERROR)
    return
  end

  vim.system(cmd, { detach = true })
end

return M
