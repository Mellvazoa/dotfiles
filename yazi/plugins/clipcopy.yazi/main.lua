local function item_path(item)
	if type(item) == "string" then
		return item
	end
	local ok_url, url = pcall(function() return item.url end)
	if ok_url and url ~= nil then
		return tostring(url)
	end
	return tostring(item)
end

local get_paths = ya.sync(function()
	local paths = {}
	for _, item in pairs(cx.active.selected) do
		paths[#paths + 1] = item_path(item)
	end
	if #paths == 0 and cx.active.current.hovered then
		paths[1] = item_path(cx.active.current.hovered)
	end
	return paths
end)

return {
	entry = function(_, job)
		local paths = get_paths()
		if #paths == 0 then
			return
		end

		local bin = (os.getenv("HOME") or "") .. "/.local/bin/filecopy"
		local status = Command(bin):arg(paths):status()
		if not status or not status.success then
			ya.notify { title = "Clipboard", content = "Failed to copy files", timeout = 2.5, level = "error" }
			return
		end

		if job.args[1] == "quit" or job.args.quit then
			ya.emit("quit", {})
		else
			ya.notify {
				title = "Clipboard",
				content = string.format("Copied %d file(s) — Cmd+V to paste", #paths),
				timeout = 2.0,
				level = "info",
			}
		end
	end,
}
