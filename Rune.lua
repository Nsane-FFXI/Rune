_addon.name     = 'Rune'
_addon.author   = 'Nsane'
_addon.version  = '2025.9.3'
_addon.commands = {'ru', 'rune'}

require('tables')
require('strings')
local config  = require('config')
local res     = require('resources')
local texts   = require('texts')

-- =====================
-- Settings
-- =====================
local defaults = {
    pos   = {x = 300, y = 300},
    font  = {name = 'Consolas', size = 12, bold = false},
    bg    = {alpha = 255},
    show_empty = false, -- reserved for future use
    durations = {Rayke = 48, Gambit = 96},
    colors = {
        dark      = { 92,  92,  92},
        earth     = {255, 255,  28},
        ice       = {  0, 255, 255},
        light     = {255, 255, 255},
        water     = {  0, 150, 255},
        wind      = { 51, 255,  20},
        fire      = {255,  22,  12},
        lightning = {233,   0, 255},
        neutral   = {200, 200, 200},
    },
}
local settings = config.load(defaults)

-- =====================
-- UI helpers
-- =====================
local function cs(rgb, s) return ('\\cs(%d,%d,%d)%s\\cr'):format(rgb[1], rgb[2], rgb[3], s) end

local box = texts.new()
box:pos(settings.pos.x, settings.pos.y)
box:font(settings.font.name)
box:size(settings.font.size)
box:bold(settings.font.bold)
box:bg_alpha(settings.bg.alpha)
box:draggable(true)
box:hide()

-- =====================
-- State
-- =====================
local ELEMENT_BUFFS = {
    Ignis='fire', Gelus='ice', Flabra='wind', Tellus='earth',
    Sulpor='lightning', Unda='water', Lux='light', Tenebrae='dark',
}

local timers = {
    Rayke  = {ends=0, color=settings.colors.neutral, color2=nil},
    Gambit = {ends=0, color=settings.colors.neutral, color2=nil},
}

local function now() return os.time() end

-- cached accessors
local function me() return windower.ffxi.get_player() end
local function my_name() local p = me() return p and p.name or nil end
local function my_id() local p = me() return p and p.id or nil end

-- =====================
-- Color + label utilities
-- =====================
local function lerp(a,b,t) return a + (b-a)*t end
local function lerp_rgb(c1,c2,t)
    return {
        math.floor(lerp(c1[1], c2[1], t)),
        math.floor(lerp(c1[2], c2[2], t)),
        math.floor(lerp(c1[3], c2[3], t))
    }
end

