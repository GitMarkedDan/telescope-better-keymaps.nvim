local defaults = require("telescope-better-keymaps.default_keymaps")

local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local utils = require("telescope.utils")
local sorters = require("telescope.sorters")
local make_entry = require("telescope.make_entry")

local function list_contains(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

local function shallow_copy(t)
    local ret = {}
    for i, v in pairs(t) do
        ret[i] = v
    end
    return ret
end

local function load_lazy_nvim_keys()
    local has_lazy, _ = pcall(require, 'lazy')
    if not has_lazy then
        warn("Cannot `require('lazy')`, empty keymap data will be used instead.")
        return {}
    end

    local lazy_keymaps = {}

    local LazyNvimConfig = require('lazy.core.config')
    local Handler = require('lazy.core.handler')
    for _, plugin in pairs(LazyNvimConfig.plugins) do
        local keys = Handler.handlers.keys:values(plugin)
        for _, keymap in pairs(keys) do
            if keymap.desc and #keymap.desc > 0 then
                lazy_keymaps[keymap[1]] = {
                    desc = keymap.desc,
                    mode = keymap.mode, ---@type string|string[]|nil
                }
            end
        end
    end
end

local FAKE_BUF = "<Plug>"

return require("telescope").register_extension({
    exports = {
        _picker = function(opts)
            opts = opts or {}

            opts.modes = vim.F.if_nil(opts.modes, { "n", "i", "c", "x" })
            opts.show_plug = vim.F.if_nil(opts.show_plug, false)
            opts.only_buf = vim.F.if_nil(opts.only_buf, false)

            local plug_dict = {}
            local cached_plugs = {}
            local keymap_encountered = {} -- used to make sure no duplicates are inserted into keymaps_table
            local keymaps_table = {}
            local max_len_lhs = 0

            local lazy_data = opts.use_lazy and load_lazy_nvim_keys() or {}

            local function test_keymap(keymap, do_plug_check)
                do_plug_check = do_plug_check or not opts.show_plug
                local keymap_key = keymap.buffer .. keymap.mode .. keymap.lhs -- should be distinct for every keymap
                if not keymap_encountered[keymap_key] then
                    keymap_encountered[keymap_key] = true
                    if (not opts.lhs_filter or opts.lhs_filter(keymap.lhs)) and (not opts.filter or opts.filter(keymap)) then
                        if do_plug_check and string.find(keymap.lhs, "<Plug>") then
                            table.insert(cached_plugs, keymap)
                        elseif do_plug_check and keymap.rhs and string.find(keymap.rhs, "<Plug>") then
                            plug_dict[keymap.rhs] = keymap.lhs
                        else
                            if not keymap.desc and lazy_data[keymap.desc] then
                                keymap.desc = lazy_data[keymap].desc
                            end
                            table.insert(keymaps_table, keymap)
                            max_len_lhs = math.max(max_len_lhs, #utils.display_termcodes(keymap.lhs))
                        end
                    end
                end
            end

            for _, keymap in pairs(defaults) do
                if list_contains(opts.modes, keymap.mode) then
                    if type(keymap.lhs) == "table" then
                        for _, keymap_type in ipairs(keymap) do
                            local temp_keymap = shallow_copy(keymap)
                            temp_keymap.buffer = FAKE_BUF
                            temp_keymap.lhs = keymap_type
                            test_keymap(temp_keymap)
                        end
                    else
                        keymap.buffer = FAKE_BUF
                        test_keymap(keymap)
                    end
                end
            end

            for _, mode in pairs(opts.modes) do
                for _, keymap in pairs(vim.api.nvim_buf_get_keymap(0, mode)) do
                    test_keymap(keymap)
                end
                if not opts.only_buf then
                    for _, keymap in pairs(vim.api.nvim_get_keymap(mode)) do
                        test_keymap(keymap)
                    end
                end
            end

            -- this will be nil if plug is not true, so its just fine if we loop through
            for _, keymap in ipairs(cached_plugs) do
                if plug_dict[keymap.lhs] then
                    if not keymap.desc then
                        keymap.desc = string.sub(keymap.lhs, 7, -1)
                    end
                    local temp_keymap = shallow_copy(keymap)
                    temp_keymap.lhs = plug_dict[keymap.lhs]
                    temp_keymap.buffer = ""
                    test_keymap(temp_keymap, false)
                else
                    test_keymap(keymap)
                end
            end

            opts.width_lhs = max_len_lhs + 1

            pickers.new(opts, {
                prompt_title = "Key Maps",
                finder = finders.new_table {
                    results = keymaps_table,
                    entry_maker = opts.entry_maker or make_entry.gen_from_keymaps(opts),
                },
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(prompt_bufnr)
                    actions.select_default:replace(function()
                        local selection = action_state.get_selected_entry()
                        if selection == nil then
                            utils.__warn_no_selection("better-keymaps")
                            return
                        end
                        actions.close(prompt_bufnr)
                        local keys = selection.value.lhs
                        if selection.value.incomplete then
                            keys = keys:gsub("{c}", function()
                                vim.print("Input any character: ")
                                return vim.fn.getcharstr()
                            end)
                            keys = keys:gsub("{n}", function()
                                vim.print("Input a number (0-9): ")
                                local input = tostring(tonumber(vim.fn.getcharstr()))
                                if not input then
                                    error("Not a valid number!")
                                end
                                return input
                            end)
                            keys = keys:gsub("{r}", function()
                                vim.print("Input a register (0-9)/(a-Z)/(*+:.%#=*+_/): ")
                                local input = vim.fn.getcharstr()
                                if not input:match("[0-9a-Z*+:.%#=*+_/]") then
                                    error("Not a valid register!")
                                end
                                return input
                            end)
                            keys:gsub("{P}", "")
                        end
                        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "t", true)
                    end)
                    return true
                end,
            }):find()
        end
    }
})
