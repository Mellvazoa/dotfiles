local compact_mode = {
  is_compact = false,
  callbacks = {},
}

sbar.add("event", "compact_mode_change")

function compact_mode.set(compact)
  compact = not not compact
  if compact_mode.is_compact == compact then return end
  compact_mode.is_compact = compact

  sbar.trigger("compact_mode_change", { compact = compact and "on" or "off" })

  for _, cb in ipairs(compact_mode.callbacks) do
    cb(compact)
  end
end

function compact_mode.on_change(cb)
  table.insert(compact_mode.callbacks, cb)
  cb(compact_mode.is_compact)
end

return compact_mode
