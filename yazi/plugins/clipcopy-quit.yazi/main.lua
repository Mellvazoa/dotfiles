--- @sync entry
local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

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

return {
	entry = function()
		local paths = {}
		for _, item in pairs(cx.active.selected) do
			paths[#paths + 1] = shell_quote(item_path(item))
		end
		if #paths == 0 and cx.active.current.hovered then
			paths[1] = shell_quote(item_path(cx.active.current.hovered))
		end
		if #paths == 0 then
			return
		end

		local bin = (os.getenv("HOME") or "") .. "/.local/bin/filecopy"
		local cmd = shell_quote(bin) .. " " .. table.concat(paths, " ") .. " >/dev/null 2>&1"
		local ok = os.execute(cmd)
		if not ok then
			ya.notify { title = "Clipboard", content = "Failed to copy files", timeout = 2.5, level = "error" }
		end
	end,
}
