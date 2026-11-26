local mod = get_mod("boneforge-observer")

local WalletSettings = require("scripts/settings/wallet_settings")
local Items = require("scripts/utilities/items")
local samples = setmetatable({}, { __mode = "k" })
local wallet_scope = {}
local quotes = setmetatable({}, { __mode = "k" })
local pending_reads = setmetatable({}, { __mode = "k" })
local talent_views = setmetatable({}, { __mode = "k" })
local purchase_number = 0

local function observe(view, key, value, context, source)
    if type(value) ~= "number" then
        return
    end

    local values = samples[view]
    if not values or values.context ~= context then
        values = { context = context }
        samples[view] = values
    end

    local previous = values[key]
    if previous == value then
        return
    end
    values[key] = value

    if previous == nil then
        mod:info("display baseline %s=%d source=%s", key, value, source)
    else
        mod:info("display change %s=%d previous=%d delta=%+d source=%s", key, value, previous, value - previous, source)
    end
end

local function observe_balance(currency, wallet, source)
    if not wallet or not wallet.balance or not WalletSettings[currency] then
        return
    end
    local player = Managers.player and Managers.player:local_player(1)
    local character = player and player:character_id()
    observe(wallet_scope, currency, wallet.balance.amount, character, source)
end

mod:hook_safe("ViewElementWallet", "_get_wallet_text_size", function(view, widget, currency)
    if mod:get("observe_wallet") then
        observe_balance(currency, view:get_wallet_by_type(currency), "wallet")
    end
end)

mod:hook_safe("InventoryView", "_update_wallets_presentation", function(view, data, hidden)
    if not mod:get("observe_wallet") or hidden or not view._is_own_player or not data then
        return
    end
    for currency, settings in pairs(WalletSettings) do
        if settings.show_in_character_menu then
            observe_balance(currency, data:by_type(currency), "inventory")
        end
    end
end)

mod:hook_safe("CraftingView", "_update_wallets_presentation", function(view, data)
    if mod:get("observe_wallet") and data then
        for _, currency in ipairs(view._wallet_type or {}) do
            observe_balance(currency, data:by_type(currency), "crafting")
        end
    end
end)

local function armoury_wallet(_, data)
    if data and mod:get("observe_wallet") then
        observe_balance("credits", data:by_type("credits"), "armoury")
    end
end
mod:hook_safe("CreditsVendorBackgroundView", "_update_wallets_presentation", armoury_wallet)

local function record_quote(view, offer)
    quotes[view] = nil
    local amount = offer and offer.price and offer.price.amount
    if not mod:get("observe_wallet") or not amount or amount.type ~= "credits" then return end
    local box = view._widgets_by_name and view._widgets_by_name.info_box
    local name = view._previewed_item and Items.display_name(view._previewed_item)
    quotes[view] = {
        item = name or (box and box.content.header) or "unknown",
        price = amount.discounted_price or amount.amount,
        before = (view._current_balance and view._current_balance.credits)
            or (view._parent and view._parent:get_balance("credits")),
    }
end

local function record_purchase(view)
    local quote = quotes[view]
    quotes[view] = nil
    if not mod:get("observe_wallet") then return end
    quote = quote or {}
    purchase_number = purchase_number + 1
    local number = purchase_number
    local item = view._result_item and Items.display_name(view._result_item) or quote.item or "unknown"
    mod:info("armoury purchase #%d item=%s price=%s credits_before=%s", number, item,
        tostring(quote.price or "unknown"), tostring(quote.before or "unknown"))

    -- Both shop views refresh their wallet on success. Read that same refresh;
    -- another purchase may already be reflected in the balance it returns.
    local refresh = view._wallet_promise
    if not refresh then
        mod:info("armoury purchase #%d credits_after=unavailable", number)
        return
    end
    local pending = pending_reads[view] or {}
    pending_reads[view] = pending
    local overlaps = next(pending) ~= nil
    for id in pairs(pending) do pending[id] = true end
    pending[number] = overlaps
    refresh:next(function(data)
        if pending[number] == nil then return end
        local wallet = data and data:by_type("credits")
        local after = wallet and wallet.balance and wallet.balance.amount
        local source = pending[number] and "overlapping wallet refreshes" or "wallet refresh"
        pending[number] = nil
        mod:info("armoury purchase #%d credits_after=%s (%s)", number, tostring(after or "unavailable"), source)
    end):catch(function()
        if pending[number] == nil then return end
        pending[number] = nil
        mod:info("armoury purchase #%d credits_after=unavailable (wallet refresh failed)", number)
    end)
