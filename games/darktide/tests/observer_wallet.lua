-- Run from games/darktide. Exercise the actual hooks without a running game.
local hooks, messages = {}, {}
local character = "first"
local mod = {
    get = function() return true end,
    info = function(_, fmt, ...) messages[#messages + 1] = string.format(fmt, ...) end,
    hook_safe = function(_, class, method, fn) hooks[class .. "." .. method] = fn end,
}
local env = setmetatable({
    get_mod = function() return mod end,
    require = function(path)
        if path == "scripts/utilities/items" then
            return { display_name = function(item) return item.display_name end }
        end
        assert(path == "scripts/settings/wallet_settings")
        return { credits = { show_in_character_menu = true } }
    end,
    Managers = { player = { local_player = function()
        return { character_id = function() return character end }
    end } },
}, { __index = _G })
setfenv(assert(loadfile("boneforge-observer/scripts/mods/boneforge-observer/observer.lua")), env)()

local inventory = hooks["InventoryView._update_wallets_presentation"]
local crafting = hooks["CraftingView._update_wallets_presentation"]
local notice = hooks["ConstantElementNotificationFeed.event_add_notification_message"]
local wallet = { balance = { amount = 1000 } }
local data = { by_type = function(_, currency) if currency == "credits" then return wallet end end }
local owner = { _is_own_player = true }
inventory(owner, nil)
inventory({}, data)
inventory(owner, data, true)
inventory(owner, data)
crafting({ _wallet_type = { "credits" } }, data)
notice(nil, "currency", { currency = "credits", amount = 125 })
wallet.balance.amount = 1125
crafting({ _wallet_type = { "credits" } }, data)
inventory({ _is_own_player = true }, data)
hooks["ViewElementWallet._get_wallet_text_size"]({ get_wallet_by_type = data.by_type }, {}, "credits")
wallet.balance.amount = 0
inventory(owner, data)
character = "second"
inventory(owner, data)
notice(nil, "alert", { text = "First line\nsecond line" })

local expected = {
    "display baseline credits=1000 source=inventory",
    "currency notice credits=125",
    "display change credits=1125 previous=1000 delta=+125 source=crafting",
    "display change credits=0 previous=1125 delta=-1125 source=inventory",
    "display baseline credits=0 source=inventory",
    "UI alert: First line second line",
}
assert(#messages == #expected, "unexpected number of Observer messages")
for i, message in ipairs(expected) do assert(messages[i] == message, tostring(messages[i])) end
print("PASS Observer wallet changes, notices and alerts")

local function refresh()
    local result = {}
    function result:next(fn) self.resolve = fn; return self end
    function result:catch(fn) self.reject = fn; return self end
    return result
end

messages = {}
local shop = { _current_balance = { credits = 1000 }, _previewed_item = { display_name = "Axe" } }
local function buy(class, price)
    hooks[class .. "._purchase_item"](shop, { price = { amount = { type = "credits", amount = 500, discounted_price = price } } })
    shop._wallet_promise = refresh()
    hooks[class .. "._on_purchase_complete"](shop)
    return shop._wallet_promise
end
-- An unsuccessful selection has no receipt. Its quote is replaced on the next purchase.
hooks["CreditsVendorView._purchase_item"](shop, { price = { amount = {type="credits", amount=20} } })
local first = buy("CreditsVendorView", 125)
wallet.balance.amount = 875
first.resolve(data)
shop._current_balance.credits = 875
shop._result_item = { display_name = "Shock Maul" }
local second = buy("CreditsGoodsVendorView", 75)
local third = buy("CreditsGoodsVendorView", 50)
wallet.balance.amount = 750
third.resolve(data)
second.resolve(data)
buy("CreditsVendorView", 10).reject()
local last = buy("CreditsVendorView", 10)
hooks["CreditsVendorView.destroy"](shop)
last.resolve(data)
assert(#messages == 10)
assert(messages[1] == "armoury purchase #1 item=Axe price=125 credits_before=1000")
assert(messages[2] == "armoury purchase #1 credits_after=875 (wallet refresh)")
assert(messages[3] == "armoury purchase #2 item=Shock Maul price=75 credits_before=875")
assert(messages[5]:find("#3 credits_after=750 (overlapping wallet refreshes)", 1, true))
assert(messages[6]:find("#2 credits_after=750 (overlapping wallet refreshes)", 1, true))
assert(messages[8]:find("wallet refresh failed", 1, true))
assert(messages[10]:find("shop closed", 1, true))

messages = {}
local layout = {}
local talents = {
    _is_own_player = true, _preview_player = {}, _active_profile_preset_id = 1,
    _node_widget_tiers = { health = 1 }, _widgets_by_name = {talent_points={content={text=4}}},
    get_active_layout = function() return layout end,
    active_layout_node_by_name = function(_, name) return {talent=name.."_talent",cost=1} end,
}
local update = hooks["TalentBuilderView.update"]
update(talents)
talents._node_widget_tiers.health = 2
talents._widgets_by_name.talent_points.content.text = 3
update(talents)
update(talents)
talents._node_widget_tiers = { speed = 2 }
update(talents)
talents._active_profile_preset_id = 2
talents._node_widget_tiers = {}
update(talents)
local output = table.concat(messages, "\n")
assert(#messages == 6)
assert(output:find("talent allocated health_talent node=health rank=1->2 points=+1", 1, true))
assert(output:find("talent allocated speed_talent node=speed rank=0->2 points=+2", 1, true))
assert(output:find("talent refunded health_talent node=health rank=2->0 points=-2", 1, true))
print("PASS Observer Armoury receipts, overlapping refreshes, talent allocations and refunds")
