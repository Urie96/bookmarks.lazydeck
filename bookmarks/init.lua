local M = {}

function M.meta()
  return {
    icon = '󰃀',
    desc = 'Bookmark manager',
    color = 'yellow',
  }
end

local NAMESPACE = 'bookmarks.lazydeck'
local CACHE_KEY = 'bookmarks'

local defaults = {
  keymap = {
    delete = 'dd',
    open = '<enter>',
  },
}

local state = {
  config = defaults,
  setup_done = false,
}

local function deepcopy(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deepcopy(v)
  end
  return copy
end

local function path_to_key(path)
  if not path or #path == 0 then return '/' end
  return '/' .. table.concat(path, '/')
end

local function path_display(path)
  return path_to_key(path)
end

local function copy_path(path)
  local copied = {}
  for i, value in ipairs(path or {}) do
    copied[i] = tostring(value)
  end
  return copied
end

local function normalize_store(store)
  if type(store) ~= 'table' then return {} end

  local normalized = {}
  for key, bookmark in pairs(store) do
    if type(bookmark) == 'table' and type(bookmark.path) == 'table' then
      local path = copy_path(bookmark.path)
      local bookmark_key = path_to_key(path)
      normalized[bookmark_key] = {
        key = bookmark_key,
        path = path,
        title = bookmark.title or bookmark_key,
        created_at = tonumber(bookmark.created_at) or deck.time.now(),
        updated_at = tonumber(bookmark.updated_at) or tonumber(bookmark.created_at) or deck.time.now(),
        last_accessed_at = tonumber(bookmark.last_accessed_at) or 0,
      }
    elseif type(key) == 'string' and type(bookmark) == 'table' then
      normalized[key] = bookmark
    end
  end

  return normalized
end

local function load_bookmarks()
  return normalize_store(deck.cache.get(NAMESPACE, CACHE_KEY))
end

local function save_bookmarks(bookmarks)
  deck.cache.set(NAMESPACE, CACHE_KEY, bookmarks)
end

local function is_bookmarks_page(path)
  return path and path[1] == 'bookmarks'
end

local function add_current_page()
  local path = deck.api.get_current_path()
  if is_bookmarks_page(path) then
    deck.notify('Bookmarks page is not added')
    return
  end

  local now = deck.time.now()
  local key = path_to_key(path)
  local bookmarks = load_bookmarks()
  local existing = bookmarks[key]

  bookmarks[key] = {
    key = key,
    path = copy_path(path),
    title = path_display(path),
    created_at = existing and existing.created_at or now,
    updated_at = now,
    last_accessed_at = existing and existing.last_accessed_at or 0,
  }

  save_bookmarks(bookmarks)
  deck.notify('Bookmarked ' .. key)
end

local function delete_bookmark(bookmark)
  local bookmarks = load_bookmarks()
  bookmarks[bookmark.bookmark_key] = nil
  save_bookmarks(bookmarks)
  deck.notify('Deleted bookmark ' .. bookmark.bookmark_key)
  deck.cmd 'reload'
end

local function open_bookmark(bookmark)
  local bookmarks = load_bookmarks()
  local stored = bookmarks[bookmark.bookmark_key]
  if stored then
    stored.last_accessed_at = deck.time.now()
    bookmarks[bookmark.bookmark_key] = stored
    save_bookmarks(bookmarks)
  end
  deck.api.go_to(copy_path(bookmark.path))
end

local function entry_display(bookmark)
  local last = bookmark.last_accessed_at and bookmark.last_accessed_at > 0
      and deck.time.format(bookmark.last_accessed_at, 'relative')
    or 'never'

  return deck.style.line {
    deck.style.span(bookmark.key):fg 'cyan',
    deck.style.span('  last: '):fg 'dark_gray',
    deck.style.span(last):fg 'yellow',
  }
end

local function build_entries()
  local bookmarks = load_bookmarks()
  local list = {}

  for key, bookmark in pairs(bookmarks) do
    bookmark.key = key
    table.insert(list, bookmark)
  end

  table.sort(list, function(a, b)
    local a_last = tonumber(a.last_accessed_at) or 0
    local b_last = tonumber(b.last_accessed_at) or 0
    if a_last ~= b_last then return a_last > b_last end
    return tostring(a.key) < tostring(b.key)
  end)

  local entries = {}
  if #list == 0 then
    return {
      {
        key = '__empty__',
        kind = 'info',
        display = deck.style.line {
          deck.style.span('No bookmarks yet. '):fg 'yellow',
          deck.style.span('Use a configured global key to add the current page.'):fg 'dark_gray',
        },
      },
    }
  end

  for _, bookmark in ipairs(list) do
    local entry = {
      key = bookmark.key,
      bookmark_key = bookmark.key,
      path = copy_path(bookmark.path),
      display = entry_display(bookmark),
      keymap = {},
    }

    entry.keymap[state.config.keymap.open] = {
      desc = 'open bookmark',
      callback = function() open_bookmark(entry) end,
    }
    entry.keymap['<right>'] = {
      desc = 'open bookmark',
      callback = function() open_bookmark(entry) end,
    }
    entry.keymap[state.config.keymap.delete] = {
      desc = 'delete bookmark',
      callback = function() delete_bookmark(entry) end,
    }

    table.insert(entries, entry)
  end

  return entries
end

function M.setup(opt)
  state.config = deck.tbl_deep_extend('force', deepcopy(defaults), opt or {})

  if state.setup_done then return end
  state.setup_done = true

end

M.add = add_current_page

function M.list(path, cb)
  if #path == 1 then
    cb(build_entries())
    return
  end

  cb({})
end

function M.preview(entry, cb)
  if not entry then return end

  if entry.kind == 'info' then
    cb(deck.style.text {
      deck.style.line { deck.style.span('No bookmarks yet'):fg('yellow'):bold() },
      deck.style.line { '' },
      deck.style.line { 'Navigate to any page and use your configured global key to add it.' },
    })
    return
  end

  cb(deck.style.text {
    deck.style.line { deck.style.span('Bookmark'):fg('yellow'):bold() },
    deck.style.line { 'Path: ', deck.style.span(entry.bookmark_key or entry.key):fg 'cyan' },
    deck.style.line { '' },
    deck.style.line { deck.style.span('Actions'):fg 'green' },
    deck.style.line { state.config.keymap.delete .. '  delete bookmark' },
  })
end

return M