end

local function shop_closed(view)
    local pending = pending_reads[view] or {}
    for id in pairs(pending) do
        mod:info("armoury purchase #%d credits_after=unavailable (shop closed)", id)
        pending[id] = nil
    end
    pending_reads[view] = nil
    quotes[view] = nil
end

for _, class in ipairs({ "CreditsVendorView", "CreditsGoodsVendorView" }) do
    mod:hook_safe(class, "_purchase_item", record_quote)
    mod:hook_safe(class, "_on_purchase_complete", record_purchase)
    mod:hook_safe(class, "destroy", shop_closed)
end

mod:hook_safe("ConstantElementNotificationFeed", "event_add_notification_message", function(_, kind, data)
    if not mod:get("observe_notifications") then
        return
    end
    if kind == "currency" and type(data) == "table" and WalletSettings[data.currency] and type(data.amount) == "number" then
        mod:info("currency notice %s=%d", data.currency, data.amount)
    elseif kind == "alert" then
        local message = type(data) == "table" and data.text
        message = type(message) == "string" and message:gsub("%c", " "):sub(1, 200) or "(no text)"
        mod:info("UI alert: %s", message)
    end
end)

local function log_node(view, name, before, after)
    local node = view:active_layout_node_by_name(name)
    local talent = node and node.talent
    local label = type(talent) == "string" and talent or name
    local action = after > before and "allocated" or "refunded"
    local points = node and node.cost and (after - before) * node.cost
    mod:info("talent %s %s node=%s rank=%d->%d points=%s", action, label, name, before, after,
        points and string.format("%+d", points) or "unknown")
end

local function observe_nodes(view, layout)
    local tiers = view._node_widget_tiers
    if not tiers then return end
    local snapshot = talent_views[view]
    local preset = view._active_profile_preset_id
    local fresh = not snapshot or snapshot.layout ~= layout or snapshot.preset ~= preset
    if fresh then
        snapshot = { layout = layout, preset = preset, ranks = {} }
        talent_views[view] = snapshot
        samples[view] = nil
    end
    local ranks = snapshot.ranks
    for name, tier in pairs(tiers) do
        if type(tier) == "number" and tier ~= (ranks[name] or 0) then
            if not fresh then log_node(view, name, ranks[name] or 0, tier) end
            ranks[name] = tier
        end
    end
    for name, tier in pairs(ranks) do
        if tiers[name] == nil then
            if tier > 0 then log_node(view, name, tier, 0) end
            ranks[name] = nil
        end
    end
end

mod:hook_safe("TalentBuilderView", "update", function(view)
    if not mod:get("observe_talents") or not view._is_own_player or not view._preview_player then
        return
    end
    local layout = view:get_active_layout()
    local widget = view._widgets_by_name and view._widgets_by_name.talent_points
    if layout and widget and widget.content then
        observe_nodes(view, layout)
        observe(view, "available_talent_points", widget.content.text, layout, "talents")
    end
end)

local function reset()
    samples = setmetatable({}, { __mode = "k" })
    quotes = setmetatable({}, { __mode = "k" })
    talent_views = setmetatable({}, { __mode = "k" })
end
mod.on_setting_changed = reset
mod.on_enabled = reset
