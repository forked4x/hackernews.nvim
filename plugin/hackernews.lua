vim.api.nvim_create_user_command("HackerNews", function(opts)
  local page = vim.trim(opts.args or "")
  require("hackernews").open_frontpage(page)
end, {
  nargs = "?",
  complete = function()
    return { "new", "ask", "show", "job", "past" }
  end,
  desc = "Open Hacker News front page",
})
