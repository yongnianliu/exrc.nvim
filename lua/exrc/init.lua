local cache = require("exrc.cache")
local options = require("exrc.options")
local Menu = require("nui.menu")

local function file_hash(filepath)
  return vim.fn.sha256(table.concat(vim.fn.readfile(filepath, "b"), "\n"))
end

local mod = {
  _initialized = false,
}

function mod.setup(user_options)
  if mod._initialized then
    return
  end

  options.setup(user_options or {})
  cache.setup()

  if vim.o.exrc then
    error("[exrc.nvim] unset 'exrc' to use this plugin!")
  end

  vim.cmd([[
    augroup exrc-nvim-source
      autocmd!

      autocmd DirChanged * if v:event.scope ==# "global" | call v:lua.require("exrc").try_source() | endif

      if v:vim_did_enter
        lua require("exrc").try_source()
      else
        autocmd VimEnter * lua require("exrc").try_source()
      endif
    augroup END
  ]])

  mod._initialized = true
end

function mod.try_source()
  for _, file in ipairs(options.get("files")) do
    local filepath = vim.fn.fnamemodify(file, ":p")
    if vim.fn.filereadable(filepath) == 1 then
      return mod.source(filepath)
    end
  end
end

local function on_source_done(sourced)
  if sourced then
    vim.api.nvim_exec([[doautocmd <nomodeline> User ExrcDone]], false)
  end
end

function mod.source(filepath)
  local cached_result = cache.get(filepath)

  if cached_result and not cached_result.allowed then
    return on_source_done(false)
  end

  local current_hash = file_hash(filepath)

  if cached_result and cached_result.hash == current_hash then
    vim.cmd("source " .. filepath)
    return on_source_done(true)
  end

  local relative_filepath = vim.fn.fnamemodify(filepath, ":.")

  local title = "[Config Changed: " .. relative_filepath .. "]"
  if not cached_result then
    title = "[Config Unknown: " .. relative_filepath .. "]"
  end

  local action = {
    allow = function()
      cache.set(filepath, { allowed = true, hash = current_hash })
      vim.cmd("source " .. filepath)
      return on_source_done(true)
    end,

    disallow = function()
      cache.set(filepath, { allowed = false, hash = current_hash })
      return on_source_done(false)
    end,

    open = function()
      vim.cmd(
        string.format(
          "tabedit +%s %s",
          string.gsub(
            string.format(
              [[set nohidden | autocmd BufWinLeave <buffer> ++once :lua require("exrc").source("%s")]],
              filepath
            ),
            " ",
            "\\ "
          ),
          relative_filepath
        )
      )
    end,
  }

  local items = {
    Menu.item("[A]llow", { action = "allow", key = "a" }),
    Menu.item("[D]isallow", { action = "disallow", key = "d" }),
    Menu.item("[C]lose", { action = "close", key = "c" }),
    Menu.item("[O]pen", { action = "open", key = "o" }),
  }

  local menu = Menu({
    relative = "editor",
    border = {
      style = "rounded",
      text = {
        top = title,
      },
    },
    position = {
      row = "50%",
      col = "50%",
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    lines = items,
    min_width = #title + 2,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    },
    on_submit = function(item)
      if item.action and action[item.action] then
        action[item.action]()
      end
    end,
  })

  menu:on("BufLeave", function()
    menu:unmount()
  end, { once = true })

  local map_options = { noremap = true, nowait = true }

  for _, item in ipairs(items) do
    menu:map("n", item.key, function()
      menu:unmount()

      if item.action and action[item.action] then
        action[item.action]()
      end
    end, map_options)
  end

  menu:mount()
end

return mod