local function gradient_label(text, c1, c2)
    if not c2 then return cs(c1, text) end
    local n = math.max(6, math.min(#text, 18))
    local chunk_len = math.max(1, math.floor(#text / n))
    local i, out = 1, {}
    local denom = math.max(1, #text-1)
    while i <= #text do
        local j = math.min(#text, i + chunk_len - 1)
        local t = (i-1) / denom
        local rgb = lerp_rgb(c1, c2, t)
        out[#out+1] = cs(rgb, text:sub(i, j))
        i = j + 1
    end
    return table.concat(out)
end

-- =====================
-- Rune color detection
-- =====================
local function detect_rune_colors_at_cast()
    local p = me()
    if not p or not p.buffs then return settings.colors.neutral, nil end

    local tally = {}
    for _, bid in ipairs(p.buffs) do
        local b = bid and res.buffs and res.buffs[bid]
        if b and b.en then
            local elem = ELEMENT_BUFFS[b.en]
            if elem then tally[elem] = (tally[elem] or 0) + 1 end
        end
    end
    if next(tally) == nil then return settings.colors.neutral, nil end

    local arr = {}
    for k, c in pairs(tally) do arr[#arr+1] = {k=k, c=c} end
    table.sort(arr, function(a,b) return a.c > b.c end)

    local c1 = settings.colors[arr[1].k] or settings.colors.neutral
    local c2 = arr[2] and arr[2].k and settings.colors[arr[2].k] or nil
    return c1, c2
end

-- =====================
-- Render
-- =====================
local function fmt_time(remain)
    if remain < 0 then remain = 0 end
    return tostring(remain)
end

local function any_active(tnow)
    tnow = tnow or now()
    return (timers.Rayke.ends > tnow) or (timers.Gambit.ends > tnow)
end

local function rebuild_text()
    local tnow = now()
    local lines = {}

    local function line_for(name, T)
        local remain = math.max(0, T.ends - tnow)
        if remain <= 0 then return nil end
        local label = gradient_label(name, T.color or settings.colors.neutral, T.color2)
        return ('%s %ss'):format(label, fmt_time(remain))
    end

    local l1 = line_for('---Rayke---',  timers.Rayke)
    local l2 = line_for('---Gambit--', timers.Gambit)
    if l1 then lines[#lines+1] = l1 end
    if l2 then lines[#lines+1] = l2 end

    if #lines == 0 then
        box:text('')
        box:hide()
    else
        box:text(table.concat(lines, '\n'))
        box:show()
    end
end

-- Throttle UI updates to reduce cost
local last_draw = 0
local draw_interval = 0.10 -- seconds

windower.register_event('prerender', function()
    if not any_active() then
        if box:visible() then box:hide() end
        return
    end
    local t = os.clock()
    if t - last_draw >= draw_interval then
        last_draw = t
        rebuild_text()
    end
end)

-- =====================
-- Triggers
-- =====================
local function trigger(name)
    local c1, c2 = detect_rune_colors_at_cast()
    local dur = settings.durations[name] or 45
    timers[name].ends   = now() + dur
    timers[name].color  = c1
    timers[name].color2 = c2
    rebuild_text()
end

-- =====================
-- Detection: chat text
-- =====================
windower.register_event('incoming text', function(original, modified, mode)
    local n = my_name()
    if not n then return end
    local line = original or ''
    -- quick filter to avoid pattern work if name not present
    if not line:find(n, 1, true) or not line:find(' uses ', 1, true) then return end

    if line:find('%f[%a]Rayke%f[%A]') then
        trigger('Rayke')
    elseif line:find('%f[%a]Gambit%f[%A]') then
        trigger('Gambit')
    end
end)

-- =====================
-- Detection: action packet
-- =====================
windower.register_event('action', function(act)
    if not act then return end
    local pid = my_id()
    if not pid or act.actor_id ~= pid then return end
    local ja_id = act.param
    if not ja_id then return end
    local ja = res.job_abilities and res.job_abilities[ja_id]
    if not ja or not ja.en then return end

    if ja.en == 'Rayke' then
        trigger('Rayke')
    elseif ja.en == 'Gambit' then
        trigger('Gambit')
    end
end)

-- =====================
-- Commands
-- =====================
windower.register_event('addon command', function(cmd, a1, a2)
    cmd = (cmd or ''):lower()

    if cmd == 'test' and a1 then
        local n = a1:lower()
        if n == 'rayke' then
            trigger('Rayke')
        elseif n == 'gambit' then
            trigger('Gambit')
        end

    elseif cmd == 'dur' and a1 and a2 then
        local n = a1:gsub('^%l', string.upper)
        local v = tonumber(a2)
        if (n == 'Rayke' or n == 'Gambit') and v and v > 0 then
            settings.durations[n] = v
            config.save(settings)
            rebuild_text()
        end

    elseif cmd == 'pos' and a1 and a2 then
        local x = tonumber(a1)
        local y = tonumber(a2)
        if x and y then
            settings.pos.x, settings.pos.y = x, y
            config.save(settings)
            box:pos(x, y)
        end
    end
end)

-- =====================
-- Lifecycle
-- =====================
windower.register_event('load', function()
    box:pos(settings.pos.x, settings.pos.y)
    box:font(settings.font.name)
    box:size(settings.font.size)
    box:bold(settings.font.bold)
    box:bg_alpha(settings.bg.alpha)
    box:hide()
end)

local function reset_all()
    timers.Rayke.ends, timers.Gambit.ends = 0, 0
    box:hide()
    box:text('')
end

windower.register_event('zone change', reset_all)

windower.register_event('logout', reset_all)
