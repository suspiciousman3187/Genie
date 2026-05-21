_addon.name = 'Genie'
_addon.author = 'A Man In Black'
_addon.version = '1.0'
_addon.commands = {'Genie','genie','ge','gn'}
_addon.language = 'english'

packets = require('packets')
config = require('config')
texts = require('texts')
require('pack')
require('chat')
local bit = require('bit')

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
defaults = {}
defaults.auto_solve = false
defaults.auto_warp_nm = false
defaults.auto_warp_all = false
defaults.auto_warp_family = false
defaults.auto_warp_single = false
defaults.rune_runner = ''
defaults.hud = {
    pos = { x = 144, y = 144 },
    text = { font = 'Segoe UI', size = 12, alpha = 255, red = 188, green = 131, blue = 246 },
    bg = { alpha = 175, red = 50, green = 50, blue = 50 },
}

settings = config.load(defaults)

function genie_state_path()
    local p = windower.ffxi.get_player()
    local name = (p and p.name and p.name ~= '') and p.name:lower() or 'default'
    return windower.addon_path .. 'data/genie_state_' .. name .. '.lua'
end

genie_state_debug = false

function genie_state_load()
    local path = genie_state_path()
    local f = io.open(path, 'r')
    if not f then
        if genie_state_debug then windower.add_to_chat(167, ('Genie LOAD: %s does not exist'):format(path)) end
        return {}
    end
    local body = f:read('*a')
    f:close()
    if not body or body == '' then return {} end
    local chunk, err = loadstring(body)
    if not chunk then
        if genie_state_debug then windower.add_to_chat(167, ('Genie LOAD: parse error: %s'):format(tostring(err))) end
        return {}
    end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= 'table' then
        if genie_state_debug then windower.add_to_chat(167, ('Genie LOAD: exec error: %s'):format(tostring(t))) end
        return {}
    end
    if genie_state_debug then
        windower.add_to_chat(200, ('Genie LOAD [%s]: auto_solve=%s warp[nm=%s all=%s family=%s single=%s] runner=%s'):format(
            path, tostring(t.auto_solve), tostring(t.auto_warp_nm), tostring(t.auto_warp_all),
            tostring(t.auto_warp_family), tostring(t.auto_warp_single), tostring(t.rune_runner)))
    end
    return t
end

function genie_state_save(t)
    local path = genie_state_path()
    local f, err = io.open(path, 'w')
    if not f then
        windower.add_to_chat(167, ('Genie SAVE: open FAILED: %s'):format(tostring(err)))
        return false
    end
    f:write('return {\n')
    f:write(('    auto_solve       = %s,\n'):format(tostring(t.auto_solve == true)))
    f:write(('    auto_warp_nm     = %s,\n'):format(tostring(t.auto_warp_nm == true)))
    f:write(('    auto_warp_all    = %s,\n'):format(tostring(t.auto_warp_all == true)))
    f:write(('    auto_warp_family = %s,\n'):format(tostring(t.auto_warp_family == true)))
    f:write(('    auto_warp_single = %s,\n'):format(tostring(t.auto_warp_single == true)))
    f:write(('    rune_runner      = %q,\n'):format(t.rune_runner or ''))
    f:write('}\n')
    f:close()
    if genie_state_debug then
        windower.add_to_chat(200, ('Genie SAVE [%s]: auto_solve=%s warp[nm=%s all=%s family=%s single=%s] runner=%s'):format(
            path, tostring(t.auto_solve == true), tostring(t.auto_warp_nm == true), tostring(t.auto_warp_all == true),
            tostring(t.auto_warp_family == true), tostring(t.auto_warp_single == true), tostring(t.rune_runner)))
    end
    return true
end

local _loaded_state = genie_state_load()
if _loaded_state.auto_solve       ~= nil then settings.auto_solve       = _loaded_state.auto_solve       end
if _loaded_state.auto_warp_nm     ~= nil then settings.auto_warp_nm     = _loaded_state.auto_warp_nm     end
if _loaded_state.auto_warp_all    ~= nil then settings.auto_warp_all    = _loaded_state.auto_warp_all    end
if _loaded_state.auto_warp_family ~= nil then settings.auto_warp_family = _loaded_state.auto_warp_family end
if _loaded_state.auto_warp_single ~= nil then settings.auto_warp_single = _loaded_state.auto_warp_single end
if _loaded_state.rune_runner      ~= nil then settings.rune_runner      = _loaded_state.rune_runner      end
if genie_state_debug then
    windower.add_to_chat(200, ('Genie INIT: settings after load: auto_solve=%s warp[nm=%s all=%s family=%s single=%s] runner=%s'):format(
        tostring(settings.auto_solve), tostring(settings.auto_warp_nm), tostring(settings.auto_warp_all),
        tostring(settings.auto_warp_family), tostring(settings.auto_warp_single), tostring(settings.rune_runner)))
end

function settings_save()
    genie_state_save(settings)
    pcall(function() settings:save('all') end)
end

genie_settings = settings

-------------------------------------------------------------------------------
-- HUD text box
-------------------------------------------------------------------------------
local tb_ok, text_box = pcall(texts.new, settings.hud, settings)
if not tb_ok or not text_box then
    text_box = setmetatable({}, { __index = function() return function() end end })
end

-------------------------------------------------------------------------------
-- Constants: fixed entity indices in Nyzul Isle (zone 77)
-------------------------------------------------------------------------------
local SORTED_INDEXES      = { 0x2D2, 0x2D3, 0x2D4, 0x2D5, 0x2D6, 0x2D7, 0x2D8 }
local SORTED_LAMP_INDEXES = { 0x2D4, 0x2D5, 0x2D6, 0x2D7, 0x2D8 }
local RUNE_INDICES         = { 0x2D2, 0x2D3 }

local LAMP_INDEX_TO_NUM = {
    [0x2D4] = 1, [0x2D5] = 2, [0x2D6] = 3, [0x2D7] = 4, [0x2D8] = 5,
}

local tLamps = {
    [0x2D4] = {}, [0x2D5] = {}, [0x2D6] = {},
    [0x2D7] = {}, [0x2D8] = {},
    [0x2D2] = {}, [0x2D3] = {},
}

-------------------------------------------------------------------------------
-- Known Nyzul NM names for "Eliminate enemy leader" objective
-------------------------------------------------------------------------------
local NYZUL_NMS = {
    'Long-Gunned Chariot', 'Long-Horned Chariot', 'Battledressed Chariot', 'Shielded Chariot',
    'Anise Custard', 'Caraway Custard', 'Cinnamon Custard', 'Cumin Custard', 'Ginger Custard', 'Nutmeg Custard', 'Mint Custard',
    'Mokka', 'Mokke', 'Mokku',
    'Eriri Samariri', 'Oriri Samariri', 'Uriri Samariri',
    'Vile Ineef', 'Vile Wahdaha', 'Vile Yabeewa',
    'Gem Heister Roorooroon', 'Quick Draw Sasaroon', 'Stealth Bomber Gagaroon',
}
local NYZUL_NM_SET = {}
for _, name in ipairs(NYZUL_NMS) do NYZUL_NM_SET[name] = true end

-------------------------------------------------------------------------------
-- DAT-based NM lookup
-------------------------------------------------------------------------------
local NYZUL_DATS = { 'ROM4\\1\\76.DAT' }
local FFXI_PATH  = 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix\\FINAL FANTASY XI\\'

local nm_dat_indices = nil

local function dat_find(name_to_find)
    local results = {}
    for _, dat_path in ipairs(NYZUL_DATS) do
        local file = io.open(FFXI_PATH .. dat_path, 'rb')
        if file then
            while true do
                local data = file:read(32)
                if not data or #data < 32 then break end
                local name = ''
                for i = 1, 28 do
                    local c = data:byte(i)
                    if c and c ~= 0 then name = name .. string.char(c) end
                end
                local id = data:unpack('I', 29)
                local index = bit.band(id, 0xFFF)
                if name:lower():find(name_to_find:lower(), 1, true) then
                    results[#results+1] = { name = name, id = id, index = index }
                end
            end
            file:close()
        end
    end
    return results
end

local function get_nm_dat_indices()
    if nm_dat_indices then return nm_dat_indices end
    nm_dat_indices = {}
    for _, nm_name in ipairs(NYZUL_NMS) do
        local results = dat_find(nm_name)
        for _, r in ipairs(results) do
            if r.name == nm_name then
                nm_dat_indices[nm_name] = r.index
            end
        end
    end
    return nm_dat_indices
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
debugmode          = false
currentZone        = 0
lastZone           = 0
eventClock         = nil
clock              = os.clock()
scanClock          = os.clock()
needLampScan       = false
lampCount          = 0
lampFloorDetected  = false
currentFloorRuneFilter = 0
objectiveCompleted = false

check_cache     = {}
check_queue     = {}
check_current   = nil
check_last_time = 0

eliminate_leader_floor = false
eliminate_leader       = nil
defeated_nm_set        = {}

archaic_gear_warning = nil
time_penalty_minutes = 0

has_armband      = false
party_size       = 1
starting_floor   = 0
floors_completed = 0
floor_penalties  = 0
potential_tokens = 0

current_objective = nil

current_floor_number = 0
local BOSS_FLOORS = { [20] = true, [40] = true, [60] = true, [80] = true, [100] = true }
local function is_boss_floor()
    return BOSS_FLOORS[current_floor_number] == true
end

simultaneous_floor = false
simultaneous_lamps = {}
simultaneous_step  = 0

eliminate_all_floor = false

ws_cache = {
    last_refresh = 0,
    refresh_interval = 15.0,
    mobs = {},
}

specified_enemy_floor = false
specified_enemy_list  = {}
specified_enemy       = nil

specified_enemies_floor = false
specified_enemies_family = nil
specified_enemies_name  = nil
specified_enemies_name_slug = nil
specified_enemies_list  = {}

local FAMILY_GROUPS = {
    Chariots    = {
        'Racing Chariot',
        'Long-Gunned Chariot', 'Long-Horned Chariot', 'Battledressed Chariot', 'Shielded Chariot',
    },
    Flans       = {
        'Ebony Pudding',
        'Anise Custard', 'Caraway Custard', 'Cinnamon Custard', 'Cumin Custard', 'Ginger Custard', 'Nutmeg Custard', 'Mint Custard',
    },
    Imps        = {
        'Heraldic Imp',
        'Mokka', 'Mokke', 'Mokku',
    },
    Poroggos    = {
        'Poroggo Gent',
        'Eriri Samariri', 'Oriri Samariri', 'Uriri Samariri',
    },
    Soulflayers = {
        'Psycheflayer',
        'Vile Ineef', 'Vile Wahdaha', 'Vile Yabeewa',
    },
    Qiqirns     = {
        'Qiqirn Treasure Hunter', 'Qiqirn Archaeologist',
        'Gem Heister Roorooroon', 'Quick Draw Sasaroon', 'Stealth Bomber Gagaroon',
    },
}

local FAMILY_SINGULAR = {
    Chariots    = 'Chariot',
    Flans       = 'Flan',
    Imps        = 'Imp',
    Poroggos    = 'Poroggo',
    Soulflayers = 'Soulflayer',
    Qiqirns     = 'Qiqirn',
}

local NAME_TO_FAMILY = {}
for fam_id, names in pairs(FAMILY_GROUPS) do
    for _, name in ipairs(names) do
        NAME_TO_FAMILY[name] = fam_id
        NAME_TO_FAMILY[name:gsub('%s+', '')] = fam_id
    end
end

local SPECIFIED_ENEMIES_FAMILIES = {}
for name in pairs(NAME_TO_FAMILY) do
    SPECIFIED_ENEMIES_FAMILIES[name] = true
end

local FILTER_NAMES = {
    ['Archaic Gear'] = true,
    ['Archaic Gears'] = true,
    ['Rune of Transfer'] = true,
    ['Runic Lamp'] = true,
    ['ArchaicGear'] = true,
    ['ArchaicGears'] = true,
    ['RuneofTransfer'] = true,
    ['RunicLamp'] = true,
}

local SPECIFIED_ENEMY_EXCLUDED_NAMES = {
    'Archaic Rampart', 'Archaic Chariot',
    'Bat Eye', 'Shadow Eye', 'Juggler Hecatomb', 'Smothered Schmidt',
    'Hellion', 'Leaping Lizzy', 'Tom Tit Tat', 'Jaggedy-Eared Jack',
    'Cactuar Cantautor', 'Gargantua', 'Gyre-Carlin', 'Asphyxiated Amsel',
    'Frostmane', 'Peallaidh', 'Carnero', 'Falcatus Aranei',
    'Emergent Elm', 'Old Two-Wings', 'Aiatar', 'Intulo',
    'Orctrap', 'Valkurm Emperor', 'Crushed Krause', 'Stinging Sophie',
    'Serpopard Ishtar', 'Western Shadow', 'Bloodtear Baldurf', 'Zizzy Zillah',
    'Ellyllon', 'Mischievous Micholas', 'Leech King', 'Eastern Shadow',
    'Nunyenunc', 'Helldiver', 'Taisaijin', 'Fungus Beetle',
    'Friar Rush', 'Pulverized Pfeffer', 'Argus', 'Bloodpool Vorax',
    'Nightmare Vase', 'Daggerclaw Dracos', 'Northern Shadow', 'Fraelissa',
    'Roc', 'Sabotender Bailarin', 'Aquarius', 'Energetic Eruca',
    'Spiny Spipi', 'Trickster Kinetix', 'Drooling Daisy', 'Bonnacon',
    'Golden Bat', 'Steelfleece Baldarich', 'Sabotender Mariachi', 'Ungur',
    'Swamfish', 'Buburimboo', 'Keeper of Halidom', 'Serket',
    'Dune Widow', 'Odqan', 'Burned Bergmann', 'Tyrannic Tunnok',
    'Bloodsucker', 'Tottering Toby', 'Southern Shadow', 'Sharp-Eared Ropipi',
    'Panzer Percival', 'Vouivre', 'Jolly Green', 'Tumbling Truffle',
    'Capricious Cassie', 'Amikiri', 'Sewer Syrup', 'Unut',
    'Simurgh', 'Pelican', 'Cargo Crab Colin', 'Wounded Wurfel',
    'Peg Powler', 'Jaded Jody', 'Maighdean Uaine',
}
local SPECIFIED_ENEMY_EXCLUSIONS = {}
for _, n in ipairs(SPECIFIED_ENEMY_EXCLUDED_NAMES) do
    SPECIFIED_ENEMY_EXCLUSIONS[n] = true
    SPECIFIED_ENEMY_EXCLUSIONS[n:gsub('%s+', '')] = true
end

local function specified_enemy_excluded(name)
    if not name then return false end
    if SPECIFIED_ENEMY_EXCLUSIONS[name] then return true end
    local stripped = name:gsub('%s+', '')
    return SPECIFIED_ENEMY_EXCLUSIONS[stripped] == true
end

local function family_name_match(ws_name, family_id)
    if not ws_name or ws_name == '' or not family_id then return false end
    local members = FAMILY_GROUPS[family_id]
    if not members then return false end
    for _, full in ipairs(members) do
        local slug = full:gsub('%s+', '')
        if ws_name == full or ws_name == slug then return true end
        if #ws_name <= 16 and #slug > 16 and slug:sub(1, #ws_name) == ws_name then
            return true
        end
    end
    return false
end

local function name_filter_match(name)
    if not name then return false end
    if FILTER_NAMES[name] then return true end
    local stripped = name:gsub('%s+', ''):gsub('%c', '')
    if FILTER_NAMES[stripped] then return true end
    local lower = stripped:lower()
    local keywords = { 'runeoftransfer', 'runiclamp', 'archaicgear' }
    for _, kw in ipairs(keywords) do
        if lower:find(kw, 1, true) then return true end
        if #lower >= 6 and kw:sub(1, #lower) == lower then return true end
    end
    return false
end

local NYZUL_NM_SET_SLUGGED = {}
for name in pairs(NYZUL_NM_SET) do
    NYZUL_NM_SET_SLUGGED[name:gsub('%s+', '')] = true
end
local function nm_match(name)
    if not name then return false end
    return NYZUL_NM_SET[name] or NYZUL_NM_SET_SLUGGED[name]
end

ws_scan = {
    active = false,
    mode = nil,
    results = {},
    nm_found = nil,
    mob_count = 0,
    callback = nil,
}

local function token_relative_floor()
    if current_floor_number == 0 then return 0 end
    if current_floor_number < starting_floor then
        return current_floor_number + 100
    end
    return current_floor_number
end

local function token_rate()
    local rate = 1.0
    if has_armband then rate = rate + 0.1 end
    if party_size > 3 then rate = rate - ((party_size - 3) * 0.1) end
    if rate < 0 then rate = 0 end
    return rate
end

local function token_credit_floor()
    local rf = token_relative_floor()
    if rf < 1 then return end
    local rate = token_rate()
    local floor_bonus = 0
    if rf > 1 then floor_bonus = 10 * math.floor((rf - 1) / 5) end
    local gross = (200 + floor_bonus) * rate
    local penalty = math.floor(117 * rate + 0.5) * floor_penalties
    potential_tokens = potential_tokens + gross - penalty
    floor_penalties = 0
end

local function token_refresh_armband()
    has_armband = false
    local kis = windower.ffxi.get_key_items()
    if kis then
        for _, v in ipairs(kis) do
            if v == 797 then has_armband = true; break end
        end
    end
end

local function token_refresh_party_size()
    local p = windower.ffxi.get_party_info()
    party_size = (p and p.party1_count) or 1
end

poke_target = nil

autocertify_enabled = true

rune_runner_name = (genie_settings.rune_runner ~= '' and genie_settings.rune_runner) or nil
rune_mode        = 'up'
rune_active      = false
rune_attempts    = 0

certify_state = {
    active = false,
    last_poke_time = 0,
    retry_count = 0,
    max_retries = 5,
    retry_interval = 6.0,
}
auto_solve = genie_settings.auto_solve == true
auto_warp_nm     = genie_settings.auto_warp_nm == true
auto_warp_all    = genie_settings.auto_warp_all == true
auto_warp_family = genie_settings.auto_warp_family == true
auto_warp_single = genie_settings.auto_warp_single == true
last_warp_time = 0

floor_count      = 0
floor_start_time = 0
floor_times      = {}
run_start_time   = 0

solver_active       = false
solver_paused       = false
solver_opt          = 0
solver_perms        = {}
solver_perm_idx     = 0
solver_step         = 0
solver_lamps        = {}
solver_wait_time    = 0
solver_delay        = 12.0
solver_poke_time    = 0
solver_poke_retries = 0

lamp_unlit_set = {}
solver_known_prefix = {}
solver_step_clicks = {}

nm_scan = {
    active = false,
    indices = {},
    pos = 0,
    callback = nil,
    found = nil,
    last_req_idx = 0,
    last_req_time = 0,
    pending = {},
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function get_lamp_letter(targetIndex)
    return string.char(64 + LAMP_INDEX_TO_NUM[targetIndex])
end

local function table_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function direction_arrow(decimal)
    local index = math.ceil(math.fmod(decimal + 22.5, 360) / 45)
    local arrows = { '↑', '↑→', '→', '↓→', '↓', '←↓', '←', '←↑' }
    return arrows[index] or ''
end

local function compute_distance(a, b)
    return math.sqrt((b.x - a.x)^2 + (b.y - a.y)^2)
end

local function dist_color(dist)
    if dist < 10 then
        return '\\cs(100,255,100)'
    elseif dist < 30 then
        return '\\cs(255,255,100)'
    else
        return '\\cs(220,220,220)'
    end
end

local function compute_relative_direction(playerpos, target)
    local vectorX = target.x - playerpos.x
    local vectorY = target.y - playerpos.y
    local quatranCorrection = 0
    if vectorX < 0 then
        quatranCorrection = 180
    elseif vectorY < 0 then
        quatranCorrection = 360
    end
    local playerdirection = math.fmod((playerpos.facing * 180 / 3.1413) + 450, 360)
    local direction = math.fmod(360 - (math.deg(math.atan(vectorY / vectorX)) + quatranCorrection) + 90, 360)
    return math.fmod(direction - playerdirection + 360, 360)
end

-------------------------------------------------------------------------------
-- Entity request helper
-------------------------------------------------------------------------------
local function request_entity(idx)
    local r = packets.new('outgoing', 0x016)
    r['Target Index'] = idx
    packets.inject(r)
end

local function request_all_lamps()
    for _, idx in ipairs(SORTED_LAMP_INDEXES) do
        request_entity(idx)
    end
end

-------------------------------------------------------------------------------
-- Auto-check: send /check packet for a mob
-------------------------------------------------------------------------------
local function send_check(mob_index, mob_id)
    local p = packets.new('outgoing', 0x0DD)
    p['Target']       = mob_id
    p['Target Index']  = mob_index
    p['Check Type']    = 0
    packets.inject(p)
end

local function process_check_queue()
    if check_current then
        if os.clock() - check_current.time > 3.0 then
            check_cache[check_current.index] = 'normal'
            check_current = nil
        else
            return
        end
    end
    if #check_queue == 0 then return end
    if os.clock() - check_last_time < 1.0 then return end

    local entry = table.remove(check_queue, 1)
    local mob = windower.ffxi.get_mob_by_index(entry.index)
    if not mob or not mob.valid_target or mob.hpp == 0 then
        check_cache[entry.index] = nil
        return
    end
    check_current = { index = entry.index, id = entry.id, time = os.clock() }
    check_last_time = os.clock()
    send_check(entry.index, entry.id)
end

local function queue_check(mob)
    if check_cache[mob.index] then return end
    check_cache[mob.index] = 'pending'
    check_queue[#check_queue+1] = { index = mob.index, id = mob.id }
end

local function clear_check_cache()
    check_cache = {}
    check_queue = {}
    check_current = nil
end

-------------------------------------------------------------------------------
-- Teleport (fake incoming 0x065)
-------------------------------------------------------------------------------
local function teleport_to(x, y, z)
    local player = windower.ffxi.get_player()
    local me = windower.ffxi.get_mob_by_target('me')
    if not player or not me then
        windower.add_to_chat(167, 'Genie: Cannot get player data.')
        return false
    end
    local p = packets.new('incoming', 0x065)
    p['ID']        = me.id
    p['Index']     = me.index
    p['Animation'] = 0
    p['Rotation']  = 0
    p['X']         = x
    p['Y']         = y
    p['Z']         = z
    packets.inject(p)
    return true
end

-------------------------------------------------------------------------------
-- Release (force-close menu)
-------------------------------------------------------------------------------
local function do_release()
    local me = windower.ffxi.get_mob_by_target('me')
    local t = windower.ffxi.get_mob_by_target('t')
    if t and me then
        local zone = windower.ffxi.get_info().zone
        local cancel = packets.new('outgoing', 0x05B)
        cancel['Target']            = t.id
        cancel['Target Index']      = t.index
        cancel['Zone']              = zone
        cancel['Menu ID']           = 0
        cancel['Option Index']      = 0
        cancel['_unknown1']         = 0
        cancel['Automated Message'] = false
        cancel['_unknown2']         = 0
        packets.inject(cancel)
    end
    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,0,0,0,0))
    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,1,0,0,0))
    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,0,0,0,0))
    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,1,0,0,0))
    poke_target = nil
    windower.add_to_chat(200, 'Genie: Release injected.')
end

-------------------------------------------------------------------------------
-- Certify
-------------------------------------------------------------------------------
local function do_certify(is_retry)
    request_all_lamps()
    coroutine.schedule(function()
        local lamp = nil
        for _, idx in ipairs(SORTED_LAMP_INDEXES) do
            local npc = windower.ffxi.get_mob_by_index(idx)
            if npc and npc.name == 'Runic Lamp' and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                lamp = npc
                break
            end
        end
        if not lamp then
            windower.add_to_chat(167, 'Genie: No lamp found for certification.')
            return
        end
        if is_retry then
            windower.add_to_chat(200, ('Genie: Retrying certification (attempt %d/%d)...'):format(
                certify_state.retry_count + 1, certify_state.max_retries))
        else
            windower.add_to_chat(200, ('Genie: Certifying at lamp (index=%d)...'):format(lamp.index))
            certify_state.retry_count = 0
        end
        certify_state.active = true
        certify_state.last_poke_time = os.clock()
        poke_target = {
            index = lamp.index,
            npc_id = lamp.id,
            x = lamp.x, y = lamp.y, z = lamp.z,
            opt = -1,
            spoof_count = 0,
            state = 'SPOOF',
            is_certify = true,
        }
    end, 1.0)
end

-------------------------------------------------------------------------------
-- Rune of Transfer (auto-floor-advance)
-------------------------------------------------------------------------------

local function find_rune_of_transfer_local()
    for _, idx in ipairs(RUNE_INDICES) do
        local mob = windower.ffxi.get_mob_by_index(idx)
        if mob and mob.name == 'Rune of Transfer' and mob.valid_target and mob.is_npc
           and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0) then
            return mob
        end
    end
    for _, mob in pairs(windower.ffxi.get_mob_array()) do
        if mob and mob.valid_target and mob.name == 'Rune of Transfer' and mob.is_npc
           and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0) then
            return mob
        end
    end
    return nil
end

local function setup_rune_poke(rune)
    local me = windower.ffxi.get_mob_by_target('me')
    local dist = nil
    if me then
        local dx, dy = rune.x - me.x, rune.y - me.y
        dist = math.sqrt(dx*dx + dy*dy)
    end
    local opt = (rune_mode == 'up') and 2 or 1

    if dist and dist <= 5 then
        windower.add_to_chat(200, ('Genie: Rune is close (%.1fy) - poking directly (mode=%s)...'):format(dist, rune_mode))
        poke_target = {
            index = rune.index,
            npc_id = rune.id,
            x = rune.x, y = rune.y, z = rune.z,
            opt = opt,
            spoof_count = 2,
            state = 'POKE',
            is_rune = true,
        }
        request_entity(rune.index)
        local poke = packets.new('outgoing', 0x01A)
        poke['Target']       = rune.id
        poke['Target Index'] = rune.index
        poke['Category']     = 0x00
        poke['Param']        = 0
        packets.inject(poke)
    else
        local dist_str = dist and ('%.1f'):format(dist) or '?'
        poke_target = {
            index = rune.index,
            npc_id = rune.id,
            x = rune.x, y = rune.y, z = rune.z,
            opt = opt,
            spoof_count = 0,
            state = 'SPOOF',
            is_rune = true,
        }
    end
end

local function poke_rune()
    if not rune_active then return end
    if poke_target then return end
    rune_attempts = rune_attempts + 1
    if rune_attempts > 10 then
        windower.add_to_chat(167, 'Genie: Rune click gave up after 10 attempts.')
        rune_active = false
        return
    end

    local rune = find_rune_of_transfer_local()
    if rune then
        setup_rune_poke(rune)
        return
    end

    windower.add_to_chat(200, 'Genie: Rune not loaded - requesting entity data...')
    for _, idx in ipairs(RUNE_INDICES) do
        request_entity(idx)
    end
    coroutine.schedule(function()
        if not rune_active or poke_target then return end
        local r = find_rune_of_transfer_local()
        if r then
            setup_rune_poke(r)
        else
            windower.add_to_chat(167, 'Genie: Rune still not loaded, will retry.')
            coroutine.schedule(poke_rune, 2.0)
        end
    end, 1.0)
end

local function is_rune_runner()
    if not rune_runner_name then return false end
    local player = windower.ffxi.get_player()
    if not player or not player.name then return false end
    return player.name:lower() == rune_runner_name:lower()
end

-------------------------------------------------------------------------------
-- NM finder
-------------------------------------------------------------------------------
local function find_nyzul_nm()
    local mob_array = windower.ffxi.get_mob_array()
    for _, mob in pairs(mob_array) do
        if mob and mob.name and NYZUL_NM_SET[mob.name] and mob.valid_target and mob.is_npc
           and not defeated_nm_set[mob.index] then
            return mob
        end
    end
    return nil
end

local function nm_scan_next()
    if not nm_scan.active then return end
    if nm_scan.found then
        nm_scan.active = false
        if nm_scan.callback then
            nm_scan.callback(nm_scan.found)
            nm_scan.callback = nil
        end
        return
    end
    nm_scan.pos = nm_scan.pos + 1
    if nm_scan.pos > #nm_scan.indices then
        nm_scan.active = false
        if nm_scan.callback then
            nm_scan.callback(nil)
            nm_scan.callback = nil
        end
        return
    end
    local entry = nm_scan.indices[nm_scan.pos]
    local target_index = entry.index
    windower.packets.inject_outgoing(0x16, string.char(0x16, 0x08, 0x00, 0x00,
        (target_index % 256), math.floor(target_index / 256), 0x00, 0x00))
    nm_scan.last_req_idx = target_index
    nm_scan.pending[target_index] = true
    nm_scan.last_req_time = os.clock()
    windower.add_to_chat(200, ('  Scanning %s (index=%d)...'):format(entry.name, target_index))
end

local function start_nm_scan(callback)
    local indices = get_nm_dat_indices()
    local to_scan = {}
    for name, index in pairs(indices) do
        to_scan[#to_scan+1] = { name = name, index = index }
    end
    if #to_scan == 0 then
        windower.add_to_chat(167, 'Genie: No NM indices found in DAT files.')
        if callback then callback(nil) end
        return
    end
    windower.add_to_chat(200, ('Genie: Found %d NM indices in DAT. Scanning for live NM...'):format(#to_scan))
    nm_scan.active = true
    nm_scan.indices = to_scan
    nm_scan.pos = 0
    nm_scan.callback = callback
    nm_scan.found = nil
    nm_scan.last_req_idx = 0
    nm_scan.last_req_time = 0
    nm_scan.pending = {}
    nm_scan_next()
end

-------------------------------------------------------------------------------
-- Widescan-based scanning
-------------------------------------------------------------------------------

local function start_widescan(mode, callback)
    ws_scan.active = true
    ws_scan.mode = mode
    ws_scan.results = {}
    ws_scan.nm_found = nil
    ws_scan.mob_count = 0
    ws_scan.callback = callback
    local p = packets.new('outgoing', 0x0F4)
    p['Flags'] = 1
    packets.inject(p)
    windower.add_to_chat(200, ('Genie: Widescan triggered (mode=%s)...'):format(mode))
end

local function ws_find_nm(callback)
    start_widescan('nm', function(results)
        if ws_scan.nm_found then
            local idx = ws_scan.nm_found.index
            local name = ws_scan.nm_found.name
            windower.add_to_chat(200, ('Genie: NM "%s" found (index=%d). Getting coordinates...'):format(name, idx))
            local track = packets.new('outgoing', 0x0F5)
            track['Index'] = idx
            packets.inject(track)
            if callback then callback(ws_scan.nm_found) end
        else
            windower.add_to_chat(167, 'Genie: No NM found via widescan.')
            if callback then callback(nil) end
        end
    end)
end

local function ws_count_enemies(callback)
    start_widescan('count', function(results)
        windower.add_to_chat(200, ('Genie: %d enemies found on floor (%d total entities scanned).'):format(
            ws_scan.mob_count, #results))
        if callback then callback(ws_scan.mob_count, results) end
    end)
end

local function ws_cache_update_positions()
    local to_remove = {}
    for idx, entry in pairs(ws_cache.mobs) do
        local mob = windower.ffxi.get_mob_by_index(idx)
        if mob then
            if mob.hpp == 0 and mob.id and mob.id ~= 0 then
                to_remove[#to_remove+1] = idx
            elseif mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0 then
                entry.x = mob.x
                entry.y = mob.y
                entry.z = mob.z
                entry.hpp = mob.hpp
            end
        end
    end
    for _, idx in ipairs(to_remove) do
        ws_cache.mobs[idx] = nil
        if specified_enemies_list[idx] then
            specified_enemies_list[idx] = nil
        end
    end
end

last_pos_refresh_time = 0

packet_capture = {
    active = false,
    end_time = 0,
    label = '',
}
local function ws_throttled_position_refresh()
    if os.clock() - last_pos_refresh_time < 1.0 then return end
    local best_idx = nil
    local best_age = -1
    for idx, entry in pairs(ws_cache.mobs) do
        local mob = windower.ffxi.get_mob_by_index(idx)
        local is_loaded = mob and (mob.x ~= 0 or mob.y ~= 0)
        if not is_loaded then
            local age = entry.last_refresh and (os.clock() - entry.last_refresh) or math.huge
            if not entry.x then age = math.huge end
            if age > best_age then
                best_age = age
                best_idx = idx
            end
        end
    end
    if best_idx and best_age > 30.0 then
        local req = packets.new('outgoing', 0x016)
        req['Target Index'] = best_idx
        packets.inject(req)
        ws_cache.mobs[best_idx].last_refresh = os.clock()
        last_pos_refresh_time = os.clock()
    end
end

local function ws_preload_for_check()
    start_widescan('preload', function(results)
        local count = 0
        ws_cache.mobs = {}
        local families_present = {}
        local family_first_member = {}
        for _, r in ipairs(results) do
            if not name_filter_match(r.name) and not nm_match(r.name) then
                local req = packets.new('outgoing', 0x016)
                req['Target Index'] = r.index
                packets.inject(req)
                ws_cache.mobs[r.index] = {
                    name = r.name, level = r.level,
                    x_off = r.x_off, y_off = r.y_off,
                    x = nil, y = nil, z = nil, hpp = 100,
                }
                count = count + 1
                local fam_id = NAME_TO_FAMILY[r.name]
                if not fam_id then
                    for fid, _ in pairs(FAMILY_GROUPS) do
                        if family_name_match(r.name, fid) then fam_id = fid; break end
                    end
                end
                if fam_id and not families_present[fam_id] then
                    families_present[fam_id] = true
                    family_first_member[fam_id] = r.name
                end
            end
        end
        ws_cache.last_refresh = os.clock()
        coroutine.schedule(ws_cache_update_positions, 0.5)
        windower.add_to_chat(200, ('Genie: Preloaded %d enemy entities for checking.'):format(count))

        if specified_enemies_floor and not specified_enemies_family then
            local list = {}
            for fid in pairs(families_present) do list[#list+1] = fid end
            if #list == 1 then
                local fid = list[1]
                specified_enemies_family = fid
                specified_enemies_name   = family_first_member[fid]
                windower.add_to_chat(200, ('Genie: >>> SOLO FAMILY: %s (only family on floor) <<<'):format(fid))
                local found = 0
                for idx, entry in pairs(ws_cache.mobs) do
                    if family_name_match(entry.name, fid) then
                        specified_enemies_list[idx] = {
                            index = idx, name = entry.name,
                            x = entry.x, y = entry.y, z = entry.z,
                        }
                        found = found + 1
                    end
                end
                windower.add_to_chat(200, ('Genie: Found %d %s family members; skipping ITG check.'):format(found, fid))
            elseif #list > 1 then
                windower.add_to_chat(200, ('Genie: %d candidate families on floor (%s) - ITG check required.'):format(
                    #list, table.concat(list, ', ')))
            end
        end
    end)
end

local function ws_refresh_cache(preload_positions)
    if ws_scan.active then return end
    start_widescan('cache', function(results)
        local new_count = 0
        for _, r in ipairs(results) do
            if not name_filter_match(r.name) and not nm_match(r.name) then
                local existing = ws_cache.mobs[r.index]
                if existing then
                    existing.name = r.name
                    existing.level = r.level
                    existing.x_off = r.x_off
                    existing.y_off = r.y_off
                else
                    ws_cache.mobs[r.index] = {
                        name = r.name, level = r.level,
                        x_off = r.x_off, y_off = r.y_off,
                        x = nil, y = nil, z = nil, hpp = 100,
                        last_refresh = 0,
                    }
                    if preload_positions then
                        local req = packets.new('outgoing', 0x016)
                        req['Target Index'] = r.index
                        packets.inject(req)
                        ws_cache.mobs[r.index].last_refresh = os.clock()
                        new_count = new_count + 1
                    end
                end

                if specified_enemies_floor and specified_enemies_family
                   and family_name_match(r.name, specified_enemies_family)
                   and not specified_enemies_list[r.index] then
                    specified_enemies_list[r.index] = {
                        index = r.index, name = r.name,
                        x = ws_cache.mobs[r.index].x,
                        y = ws_cache.mobs[r.index].y,
                        z = ws_cache.mobs[r.index].z,
                    }
                end
            end
        end
        ws_cache.last_refresh = os.clock()
        if preload_positions and new_count > 0 then
            coroutine.schedule(ws_cache_update_positions, 0.5)
        end
    end)
end

-------------------------------------------------------------------------------
-- Solver: permutation generator
-------------------------------------------------------------------------------
local function generate_permutations(n)
    local result = {}
    local arr = {}
    for i = 1, n do arr[i] = i end
    local function permute(k)
        if k == 1 then
            local copy = {}
            for i = 1, n do copy[i] = arr[i] end
            result[#result+1] = copy
        else
            for i = 1, k do
                permute(k - 1)
                if k % 2 == 0 then
                    arr[i], arr[k] = arr[k], arr[i]
                else
                    arr[1], arr[k] = arr[k], arr[1]
                end
            end
        end
    end
    permute(n)
    return result
end

-------------------------------------------------------------------------------
-- Solver: forward declarations
-------------------------------------------------------------------------------
local solver_activate_next
local solver_start_next_perm
local solver_retry_current

-------------------------------------------------------------------------------
-- Simultaneous lamps: poke all lamps once in quick succession
-------------------------------------------------------------------------------
simultaneous_done_time = 0
last_poke_was_simultaneous = false
last_poke_was_solver = false
last_poke_time_for_skip = 0

local function simultaneous_activate_next()
    if not simultaneous_floor then return end
    simultaneous_step = simultaneous_step + 1
    if simultaneous_step > #simultaneous_lamps then
        windower.add_to_chat(200, 'Genie: All lamps poked. Waiting for activation...')
        simultaneous_done_time = os.clock()
        return
    end
    local lamp = simultaneous_lamps[simultaneous_step]
    request_entity(lamp.index)
    local npc = windower.ffxi.get_mob_by_index(lamp.index)
    if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
        lamp.x, lamp.y, lamp.z = npc.x, npc.y, npc.z
        lamp.npc_id = npc.id
    end
    windower.add_to_chat(200, ('Genie SOLVER: Activating Lamp %s...'):format(get_lamp_letter(lamp.index)))
    poke_target = {
        index = lamp.index,
        npc_id = lamp.npc_id,
        x = lamp.x, y = lamp.y, z = lamp.z,
        opt = 1,
        spoof_count = 0,
        state = 'SPOOF',
        is_simultaneous = true,
    }
end

-------------------------------------------------------------------------------
-- Solver: lamp state debug logger
-------------------------------------------------------------------------------
local function dump_mob_fields(mob, prefix)
    prefix = prefix or ''
    local lines = {}
    local keys = {}
    for k in pairs(mob) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local v = mob[k]
        local t = type(v)
        if t == 'table' then
            local sub = {}
            for sk, sv in pairs(v) do
                sub[#sub+1] = tostring(sk) .. '=' .. tostring(sv)
            end
            lines[#lines+1] = ('%s%s: { %s }'):format(prefix, k, table.concat(sub, ', '))
        elseif t == 'function' or t == 'userdata' then
        else
            lines[#lines+1] = ('%s%s = %s'):format(prefix, k, tostring(v))
        end
    end
    return lines
end

local function log_lamp_states(label, force)
    if not debugmode and not force then return end
    windower.add_to_chat(200, ('Genie LAMP DEBUG [%s]:'):format(label))
    for _, idx in ipairs(SORTED_LAMP_INDEXES) do
        request_entity(idx)
    end
    coroutine.schedule(function()
        local log_path = windower.addon_path .. 'data\\lamp_debug.log'
        local file = io.open(log_path, 'a')
        if file then
            file:write(('\n=== %s @ %s ===\n'):format(label, os.date('%Y-%m-%d %H:%M:%S')))
        end

        for _, idx in ipairs(SORTED_LAMP_INDEXES) do
            local npc = windower.ffxi.get_mob_by_index(idx)
            if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) and npc.name == 'Runic Lamp' then
                local letter = get_lamp_letter(idx)
                local header = ('  Lamp %s [%d]:'):format(letter, idx)
                windower.add_to_chat(200, header)
                if file then file:write(header .. '\n') end

                local lines = dump_mob_fields(npc, '    ')
                for _, line in ipairs(lines) do
                    windower.add_to_chat(200, line)
                    if file then file:write(line .. '\n') end
                end
            end
        end

        if file then
            file:close()
            windower.add_to_chat(200, ('Genie: Lamp state written to data/lamp_debug.log'))
        end
    end, 0.7)
end

-------------------------------------------------------------------------------
-- Solver: start next permutation
-------------------------------------------------------------------------------
local function update_known_prefix_from_unlit()
    local new_prefix = {}
    for step = 1, #solver_step_clicks do
        local lamp_idx = solver_step_clicks[step]
        if lamp_unlit_set[lamp_idx] then
            break
        end
        new_prefix[#new_prefix+1] = lamp_idx
    end
    if #new_prefix > #solver_known_prefix then
        solver_known_prefix = new_prefix
        local letters = {}
        for _, idx in ipairs(solver_known_prefix) do
            letters[#letters+1] = get_lamp_letter(idx)
        end
        if debugmode then
            windower.add_to_chat(200, ('Genie SOLVER: Known correct prefix: %s (length %d)'):format(
                table.concat(letters, ' -> '), #solver_known_prefix))
        end
    end
end

local function perm_matches_prefix(perm)
    if #solver_known_prefix == 0 then return true end
    for i, idx in ipairs(solver_known_prefix) do
        local lamp_pos = perm[i]
        if not lamp_pos then return false end
        local lamp = solver_lamps[lamp_pos]
        if not lamp or lamp.index ~= idx then return false end
    end
    return true
end

solver_start_next_perm = function()
    if solver_perm_idx > 0 and not objectiveCompleted and #solver_step_clicks > 0 then
        update_known_prefix_from_unlit()
    end
    lamp_unlit_set = {}
    solver_step_clicks = {}
    solver_perm_idx = solver_perm_idx + 1
    solver_step = 0
    solver_wait_time = 0
    solver_poke_time = 0
    solver_poke_retries = 0
    local skipped = 0
    while solver_perm_idx <= #solver_perms and not perm_matches_prefix(solver_perms[solver_perm_idx]) do
        solver_perm_idx = solver_perm_idx + 1
        skipped = skipped + 1
    end
    if skipped > 0 and debugmode then
        windower.add_to_chat(200, ('Genie SOLVER: Skipped %d permutations not matching prefix.'):format(skipped))
    end
    if solver_perm_idx > #solver_perms then
        windower.add_to_chat(167, 'Genie SOLVER: Exhausted all permutations - no solution found.')
        solver_active = false
        return
    end
    coroutine.schedule(solver_activate_next, 2.0)
end

-------------------------------------------------------------------------------
-- Solver: activate next lamp in current permutation
-------------------------------------------------------------------------------
solver_activate_next = function()
    if objectiveCompleted or rune_active then
        solver_active = false
        solver_wait_time = 0
        solver_poke_time = 0
        poke_target = nil
        return
    end
    if not solver_active then return end
    if solver_paused then return end
    if objectiveCompleted then
        local perm = solver_perms[solver_perm_idx]
        local order_str = ''
        if perm then
            local order = {}
            for i, lamp_pos in ipairs(perm) do
                order[i] = get_lamp_letter(solver_lamps[lamp_pos].index)
            end
            order_str = ' (order: ' .. table.concat(order, ' -> ') .. ')'
        end
        windower.add_to_chat(200, 'Genie: Lamp Floor Solved!')
        solver_active = false
        return
    end
    local perm = solver_perms[solver_perm_idx]
    if not perm then
        windower.add_to_chat(167, 'Genie SOLVER: Exhausted all permutations - no solution found.')
        solver_active = false
        return
    end
    solver_step = solver_step + 1
    if solver_step > #perm then
        solver_wait_time = os.clock()
        if debugmode then
            windower.add_to_chat(200, ('Genie SOLVER: Perm %d/%d complete. Waiting %.0fs for result...'):format(
                solver_perm_idx, #solver_perms, solver_delay))
        end
        coroutine.schedule(function()
            if solver_active and solver_wait_time > 0 then
                for _, idx in ipairs(SORTED_LAMP_INDEXES) do
                    request_entity(idx)
                end
            end
        end, 6.0)
        return
    end
    local lamp = solver_lamps[perm[solver_step]]
    if not lamp then
        windower.add_to_chat(167, ('Genie SOLVER: Lamp %d not available, skipping permutation.'):format(perm[solver_step]))
        solver_start_next_perm()
        return
    end
    local letter = get_lamp_letter(lamp.index)
    solver_step_clicks[solver_step] = lamp.index
    windower.add_to_chat(200, ('Genie SOLVER: Activating Lamp %s...'):format(letter))
    request_entity(lamp.index)
    local npc = windower.ffxi.get_mob_by_index(lamp.index)
    if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
        lamp.x, lamp.y, lamp.z = npc.x, npc.y, npc.z
        lamp.npc_id = npc.id
    end
    poke_target = {
        index = lamp.index,
        npc_id = lamp.npc_id,
        x = lamp.x, y = lamp.y, z = lamp.z,
        opt = solver_opt,
        spoof_count = 0,
        state = 'SPOOF',
        is_solver = true,
    }
    solver_poke_time = os.clock()
    solver_poke_retries = 0
end

-------------------------------------------------------------------------------
-- Solver: retry current lamp poke
-------------------------------------------------------------------------------
solver_retry_current = function()
    if objectiveCompleted or rune_active then
        solver_active = false
        poke_target = nil
        return
    end
    if not solver_active or solver_paused then return end
    solver_poke_retries = solver_poke_retries + 1
    if solver_poke_retries > 5 then
        windower.add_to_chat(167, 'Genie SOLVER: Too many retries on current lamp. Restarting permutation...')
        solver_start_next_perm()
        return
    end
    solver_step = solver_step - 1
    if debugmode then
        windower.add_to_chat(200, ('Genie SOLVER: Retrying lamp (attempt %d/5)...'):format(solver_poke_retries))
    end
    poke_target = nil
    coroutine.schedule(solver_activate_next, 1.5)
end

-------------------------------------------------------------------------------
-- Solver: pause / resume
-------------------------------------------------------------------------------
solver_pause_was_mid_poke = false

local function solver_pause()
    if solver_active and not solver_paused then
        solver_paused = true
        solver_pause_was_mid_poke = (poke_target ~= nil)
        poke_target = nil
        windower.add_to_chat(200, 'Genie SOLVER: Paused (combat).')
    end
end

local function solver_resume()
    if solver_active and solver_paused then
        solver_paused = false
        windower.add_to_chat(200, 'Genie SOLVER: Resuming...')
        if solver_pause_was_mid_poke and solver_step > 0 then
            solver_step = solver_step - 1
        end
        solver_pause_was_mid_poke = false
        coroutine.schedule(solver_activate_next, 2.0)
    end
end

-------------------------------------------------------------------------------
-- Reset helpers
-------------------------------------------------------------------------------
local function reset_lamps()
    needLampScan = false
    currentFloorRuneFilter = 0
    objectiveCompleted = false
    lampFloorDetected = false
    eliminate_leader_floor = false
    eliminate_leader = nil
    simultaneous_floor = false
    simultaneous_lamps = {}
    simultaneous_step = 0
    eliminate_all_floor = false
    specified_enemy_floor = false
    specified_enemy = nil
    specified_enemy_list = {}
    archaic_gear_warning = nil
    current_objective = nil
    defeated_nm_set = {}
    rune_active = false
    rune_attempts = 0
    specified_enemies_floor = false
    specified_enemies_family = nil
    specified_enemies_name = nil
    specified_enemies_name_slug = nil
    specified_enemies_list = {}
    ws_cache.mobs = {}
    ws_cache.last_refresh = 0
    clear_check_cache()
    for k in pairs(tLamps) do
        tLamps[k] = {}
    end
end

local function hide_display()
    if not debugmode then
        text_box:visible(false)
        text_box:text('')
    end
end

local function update_entities()
    for k in pairs(tLamps) do
        request_entity(k)
    end
end

-------------------------------------------------------------------------------
-- HUD Display
-------------------------------------------------------------------------------
local function display()
    local new_text = ''
    local player = windower.ffxi.get_player()
    local playerpos = windower.ffxi.get_mob_by_index(player.index)
    local lampCountCheck = 0

    if eventClock ~= nil then
        local remainingMinutes = 30 - math.round(((os.clock() - eventClock) / 60), 0) - (time_penalty_minutes or 0)
        new_text = new_text .. 'Time Remaining - '
        if remainingMinutes <= 5 then
            new_text = new_text .. '\\cs(255,0,0)'
        elseif remainingMinutes <= 8 then
            new_text = new_text .. '\\cs(255,255,0)'
        else
            new_text = new_text .. '\\cs(200,200,200)'
        end
        new_text = new_text .. remainingMinutes .. ' min(s)\\cr\n'
    end

    if currentZone == 77 and floor_count > 0 then
        local floor_elapsed = os.clock() - floor_start_time
        local avg = 0
        if #floor_times > 0 then
            local sum = 0
            for _, t in ipairs(floor_times) do sum = sum + t end
            avg = sum / #floor_times
        end
        new_text = new_text .. ('\\cs(180,180,255)F%d'):format(floor_count)
        new_text = new_text .. (' | %d:%02d'):format(math.floor(floor_elapsed / 60), math.floor(floor_elapsed % 60))
        if avg > 0 then
            new_text = new_text .. (' | Avg %d:%02d'):format(math.floor(avg / 60), math.floor(avg % 60))
        end
        new_text = new_text .. '\\cr\n'
    end

    if currentZone == 77 then
        local rate = token_rate()
        new_text = new_text .. ('\\cs(255,215,100)Tokens: %d (%d%% rate'):format(
            math.floor(potential_tokens + 0.5), math.floor(rate * 100 + 0.5))
        if has_armband then new_text = new_text .. ' +armband' end
        if floor_penalties > 0 then
            new_text = new_text .. (', -%d penalty'):format(floor_penalties)
        end
        new_text = new_text .. ')\\cr\n'
    end

    if currentZone == 77 and current_objective then
        new_text = new_text .. '\\cs(220,220,255)Objective: ' .. current_objective .. '\\cr\n'
    end

    if currentZone == 77 then
        for _, idx in ipairs(RUNE_INDICES) do
            local rune = tLamps[idx]
            if rune and rune.id ~= nil and rune.x and rune.y
               and not (rune.x == 0 and rune.y == 0)
               and rune.index ~= currentFloorRuneFilter then
                local dist = compute_distance(playerpos, rune)
                if dist < 300 then
                    local relDir = compute_relative_direction(playerpos, rune)
                    new_text = new_text .. '\\cs(180,255,180)Rune of Transfer\\cr - \\cs(200,200,200)'
                        .. math.round(dist, 0) .. 'y\\cr \\cs(255,255,255)' .. direction_arrow(relDir) .. '\\cr\n'
                    break
                end
            end
        end
    end

    if currentZone == 77 then
        local mob_array = windower.ffxi.get_mob_array()
        local gears = {}
        for _, mob in pairs(mob_array) do
            if mob and mob.name and mob.is_npc and mob.spawn_type == 16
               and mob.valid_target and (mob.hpp == nil or mob.hpp > 0)
               and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0)
               and (mob.name == 'Archaic Gear' or mob.name == 'Archaic Gears') then
                local d = compute_distance(playerpos, mob)
                if d <= 100 then
                    gears[#gears+1] = { mob = mob, dist = d }
                end
            end
        end
        if #gears > 0 or archaic_gear_warning then
            table.sort(gears, function(a, b) return a.dist < b.dist end)
            if archaic_gear_warning then
                new_text = new_text .. '\\cs(255,180,50)[!] ' .. archaic_gear_warning .. '\\cr\n'
            end
            if #gears > 0 then
                new_text = new_text .. ('\\cs(255,200,100)-- Archaic Gears (%d nearby) --\\cr\n'):format(#gears)
                for i, g in ipairs(gears) do
                    local relDir = compute_relative_direction(playerpos, g.mob)
                    new_text = new_text .. ('\\cs(255,200,100)Gear #%d\\cr - \\cs(200,200,200)%dy\\cr \\cs(255,255,255)%s\\cr\n'):format(
                        i, math.round(g.dist, 0), direction_arrow(relDir))
                end
            end
        end
    end

    if eliminate_leader_floor then
        if not eliminate_leader then
            local nm = find_nyzul_nm()
            if nm then
                eliminate_leader = {
                    index = nm.index, id = nm.id, name = nm.name,
                    x = nm.x, y = nm.y, z = nm.z,
                }
                windower.add_to_chat(200, ('Genie: >>> FOUND NM: %s <<<'):format(nm.name))
                if auto_warp_nm then
                    windower.add_to_chat(200, 'Genie: Auto-warping to NM...')
                    teleport_to(nm.x, nm.y, nm.z)
                end
            end
        end

        if eliminate_leader then
            local mob = windower.ffxi.get_mob_by_index(eliminate_leader.index)
            if mob and mob.valid_target and mob.hpp > 0 then
                eliminate_leader.x = mob.x
                eliminate_leader.y = mob.y
                eliminate_leader.z = mob.z
                local dist = compute_distance(playerpos, mob)
                local relDir = compute_relative_direction(playerpos, mob)
                local arrow = direction_arrow(relDir)
                new_text = new_text .. '\\cs(255,100,50)>>> NM: ' .. mob.name .. ' <<<\\cr\n'
                new_text = new_text .. '\\cs(255,180,100)' .. math.round(dist, 0) .. 'y ' .. arrow .. ' HP:' .. mob.hpp .. '%%\\cr\n'
            end
        else
            new_text = new_text .. '\\cs(255,255,0)>>> Searching for NM... <<<\\cr\n'
        end
    end

    if eliminate_all_floor then
        ws_cache_update_positions()

        local mob_list = {}
        for idx, entry in pairs(ws_cache.mobs) do
            local mob = windower.ffxi.get_mob_by_index(idx)
            local entry_name = entry.name or ''
            local mob_name = (mob and mob.name) or ''
            if name_filter_match(entry_name) or name_filter_match(mob_name)
               or nm_match(entry_name) or nm_match(mob_name) then
            elseif mob and mob.valid_target and mob.hpp > 0 and (mob.x ~= 0 or mob.y ~= 0) then
                mob_list[#mob_list+1] = {
                    name = mob.name, x = mob.x, y = mob.y, z = mob.z,
                    hpp = mob.hpp, dist = compute_distance(playerpos, mob),
                    loaded = true,
                }
            elseif entry.x and entry.y then
                mob_list[#mob_list+1] = {
                    name = entry.name, x = entry.x, y = entry.y, z = entry.z,
                    hpp = entry.hpp or 100,
                    dist = compute_distance(playerpos, entry),
                    loaded = false,
                }
            else
                mob_list[#mob_list+1] = {
                    name = entry.name, x = nil, y = nil, z = nil,
                    hpp = 100, dist = 9999, loaded = false,
                }
            end
        end
        table.sort(mob_list, function(a, b) return a.dist < b.dist end)

        if #mob_list > 0 then
            local nearby_count = 0
            for _, m in ipairs(mob_list) do
                if m.loaded then nearby_count = nearby_count + 1 end
            end
            new_text = new_text .. ('\\cs(255,200,100)>>> Kill All: %d remaining (%d in range) <<<\\cr\n'):format(
                #mob_list, nearby_count)

            if auto_warp_all and mob_list[1].x and mob_list[1].dist > 15
               and player.status == 0
               and os.clock() - last_warp_time > 5.0 then
                local target = mob_list[1]
                windower.add_to_chat(200, ('Genie: Auto-warping to %s (%.0fy)...'):format(target.name, target.dist))
                teleport_to(target.x, target.y, target.z)
                last_warp_time = os.clock()
            end

            for _, entry in ipairs(mob_list) do
                local color = entry.x and dist_color(entry.dist) or '\\cs(120,120,120)'
                new_text = new_text .. color .. entry.name .. '\\cr'
                if entry.x then
                    local relDir = compute_relative_direction(playerpos, entry)
                    new_text = new_text .. ' - ' .. color .. math.round(entry.dist, 0) .. 'y\\cr '
                    if entry.loaded then
                        new_text = new_text .. color .. entry.hpp .. '%%\\cr '
                    end
                    new_text = new_text .. color .. direction_arrow(relDir) .. '\\cr'
                    if not entry.loaded then
                        new_text = new_text .. ' \\cs(120,120,120)(stale)\\cr'
                    end
                else
                    new_text = new_text .. ' \\cs(120,120,120)(no position)\\cr'
                end
                new_text = new_text .. '\n'
            end
        elseif ws_cache.last_refresh == 0 then
            new_text = new_text .. '\\cs(255,255,0)>>> Scanning floor... <<<\\cr\n'
        end
    end

    if specified_enemy_floor then
        ws_cache_update_positions()

        local mob_array = windower.ffxi.get_mob_array()
        for _, mob in pairs(mob_array) do
            if mob and mob.name and mob.name ~= '' and mob.is_npc
               and mob.spawn_type == 16 and mob.valid_target
               and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0)
               and not name_filter_match(mob.name)
               and not specified_enemy_excluded(mob.name) then
                queue_check(mob)
            end
        end

        local candidates = {}
        local seen = {}
        for idx, entry in pairs(specified_enemy_list) do
            local mob = windower.ffxi.get_mob_by_index(idx)
            if mob and mob.valid_target and mob.hpp > 0 and (mob.x ~= 0 or mob.y ~= 0) then
                candidates[#candidates+1] = {
                    index = idx, status = 'itg',
                    name = mob.name, x = mob.x, y = mob.y, z = mob.z,
                    hpp = mob.hpp, dist = compute_distance(playerpos, mob),
                    loaded = true,
                }
                seen[idx] = true
            elseif entry.x and entry.y then
                candidates[#candidates+1] = {
                    index = idx, status = 'itg',
                    name = entry.name, x = entry.x, y = entry.y, z = entry.z,
                    hpp = entry.hpp or 100,
                    dist = compute_distance(playerpos, entry),
                    loaded = false,
                }
                seen[idx] = true
            end
        end
        for idx, entry in pairs(ws_cache.mobs) do
            if not seen[idx]
               and check_cache[idx] ~= 'normal'
               and not name_filter_match(entry.name)
               and not nm_match(entry.name)
               and not specified_enemy_excluded(entry.name) then
                local mob = windower.ffxi.get_mob_by_index(idx)
                local status = (check_cache[idx] == 'pending') and 'pending' or 'unchecked'
                if mob and mob.valid_target and mob.hpp > 0 and (mob.x ~= 0 or mob.y ~= 0) then
                    candidates[#candidates+1] = {
                        index = idx, status = status,
                        name = mob.name, x = mob.x, y = mob.y, z = mob.z,
                        hpp = mob.hpp, dist = compute_distance(playerpos, mob),
                        loaded = true,
                    }
                elseif entry.x and entry.y then
                    candidates[#candidates+1] = {
                        index = idx, status = status,
                        name = entry.name, x = entry.x, y = entry.y, z = entry.z,
                        hpp = entry.hpp or 100,
                        dist = compute_distance(playerpos, entry),
                        loaded = false,
                    }
                end
            end
        end
        table.sort(candidates, function(a, b) return a.dist < b.dist end)

        local target_idx = player.target_index
        local target_is_itg = false
        local target_name = nil
        if target_idx and specified_enemy_list[target_idx] then
            target_is_itg = true
            local target_mob = windower.ffxi.get_mob_by_index(target_idx)
            target_name = (target_mob and target_mob.name) or specified_enemy_list[target_idx].name
        end

        if #candidates > 0 then
            local itg_count, unchecked_count = 0, 0
            for _, c in ipairs(candidates) do
                if c.status == 'itg' then itg_count = itg_count + 1
                else unchecked_count = unchecked_count + 1 end
            end
            new_text = new_text .. ('\\cs(255,50,50)>>> ITG: %d  |  Unchecked: %d <<<\\cr\n'):format(
                itg_count, unchecked_count)

            if auto_warp_single and candidates[1].x and candidates[1].dist > 15
               and player.status == 0
               and os.clock() - last_warp_time > 5.0 then
                local target = candidates[1]
                windower.add_to_chat(200, ('Genie: Auto-warping to %s (%.0fy)...'):format(target.name or '?', target.dist))
                teleport_to(target.x, target.y, target.z)
                last_warp_time = os.clock()
            end
            if target_is_itg then
                new_text = new_text .. ('\\cs(50,255,50)>>> TARGET IS ITG: %s <<<\\cr\n'):format(target_name or '?')
            end
            for _, c in ipairs(candidates) do
                local label = c.name or '?'
                local is_current_target = (target_idx == c.index)
                local row_color
                if c.status == 'itg' then
                    row_color = dist_color(c.dist)
                else
                    row_color = '\\cs(150,150,150)'
                end
                if is_current_target then
                    new_text = new_text .. ('\\cs(50,255,50)>> %s <<\\cr'):format(label)
                else
                    new_text = new_text .. row_color .. label .. '\\cr'
                end
                if c.status == 'pending' then
                    new_text = new_text .. ' \\cs(200,200,100)[?]\\cr'
                elseif c.status == 'unchecked' then
                    new_text = new_text .. ' \\cs(120,120,120)[unchecked]\\cr'
                end
                local relDir = compute_relative_direction(playerpos, c)
                new_text = new_text .. ' - ' .. row_color .. math.round(c.dist, 0) .. 'y\\cr '
                    .. row_color .. direction_arrow(relDir) .. '\\cr'
                if c.loaded then
                    new_text = new_text .. ' ' .. row_color .. 'HP:' .. c.hpp .. '%%\\cr\n'
                else
                    new_text = new_text .. ' \\cs(120,120,120)(stale)\\cr\n'
                end
            end
        else
            local checked = 0
            local total = 0
            for _, status in pairs(check_cache) do
                total = total + 1
                if status ~= 'pending' then checked = checked + 1 end
            end
            new_text = new_text .. '\\cs(255,255,0)>>> Scanning for ITG mobs... (' .. checked .. '/' .. total .. ') <<<\\cr\n'
        end
    end

    if specified_enemies_floor then
        ws_cache_update_positions()
        local mob_array = windower.ffxi.get_mob_array()

        if not specified_enemies_name then
            for _, mob in pairs(mob_array) do
                if mob and mob.name and mob.name ~= ''
                   and mob.is_npc and mob.spawn_type == 16 and mob.valid_target
                   and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0)
                   and NAME_TO_FAMILY[mob.name] then
                    queue_check(mob)
                end
            end
        else
            for _, mob in pairs(mob_array) do
                if mob and mob.name and mob.is_npc and mob.spawn_type == 16
                   and mob.valid_target and mob.hpp > 0
                   and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0)
                   and family_name_match(mob.name, specified_enemies_family) then
                    local existing = ws_cache.mobs[mob.index]
                    if existing then
                        existing.x = mob.x
                        existing.y = mob.y
                        existing.z = mob.z
                        existing.hpp = mob.hpp
                    else
                        ws_cache.mobs[mob.index] = {
                            name = mob.name, level = 0,
                            x = mob.x, y = mob.y, z = mob.z,
                            hpp = mob.hpp, last_refresh = os.clock(),
                        }
                    end
                end
            end
        end

        if specified_enemies_family then
            local matching = {}
            for idx, entry in pairs(ws_cache.mobs) do
                if family_name_match(entry.name, specified_enemies_family) then
                    local mob = windower.ffxi.get_mob_by_index(idx)
                    if mob and mob.valid_target and mob.hpp > 0 and (mob.x ~= 0 or mob.y ~= 0) then
                        matching[#matching+1] = {
                            name = mob.name, x = mob.x, y = mob.y, z = mob.z,
                            hpp = mob.hpp, dist = compute_distance(playerpos, mob),
                            loaded = true,
                        }
                    elseif entry.x and entry.y then
                        matching[#matching+1] = {
                            name = entry.name, x = entry.x, y = entry.y, z = entry.z,
                            hpp = entry.hpp or 100,
                            dist = compute_distance(playerpos, entry),
                            loaded = false,
                        }
                    else
                        matching[#matching+1] = {
                            name = entry.name, dist = 9999, loaded = false,
                        }
                    end
                end
            end
            table.sort(matching, function(a, b) return a.dist < b.dist end)

            if #matching > 0 then
                local nearby_count = 0
                for _, a in ipairs(matching) do if a.loaded then nearby_count = nearby_count + 1 end end
                new_text = new_text .. ('\\cs(255,50,50)>>> KILL FAMILY: %s (%d remaining, %d in range) <<<\\cr\n'):format(
                    specified_enemies_family, #matching, nearby_count)

                if auto_warp_family and matching[1].x and matching[1].dist > 15
                   and player.status == 0
                   and os.clock() - last_warp_time > 5.0 then
                    local target = matching[1]
                    windower.add_to_chat(200, ('Genie: Auto-warping to %s (%.0fy)...'):format(target.name or '?', target.dist))
                    teleport_to(target.x, target.y, target.z)
                    last_warp_time = os.clock()
                end
                local singular = FAMILY_SINGULAR[specified_enemies_family] or specified_enemies_family
                for _, a in ipairs(matching) do
                    local color = a.x and dist_color(a.dist) or '\\cs(120,120,120)'
                    new_text = new_text .. color .. singular .. '\\cr'
                    if a.x then
                        local relDir = compute_relative_direction(playerpos, a)
                        new_text = new_text .. ' - ' .. color .. math.round(a.dist, 0) .. 'y\\cr '
                            .. color .. direction_arrow(relDir) .. '\\cr'
                        if a.loaded then
                            new_text = new_text .. ' ' .. color .. 'HP:' .. a.hpp .. '%%\\cr\n'
                        else
                            new_text = new_text .. ' \\cs(120,120,120)(stale)\\cr\n'
                        end
                    else
                        new_text = new_text .. ' \\cs(120,120,120)(no position)\\cr\n'
                    end
                end
            elseif ws_cache.last_refresh == 0 then
                new_text = new_text .. '\\cs(255,255,0)>>> Scanning floor... <<<\\cr\n'
            end
        else
            local by_family = {}
            for idx, entry in pairs(ws_cache.mobs) do
                local fid = NAME_TO_FAMILY[entry.name]
                if not fid then
                    for f, _ in pairs(FAMILY_GROUPS) do
                        if family_name_match(entry.name, f) then fid = f; break end
                    end
                end
                if fid then
                    by_family[fid] = by_family[fid] or {}
                    local mob = windower.ffxi.get_mob_by_index(idx)
                    local rec
                    if mob and mob.valid_target and mob.hpp > 0 and (mob.x ~= 0 or mob.y ~= 0) then
                        rec = {
                            name = mob.name, x = mob.x, y = mob.y, z = mob.z,
                            hpp = mob.hpp, dist = compute_distance(playerpos, mob), loaded = true,
                        }
                    elseif entry.x and entry.y then
                        rec = {
                            name = entry.name, x = entry.x, y = entry.y, z = entry.z,
                            hpp = entry.hpp or 100, dist = compute_distance(playerpos, entry), loaded = false,
                        }
                    end
                    if rec then by_family[fid][#by_family[fid]+1] = rec end
                end
            end

            local checked, total = 0, 0
            for _, status in pairs(check_cache) do
                total = total + 1
                if status ~= 'pending' then checked = checked + 1 end
            end
            new_text = new_text .. ('\\cs(255,255,0)>>> Scanning for ITG family... (%d/%d) <<<\\cr\n'):format(checked, total)

            local family_ids = {}
            for fid in pairs(by_family) do family_ids[#family_ids+1] = fid end
            table.sort(family_ids)
            for _, fid in ipairs(family_ids) do
                local list = by_family[fid]
                table.sort(list, function(a, b) return a.dist < b.dist end)
                local singular = FAMILY_SINGULAR[fid] or fid
                new_text = new_text .. ('\\cs(200,200,255)-- %s (%d) --\\cr\n'):format(fid, #list)
                for _, a in ipairs(list) do
                    local color = a.x and dist_color(a.dist) or '\\cs(120,120,120)'
                    new_text = new_text .. color .. singular .. '\\cr'
                    if a.x then
                        local relDir = compute_relative_direction(playerpos, a)
                        new_text = new_text .. ' - ' .. color .. math.round(a.dist, 0) .. 'y\\cr '
                            .. color .. direction_arrow(relDir) .. '\\cr'
                        if a.loaded then
                            new_text = new_text .. ' ' .. color .. 'HP:' .. a.hpp .. '%%\\cr\n'
                        else
                            new_text = new_text .. ' \\cs(120,120,120)(stale)\\cr\n'
                        end
                    else
                        new_text = new_text .. ' \\cs(120,120,120)(no position)\\cr\n'
                    end
                end
            end
        end
    end

    if currentFloorRuneFilter == 0 and tLamps[0x2D2].id ~= nil and tLamps[0x2D3].id ~= nil then
        local rune1 = tLamps[0x2D2]
        local rune2 = tLamps[0x2D3]
        if rune1.id ~= nil and rune2.id ~= nil then
            local d1 = compute_distance(playerpos, rune1)
            local d2 = compute_distance(playerpos, rune2)
            if d1 < d2 then
                currentFloorRuneFilter = rune2.index
            else
                currentFloorRuneFilter = rune1.index
            end
        end
    end

    for i = 1, 7 do
        local target = tLamps[SORTED_INDEXES[i]]
        if target.id ~= nil and target.name ~= 'Rune of Transfer' then
            local distance = compute_distance(playerpos, target)
            if not (target.x == 0 and target.y == 0) and distance < 300 and target.index ~= currentFloorRuneFilter then
                local isRunicLamp = target.name == 'Runic Lamp'
                if not isRunicLamp or lampFloorDetected then
                    local relDir = compute_relative_direction(playerpos, target)
                    new_text = new_text .. target.name
                    if isRunicLamp then
                        new_text = new_text .. ' ' .. get_lamp_letter(target.index)
                        lampCountCheck = lampCountCheck + 1
                    end
                    if debugmode then
                        new_text = new_text .. ' ID: [' .. target.index .. ']'
                    end
                    new_text = new_text .. ' - \\cs(200,200,200)' .. math.round(distance, 0) .. ' Yalms\\cr \\cs(255,255,255)' .. direction_arrow(relDir) .. '\\cr \n'
                end
            end
        end
    end

    if lampCount ~= lampCountCheck then
        if debugmode then
            windower.add_to_chat(200, 'Genie Debug - Lamp quantity changed to ' .. lampCountCheck .. '.')
        end
        lampCount = lampCountCheck
    end

    if debugmode then
        local info = windower.ffxi.get_info()
        new_text = new_text .. '\n' .. player.name .. ' status:' .. player.status .. ' x:' .. math.round(playerpos.x, 2) .. ' y:' .. math.round(playerpos.y, 2) .. ' z:' .. math.round(playerpos.z, 2)
        new_text = new_text .. '\nZone: ' .. info.zone .. ' (' .. currentZone .. ')'
        new_text = new_text .. '\nLampCount: ' .. lampCount
    end

    local tidx = player.target_index
    if tidx ~= nil then
        local target = windower.ffxi.get_mob_by_index(tidx)
        if target ~= nil and debugmode then
            local distance = compute_distance(playerpos, target)
            local relDir = compute_relative_direction(playerpos, target)
            if target.name == 'Runic Lamp' then
                new_text = new_text .. '\n[' .. get_lamp_letter(target.index) .. '] '
            end
            new_text = new_text .. '\n' .. target.name .. ' x:' .. math.round(target.x, 2) .. ' y:' .. math.round(target.y, 2) .. ' z:' .. math.round(target.z, 2)
            new_text = new_text .. '\nIndex:' .. target.index .. ' status:' .. tostring(target.status) .. ' entity_type:' .. tostring(target.entity_type) .. ' spawn_type:' .. tostring(target.spawn_type)
            new_text = new_text .. '\nDistance:' .. math.round(distance, 1) .. ' Direction:' .. math.round(relDir, 1) .. ' ' .. direction_arrow(relDir)
        end
    elseif debugmode then
        new_text = new_text .. '\n\nNo target'
    end

    if objectiveCompleted then
        new_text = new_text .. '\n\\cs(0,255,0)Floor objective completed!\\cr'
    end

    text_box:text(new_text)
    text_box:visible(string.len(new_text) > 0)
end

-------------------------------------------------------------------------------
-- Commands
-------------------------------------------------------------------------------
local function cmd_solve()
    if solver_active then
        windower.add_to_chat(167, 'Genie: Solver already running. Use //genie cancel to stop.')
        return
    end
    request_all_lamps()
    solver_opt = 1
    coroutine.schedule(function()
        solver_lamps = {}
        for _, idx in ipairs(SORTED_LAMP_INDEXES) do
            local npc = windower.ffxi.get_mob_by_index(idx)
            if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                if npc.name == 'Runic Lamp' then
                    solver_lamps[#solver_lamps+1] = {
                        index = npc.index, npc_id = npc.id,
                        x = npc.x, y = npc.y, z = npc.z,
                    }
                elseif debugmode then
                    windower.add_to_chat(200, ('Genie SOLVER: Skipping index %d - name is "%s", not Runic Lamp'):format(idx, npc.name or '?'))
                end
            end
        end
        if #solver_lamps < 1 then
            windower.add_to_chat(167, 'Genie: No lamps found.')
            return
        end
        solver_perms = generate_permutations(#solver_lamps)
        solver_perm_idx = 0
        solver_step = 0
        solver_wait_time = 0
        solver_known_prefix = {}
        lamp_unlit_set = {}
        solver_step_clicks = {}
        solver_active = true
        objectiveCompleted = false
        if debugmode then
            windower.add_to_chat(200, ('Genie SOLVER: Found %d lamps. %d permutations to try. Starting...'):format(
                #solver_lamps, #solver_perms))
        end
        log_lamp_states('BASELINE - all lamps unlit')
        solver_start_next_perm()
    end, 1.5)
end

local CMD_GROUP_A = {
    debug=1, solve=1, pause=1, resume=1, cancel=1,
    poke=1, certify=1, auto=1, warp=1, next=1,
}
local function handle_cmd_a(cmd, arg)
    if not CMD_GROUP_A[cmd] then return false end

    if cmd == 'debug' then
        debugmode = not debugmode
        windower.add_to_chat(200, ('Genie: Debug mode %s'):format(debugmode and 'ON' or 'OFF'))
        if not debugmode then text_box:visible(false) end

    elseif cmd == 'solve' then
        cmd_solve()

    elseif cmd == 'pause' then
        solver_pause()

    elseif cmd == 'resume' then
        solver_resume()

    elseif cmd == 'cancel' then
        local cancelled = false
        if solver_active then
            solver_active = false
            solver_paused = false
            poke_target = nil
            cancelled = true
        end
        if simultaneous_floor then
            simultaneous_floor = false
            simultaneous_lamps = {}
            simultaneous_step = 0
            simultaneous_done_time = 0
            poke_target = nil
            cancelled = true
        end
        if cancelled then
            windower.add_to_chat(200, 'Genie: Cancelled.')
        else
            windower.add_to_chat(200, 'Genie: Nothing to cancel.')
        end

    elseif cmd == 'poke' then
        local opt_val = 1
        local target_idx = nil
        if #arg >= 2 then
            local letter_map = { a=0x2D4, b=0x2D5, c=0x2D6, d=0x2D7, e=0x2D8 }
            target_idx = letter_map[arg[2]:lower()]
        else
            local me = windower.ffxi.get_mob_by_target('me')
            local best_dist = 99999
            if me then
                for _, idx in ipairs(SORTED_LAMP_INDEXES) do
                    local npc = windower.ffxi.get_mob_by_index(idx)
                    if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                        local dx, dy, dz = npc.x - me.x, npc.y - me.y, npc.z - me.z
                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                        if dist < best_dist then
                            best_dist = dist
                            target_idx = idx
                        end
                    end
                end
            end
        end
        if not target_idx then
            windower.add_to_chat(167, 'Genie: No lamp found. Usage: //genie poke [a-e]')
            return
        end
        request_entity(target_idx)
        local npc = windower.ffxi.get_mob_by_index(target_idx)
        if not npc or (npc.x == 0 and npc.y == 0 and npc.z == 0) then
            windower.add_to_chat(167, ('Genie: Lamp (index=%d) not loaded.'):format(target_idx))
            return
        end
        windower.add_to_chat(200, ('Genie: Poking lamp %s (index=%d)...'):format(get_lamp_letter(target_idx), target_idx))
        poke_target = {
            index = target_idx,
            npc_id = npc.id,
            x = npc.x, y = npc.y, z = npc.z,
            opt = opt_val,
            spoof_count = 0,
            state = 'SPOOF',
        }

    elseif cmd == 'certify' then
        windower.send_ipc_message('genie certify')
        do_certify()

    elseif cmd == 'auto' then
        auto_solve = not auto_solve
        windower.add_to_chat(200, ('Genie: Auto-solve %s'):format(auto_solve and 'ON' or 'OFF'))
        genie_settings.auto_solve = auto_solve
        settings_save()

    elseif cmd == 'warp' then
        local sub = arg[2] and arg[2]:lower()
        if sub == 'nm' then
            auto_warp_nm = not auto_warp_nm
            windower.add_to_chat(200, ('Genie: Auto-warp NM (Eliminate enemy leader) %s'):format(auto_warp_nm and 'ON' or 'OFF'))
            genie_settings.auto_warp_nm = auto_warp_nm
        elseif sub == 'all' then
            auto_warp_all = not auto_warp_all
            windower.add_to_chat(200, ('Genie: Auto-warp ALL (Eliminate all enemies) %s'):format(auto_warp_all and 'ON' or 'OFF'))
            genie_settings.auto_warp_all = auto_warp_all
        elseif sub == 'family' then
            auto_warp_family = not auto_warp_family
            windower.add_to_chat(200, ('Genie: Auto-warp FAMILY (Specified enemies) %s'):format(auto_warp_family and 'ON' or 'OFF'))
            genie_settings.auto_warp_family = auto_warp_family
        elseif sub == 'single' then
            auto_warp_single = not auto_warp_single
            windower.add_to_chat(200, ('Genie: Auto-warp SINGLE (Specified enemy) %s'):format(auto_warp_single and 'ON' or 'OFF'))
            genie_settings.auto_warp_single = auto_warp_single
        else
            windower.add_to_chat(200, 'Genie: Auto-warp toggles (current state):')
            windower.add_to_chat(200, ('  //genie warp nm     - %s (Eliminate enemy leader)'):format(auto_warp_nm and 'ON' or 'OFF'))
            windower.add_to_chat(200, ('  //genie warp all    - %s (Eliminate all enemies)'):format(auto_warp_all and 'ON' or 'OFF'))
            windower.add_to_chat(200, ('  //genie warp family - %s (Specified enemies)'):format(auto_warp_family and 'ON' or 'OFF'))
            windower.add_to_chat(200, ('  //genie warp single - %s (Specified enemy)'):format(auto_warp_single and 'ON' or 'OFF'))
            return
        end
        settings_save()

    elseif cmd == 'next' then
        if eliminate_all_floor or specified_enemies_floor then
            local mob_array = windower.ffxi.get_mob_array()
            local me = windower.ffxi.get_mob_by_target('me')
            local best = nil
            local best_dist = 99999
            if me then
                for _, mob in pairs(mob_array) do
                    if mob and mob.name and mob.name ~= '' and mob.is_npc
                       and mob.spawn_type == 16 and mob.valid_target and mob.hpp > 0
                       and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0)
                       and not FILTER_NAMES[mob.name] then
                        if not specified_enemies_floor or mob.name == specified_enemies_name then
                            local dx, dy = mob.x - me.x, mob.y - me.y
                            local dist = math.sqrt(dx*dx + dy*dy)
                            if dist < best_dist then
                                best_dist = dist
                                best = mob
                            end
                        end
                    end
                end
            end
            if best then
                windower.add_to_chat(200, ('Genie: Warping to %s (%.0fy)...'):format(best.name, best_dist))
                teleport_to(best.x, best.y, best.z)
            else
                windower.add_to_chat(167, 'Genie: No enemies remaining.')
            end
        else
            windower.add_to_chat(167, 'Genie: Not on a kill floor.')
        end

    end
    return true
end

local CMD_GROUP_B = {
    autocertify=1, runner=1, runtest=1, mode=1, runnow=1, release=1,
    findnm=1, gotonm=1, nm=1, ['goto']=1, scan=1, nmlist=1,
    loglamps=1, capture=1, rescan=1, wsnm=1, wscount=1, wsgo=1, help=1, save=1, settings=1,
}
local function handle_cmd_b(cmd, arg)
    if not CMD_GROUP_B[cmd] then return false end

    if cmd == 'autocertify' then
        autocertify_enabled = not autocertify_enabled
        windower.add_to_chat(200, ('Genie: Auto-certify %s'):format(autocertify_enabled and 'ON' or 'OFF'))

    elseif cmd == 'runner' then
        if #arg < 2 then
            if rune_runner_name then
                windower.add_to_chat(200, ('Genie: Rune runner is %s.'):format(rune_runner_name))
            else
                windower.add_to_chat(200, 'Genie: No rune runner assigned.')
            end
        else
            local target = arg[2]
            if target:lower() == 'none' or target:lower() == 'off' then
                rune_runner_name = nil
                windower.add_to_chat(200, 'Genie: Rune runner cleared.')
                windower.send_ipc_message('genie runner_set none')
                genie_settings.rune_runner = ''
                settings_save()
            else
                if target:lower() == 'me' then
                    local p = windower.ffxi.get_player()
                    if p then target = p.name end
                end
                rune_runner_name = target
                windower.add_to_chat(200, ('Genie: Rune runner set to %s. Broadcasting via IPC...'):format(target))
                windower.send_ipc_message('genie runner_set ' .. target)
                genie_settings.rune_runner = target
                settings_save()
            end
        end

    elseif cmd == 'runtest' then
        local p = windower.ffxi.get_player()
        local me = p and p.name or '?'
        windower.add_to_chat(200, ('Genie: Sending runtest from %s. Watch for replies...'):format(me))
        windower.send_ipc_message('genie runtest ' .. me)
        if is_rune_runner() then
            windower.add_to_chat(200, ('Genie: [%s] I AM the designated runner.'):format(me))
        else
            windower.add_to_chat(200, ('Genie: [%s] I am NOT the runner (assigned: %s).'):format(
                me, rune_runner_name or 'none'))
        end

    elseif cmd == 'mode' then
        local new_mode
        if #arg >= 2 then
            local sub = arg[2]:lower()
            if sub == 'exit' then
                new_mode = 'exit'
            elseif sub == 'up' then
                new_mode = 'up'
            else
                new_mode = (rune_mode == 'up') and 'exit' or 'up'
            end
        else
            new_mode = (rune_mode == 'up') and 'exit' or 'up'
        end
        rune_mode = new_mode
        windower.add_to_chat(200, ('Genie: Rune mode set to %s. Broadcasting via IPC...'):format(rune_mode:upper()))
        windower.send_ipc_message('genie mode_set ' .. new_mode)

    elseif cmd == 'runnow' then
        if not is_rune_runner() then
            windower.add_to_chat(167, 'Genie: This character is not the designated rune runner.')
        else
            rune_active = true
            rune_attempts = 0
            windower.add_to_chat(200, ('Genie: Forcing rune click (mode=%s)...'):format(rune_mode))
            coroutine.schedule(poke_rune, 0.5)
        end

    elseif cmd == 'release' then
        do_release()

    elseif cmd == 'findnm' then
        local nm = find_nyzul_nm()
        if nm then
            windower.add_to_chat(200, ('Genie: Found NM: %s (index=%d) at (%.1f, %.1f, %.1f) dist=%.1f'):format(
                nm.name, nm.index, nm.x, nm.y, nm.z, math.sqrt(nm.distance)))
        else
            start_nm_scan(function(found)
                if found then
                    windower.add_to_chat(200, ('Genie: Found NM: %s (index=%d) HP:%d%% at (%.1f, %.1f, %.1f)'):format(
                        found.name, found.index, found.hpp or 0, found.x, found.y, found.z))
                else
                    windower.add_to_chat(167, 'Genie: No live NM found.')
                end
            end)
        end

    elseif cmd == 'gotonm' or cmd == 'nm' then
        if eliminate_leader then
            local mob = windower.ffxi.get_mob_by_index(eliminate_leader.index)
            if mob and mob.valid_target and (mob.x ~= 0 or mob.y ~= 0) then
                windower.add_to_chat(200, ('Genie: Teleporting to %s...'):format(mob.name))
                teleport_to(mob.x, mob.y, mob.z)
            elseif eliminate_leader.x and eliminate_leader.x ~= 0 then
                windower.add_to_chat(200, ('Genie: Teleporting to %s (cached pos)...'):format(eliminate_leader.name))
                teleport_to(eliminate_leader.x, eliminate_leader.y, eliminate_leader.z)
            else
                windower.add_to_chat(167, 'Genie: NM position unknown.')
            end
            return
        end
        local nm = find_nyzul_nm()
        if nm then
            windower.add_to_chat(200, ('Genie: Found %s - teleporting...'):format(nm.name))
            teleport_to(nm.x, nm.y, nm.z)
        else
            start_nm_scan(function(found)
                if found then
                    windower.add_to_chat(200, ('Genie: Found %s - teleporting...'):format(found.name))
                    teleport_to(found.x, found.y, found.z)
                else
                    windower.add_to_chat(167, 'Genie: No live NM found.')
                end
            end)
        end

    elseif cmd == 'goto' then
        if #arg < 2 then
            windower.add_to_chat(167, 'Genie: Usage: //genie goto <index>')
            return
        end
        local idx = tonumber(arg[2])
        if not idx then
            windower.add_to_chat(167, 'Genie: Invalid index.')
            return
        end
        request_entity(idx)
        coroutine.schedule(function()
            local npc = windower.ffxi.get_mob_by_index(idx)
            if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                windower.add_to_chat(200, ('Genie: Teleporting to %s (index=%d)...'):format(npc.name or '?', idx))
                teleport_to(npc.x, npc.y, npc.z)
            else
                windower.add_to_chat(167, ('Genie: Entity %d not loaded or at (0,0,0).'):format(idx))
            end
        end, 0.5)

    elseif cmd == 'scan' then
        local show_all = (#arg >= 2 and arg[2]:lower() == 'all')
        local mob_array = windower.ffxi.get_mob_array()
        local count = 0
        for _, mob in pairs(mob_array) do
            if mob and mob.name and mob.name ~= '' and mob.is_npc then
                local is_nm = NYZUL_NM_SET[mob.name]
                if is_nm or show_all then
                    local dist = mob.distance and math.sqrt(mob.distance) or 0
                    local tag = is_nm and ' *NM*' or ''
                    windower.add_to_chat(200, ('  [%d] %s  (%.1f, %.1f, %.1f)  dist=%.0f%s'):format(
                        mob.index, mob.name, mob.x, mob.y, mob.z, dist, tag))
                    count = count + 1
                end
            end
        end
        windower.add_to_chat(200, ('Genie: Scanned %d entities.'):format(count))

    elseif cmd == 'nmlist' then
        local indices = get_nm_dat_indices()
        local sorted = {}
        for name, idx in pairs(indices) do
            sorted[#sorted+1] = { name = name, idx = idx }
        end
        table.sort(sorted, function(a, b) return a.idx < b.idx end)
        windower.add_to_chat(200, ('Genie: NM indices from DAT (%d/%d):'):format(#sorted, #NYZUL_NMS))
        for _, entry in ipairs(sorted) do
            windower.add_to_chat(200, ('  [%d] %s'):format(entry.idx, entry.name))
        end
        local missing = {}
        for _, name in ipairs(NYZUL_NMS) do
            if not indices[name] then missing[#missing+1] = name end
        end
        if #missing > 0 then
            windower.add_to_chat(167, ('  Not in DAT: %s'):format(table.concat(missing, ', ')))
        end

    elseif cmd == 'loglamps' then
        local label = (#arg >= 2 and arg[2]) or 'manual'
        log_lamp_states(label, true)

    elseif cmd == 'capture' then
        local label = (#arg >= 2 and arg[2]) or 'capture'
        local seconds = (#arg >= 3 and tonumber(arg[3])) or 8
        packet_capture.active = true
        packet_capture.end_time = os.clock() + seconds
        packet_capture.label = label
        local f = io.open(windower.addon_path .. 'data\\packet_capture.log', 'a')
        if f then
            f:write(('\n=== Capture %s STARTED @ %s for %ds ===\n'):format(label, os.date('%H:%M:%S'), seconds))
            f:close()
        end
        windower.add_to_chat(200, ('Genie: Packet capture %s started (%ds)'):format(label, seconds))

    elseif cmd == 'rescan' then
        ws_cache.mobs = {}
        ws_cache.last_refresh = 0
        if eliminate_all_floor then
            ws_refresh_cache(true)
        elseif specified_enemy_floor or specified_enemies_floor then
            ws_preload_for_check()
        else
            ws_refresh_cache(false)
        end
        windower.add_to_chat(200, 'Genie: Cache cleared, widescan rescanning...')

    elseif cmd == 'wsnm' then
        ws_find_nm(function(found)
            if found and found.x then
                windower.add_to_chat(200, ('Genie: NM %s at (%.1f, %.1f, %.1f)'):format(
                    found.name, found.x, found.y, found.z))
            else
                windower.add_to_chat(200, 'Genie: Widescan range too limited - falling back to DAT scan...')
                start_nm_scan(function(nm)
                    if nm then
                        windower.add_to_chat(200, ('Genie: Found NM via DAT: %s at (%.1f, %.1f, %.1f)'):format(
                            nm.name, nm.x, nm.y, nm.z))
                    else
                        windower.add_to_chat(167, 'Genie: No live NM found by either method.')
                    end
                end)
            end
        end)

    elseif cmd == 'wscount' then
        ws_count_enemies(function(count, results)
            for _, r in ipairs(results) do
                local tag = ''
                if NYZUL_NM_SET[r.name] then tag = ' *NM*' end
                if FILTER_NAMES[r.name] then tag = ' (filtered)' end
                windower.add_to_chat(200, ('  [%d] Lv%d %s  grid(%d,%d)%s'):format(
                    r.index, r.level, r.name, r.x_off, r.y_off, tag))
            end
        end)

    elseif cmd == 'wsgo' then
        ws_find_nm(function(found)
            if found then
                coroutine.schedule(function()
                    if ws_scan.nm_found and ws_scan.nm_found.x then
                        windower.add_to_chat(200, ('Genie: Teleporting to %s...'):format(ws_scan.nm_found.name))
                        teleport_to(ws_scan.nm_found.x, ws_scan.nm_found.y, ws_scan.nm_found.z)
                    else
                        request_entity(found.index)
                        coroutine.schedule(function()
                            local npc = windower.ffxi.get_mob_by_index(found.index)
                            if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                                windower.add_to_chat(200, ('Genie: Teleporting to %s...'):format(npc.name))
                                teleport_to(npc.x, npc.y, npc.z)
                            else
                                windower.add_to_chat(167, 'Genie: Could not get coordinates.')
                            end
                        end, 0.5)
                    end
                end, 1.0)
            end
        end)

    elseif cmd == 'save' then
        genie_settings.auto_solve        = auto_solve
        genie_settings.auto_warp_nm      = auto_warp_nm
        genie_settings.auto_warp_all     = auto_warp_all
        genie_settings.auto_warp_family  = auto_warp_family
        genie_settings.auto_warp_single  = auto_warp_single
        genie_settings.rune_runner       = rune_runner_name or ''
        local lua_ok = genie_state_save(genie_settings)
        local xml_ok = pcall(function() settings:save('all') end)
        windower.add_to_chat(200, ('Genie: Settings saved (lua=%s, xml=%s).'):format(
            tostring(lua_ok), tostring(xml_ok)))
        windower.add_to_chat(200, ('  auto_solve=%s warp[nm=%s all=%s family=%s single=%s] runner=%s'):format(
            tostring(auto_solve), tostring(auto_warp_nm), tostring(auto_warp_all),
            tostring(auto_warp_family), tostring(auto_warp_single),
            rune_runner_name or 'none'))

    elseif cmd == 'settings' then
        local p = windower.ffxi.get_player()
        local me = p and p.name or '?'
        local on = function(b) return b and 'ON' or 'OFF' end
        local runner_label
        if rune_runner_name then
            runner_label = rune_runner_name
            if is_rune_runner() then runner_label = runner_label .. ' (this client)' end
        else
            runner_label = 'none'
        end
        windower.add_to_chat(200, ('Genie settings for %s:'):format(me))
        windower.add_to_chat(200, ('  auto_solve       : %s'):format(on(auto_solve)))
        windower.add_to_chat(200, ('  auto_warp_nm     : %s   (Eliminate enemy leader)'):format(on(auto_warp_nm)))
        windower.add_to_chat(200, ('  auto_warp_all    : %s   (Eliminate all enemies)'):format(on(auto_warp_all)))
        windower.add_to_chat(200, ('  auto_warp_family : %s   (Specified enemies)'):format(on(auto_warp_family)))
        windower.add_to_chat(200, ('  auto_warp_single : %s   (Specified enemy)'):format(on(auto_warp_single)))
        windower.add_to_chat(200, ('  autocertify      : %s'):format(on(autocertify_enabled)))
        windower.add_to_chat(200, ('  rune_runner      : %s'):format(runner_label))
        windower.add_to_chat(200, ('  rune_mode        : %s'):format(rune_mode:upper()))
        windower.add_to_chat(200, ('  debug            : %s'):format(on(debugmode)))
        if settings and settings.hud and settings.hud.pos then
            windower.add_to_chat(200, ('  hud_pos          : x=%d y=%d'):format(
                settings.hud.pos.x or 0, settings.hud.pos.y or 0))
        end
        windower.add_to_chat(200, ('  state file       : %s'):format(genie_state_path()))

    elseif cmd == 'help' then
        windower.add_to_chat(200, 'Genie Commands:')
        windower.add_to_chat(200, '  //genie auto - Toggle auto-solve on lamp floors (default: OFF)')
        windower.add_to_chat(200, '  //genie warp [nm|all|family|single] - Toggle auto-warp per floor type')
        windower.add_to_chat(200, '  //genie next - Teleport to nearest enemy on kill floors')
        windower.add_to_chat(200, '  //genie solve - Manually solve lamp order (handles certification too)')
        windower.add_to_chat(200, '  //genie poke [a-e] - Spoof+poke a lamp')
        windower.add_to_chat(200, '  //genie certify - All party members poke certification lamp')
        windower.add_to_chat(200, '  //genie autocertify - Toggle auto-certify (default: ON)')
        windower.add_to_chat(200, '  //genie runner <name|me|none> - Designate a character to click Rune of Transfer')
        windower.add_to_chat(200, '  //genie mode [up|exit] - Toggle Rune mode (no arg = toggle)')
        windower.add_to_chat(200, '  //genie runnow - Force the runner to click the rune now')
        windower.add_to_chat(200, '  //genie release - Force-close menu and unstick character')
        windower.add_to_chat(200, '  //genie findnm - Find NM (zone-wide via DAT lookup + 0x016)')
        windower.add_to_chat(200, '  //genie nm - Teleport to NM (uses floor scan if available)')
        windower.add_to_chat(200, '  //genie gotonm - Same as nm')
        windower.add_to_chat(200, '  //genie goto <idx> - Teleport to entity by index')
        windower.add_to_chat(200, '  //genie scan [all] - Show NMs (or all mobs) in entity table')
        windower.add_to_chat(200, '  //genie nmlist - Show confirmed NM indices from DAT')
        windower.add_to_chat(200, '  //genie wsnm - Find NM via widescan (fast, zone-wide)')
        windower.add_to_chat(200, '  //genie wsgo - Find NM via widescan + teleport')
        windower.add_to_chat(200, '  //genie wscount - Count all enemies via widescan')
        windower.add_to_chat(200, '  //genie pause - Pause solver')
        windower.add_to_chat(200, '  //genie resume - Resume paused solver')
        windower.add_to_chat(200, '  //genie cancel - Stop solver')
        windower.add_to_chat(200, '  //genie debug - Toggle debug mode')
        windower.add_to_chat(200, '  //genie settings - Show all current settings')
        windower.add_to_chat(200, '  //genie save - Save all current settings to data/settings.xml')
        windower.add_to_chat(200, '  //genie help - Show this text')

    end
    return true
end

windower.register_event('addon command', function(...)
    local arg = {...}
    if #arg == 0 then
        windower.add_to_chat(200, 'Genie v' .. _addon.version .. ' - //genie help')
        return
    end
    local cmd = arg[1]:lower()
    if not handle_cmd_a(cmd, arg) and not handle_cmd_b(cmd, arg) then
        windower.add_to_chat(167, 'Genie: Unknown command. //genie help')
    end
end)

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id == 0x015 and poke_target and poke_target.state == 'SPOOF' then
        local p = packets.parse('outgoing', data)
        if not p then return end
        p['X'] = poke_target.x
        p['Y'] = poke_target.y
        p['Z'] = poke_target.z
        poke_target.spoof_count = poke_target.spoof_count + 1
        if poke_target.spoof_count >= 2 then
            poke_target.state = 'POKE'
            request_entity(poke_target.index)
            local poke = packets.new('outgoing', 0x01A)
            poke['Target']       = poke_target.npc_id
            poke['Target Index'] = poke_target.index
            poke['Category']     = 0x00
            poke['Param']        = 0
            packets.inject(poke)
            if debugmode then
                windower.add_to_chat(200, ('Genie: Spoofed + poked (index=%d)'):format(poke_target.index))
            end
            if poke_target.is_certify then
                windower.add_to_chat(200, 'Genie: Certification poke sent.')
                poke_target = nil
            end
        end
        return packets.build(p)
    end
end)

windower.register_event('incoming chunk', function(id, data)
    if packet_capture.active then
        if os.clock() > packet_capture.end_time then
            packet_capture.active = false
            local f = io.open(windower.addon_path .. 'data\\packet_capture.log', 'a')
            if f then
                f:write(('=== Capture %s ENDED @ %s ===\n\n'):format(packet_capture.label, os.date('%H:%M:%S')))
                f:close()
            end
            windower.add_to_chat(200, 'Genie: Packet capture ended.')
        else
            local f = io.open(windower.addon_path .. 'data\\packet_capture.log', 'a')
            if f then
                local raw = {}
                for i = 1, math.min(#data, 96) do
                    raw[#raw+1] = string.format('%02X', data:byte(i))
                end
                f:write(('[%s] 0x%03X len=%d: %s\n'):format(
                    os.date('%H:%M:%S'), id, #data, table.concat(raw, ' ')))
                f:close()
            end
        end
    end

    if id == 0x0E then
        local packet = packets.parse('incoming', data)
        local mob_index = packet['Index']

        if tLamps[mob_index] then
            local mob = windower.ffxi.get_mob_by_index(mob_index)
            if mob and (mob.name == 'Runic Lamp' or mob.name == 'Rune of Transfer') then
                tLamps[mob_index] = mob
            end
            if debugmode and LAMP_INDEX_TO_NUM[mob_index] then
                local updatemask = data:unpack('b', 0x0A + 1)
                local letter = get_lamp_letter(mob_index)
                local state_byte = #data >= 43 and data:byte(43) or nil
                windower.add_to_chat(200, ('  0x0E Lamp %s [%d] len=%d mask=0x%02X state=%s'):format(
                    letter, mob_index, #data, updatemask or 0, tostring(state_byte)))
            end

            if solver_active and LAMP_INDEX_TO_NUM[mob_index] and #data >= 43 then
                local updatemask = data:unpack('b', 0x0A + 1)
                local state_byte = data:byte(43)
                if updatemask and bit.band(updatemask, 0x04) == 0x04 and state_byte == 0x05 then
                    if not lamp_unlit_set[mob_index] then
                        lamp_unlit_set[mob_index] = true
                        if debugmode then
                            windower.add_to_chat(200, ('Genie SOLVER: Lamp %s wrong (turn-off detected)'):format(
                                get_lamp_letter(mob_index)))
                        end
                    end
                end
            end
        end

        if nm_scan.active and nm_scan.pending[mob_index] then
            local updatemask = data:unpack('b', 0x0A + 1)
            local entity_id = data:unpack('I', 0x04 + 1)
            local x, z, y = 0, 0, 0
            local hpp = -1
            local name = ''
            if updatemask and bit.band(updatemask, 0x01) == 0x01 then
                x, z, y = data:unpack('fff', 0x0C + 1)
            end
            if updatemask and bit.band(updatemask, 0x04) == 0x04 then
                hpp = data:unpack('c', 0x1E + 1)
            end
            if updatemask and bit.band(updatemask, 0x08) == 0x08 then
                for i = 1, (#data - 0x34) do
                    local c = data:byte(0x34 + i)
                    if c and c ~= 0 then name = name .. string.char(c) end
                end
            end
            if defeated_nm_set[mob_index] then
                windower.add_to_chat(200, ('  Skipping %s (index=%d) - already defeated this run'):format(
                    nm_scan.indices[nm_scan.pos].name, mob_index))
            elseif x ~= 0 or y ~= 0 or z ~= 0 then
                local me = windower.ffxi.get_mob_by_target('me')
                local too_far = false
                if me then
                    local dx = x - me.x
                    local dy = y - me.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist > 150 then
                        too_far = true
                        windower.add_to_chat(200, ('  Skipping %s (index=%d) - too far (%.0fy, likely stale)'):format(
                            nm_scan.indices[nm_scan.pos].name, mob_index, dist))
                    end
                end
                if hpp == 0 then
                    windower.add_to_chat(200, ('  Skipping %s (index=%d) - hpp=0 (dead)'):format(
                        nm_scan.indices[nm_scan.pos].name, mob_index))
                elseif too_far then
                else
                    nm_scan.found = {
                        name = name ~= '' and name or nm_scan.indices[nm_scan.pos].name,
                        index = mob_index,
                        x = x, y = y, z = z,
                        id = entity_id,
                        hpp = hpp,
                    }
                    windower.add_to_chat(200, ('  FOUND: %s (index=%d) HP:%d%% at (%.1f, %.1f, %.1f)'):format(
                        nm_scan.found.name, mob_index, hpp, x, y, z))
                end
            end
            nm_scan.pending[mob_index] = nil
            if mob_index == nm_scan.last_req_idx then
                nm_scan_next()
            end
        end

    elseif id == 0x036 and solver_active and #data >= 16 then
        if debugmode then
            local idx = data:byte(9) + (data:byte(10) * 256)
            if LAMP_INDEX_TO_NUM[idx] then
                local b13 = data:byte(14)
                local b14 = data:byte(15)
                local b15 = data:byte(16)
                local letter = get_lamp_letter(idx)
                local kind = 'rejected'
                if b13 == 0xFF and b14 == 0xFF and b15 == 0xFF then
                    kind = 'fresh-lit (FF FF FF)'
                elseif b13 ~= 0 or b14 ~= 0 or b15 ~= 0 then
                    kind = ('non-zero (%02X %02X %02X)'):format(b13, b14, b15)
                end
                windower.add_to_chat(200, ('Genie 0x036: Lamp %s - %s'):format(letter, kind))
            end
        end

    elseif id == 0x034 and poke_target and poke_target.state == 'POKE' then
        local p = packets.parse('incoming', data)
        if not p then return end
        local mid = p['Menu ID']
        local zone = windower.ffxi.get_info().zone
        local t = poke_target

        if t.is_rune then
            windower.add_to_chat(200, ('Genie: Rune menu - sending mode=%s (Opt=%d)'):format(rune_mode, t.opt))
            local ack = packets.new('outgoing', 0x05B, {
                ['Target']            = p['NPC'],
                ['Target Index']      = p['NPC Index'],
                ['Zone']              = p['Zone'],
                ['Menu ID']           = mid,
                ['Option Index']      = 0,
                ['Automated Message'] = true,
            })
            packets.inject(ack)
            local choice = packets.new('outgoing', 0x05B, {
                ['Target']            = p['NPC'],
                ['Target Index']      = p['NPC Index'],
                ['Zone']              = p['Zone'],
                ['Menu ID']           = mid,
                ['Option Index']      = t.opt,
                ['Automated Message'] = false,
            })
            packets.inject(choice)
            windower.packets.inject_incoming(0x052, string.char(0,0,0,0,0,0,0,0))
            windower.packets.inject_incoming(0x052, string.char(0,0,0,0,1,0,0,0))
            coroutine.schedule(function()
                if rune_active then coroutine.schedule(poke_rune, 1.0) end
            end, 4.0)
            poke_target = nil
            return true
        end

        if debugmode then
            windower.add_to_chat(200, ('Genie: Got menu (MenuID=%d) - sending Opt=%d'):format(mid, t.opt))
        end
        local confirm = packets.new('outgoing', 0x05B)
        confirm['Target']            = t.npc_id
        confirm['Target Index']      = t.index
        confirm['Zone']              = zone
        confirm['Menu ID']           = mid
        confirm['Option Index']      = t.opt
        confirm['_unknown1']         = 0
        confirm['Automated Message'] = false
        confirm['_unknown2']         = 0
        packets.inject(confirm)
        windower.packets.inject_incoming(0x052, string.char(0,0,0,0,0,0,0,0))
        windower.packets.inject_incoming(0x052, string.char(0,0,0,0,1,0,0,0))
        local was_solver = t.is_solver
        local was_simultaneous = t.is_simultaneous
        poke_target = nil
        solver_poke_time = 0
        last_poke_was_solver = was_solver and solver_active
        last_poke_was_simultaneous = was_simultaneous and simultaneous_floor
        last_poke_time_for_skip = os.clock()
        if was_solver and solver_active and not objectiveCompleted then
            log_lamp_states(('Perm %d Step %d poked'):format(solver_perm_idx, solver_step))
            coroutine.schedule(solver_activate_next, 2.0)
        elseif was_simultaneous and simultaneous_floor then
            coroutine.schedule(simultaneous_activate_next, 1.0)
        elseif debugmode then
            windower.add_to_chat(200, 'Genie: Lamp activated.')
        end
        return true

    elseif id == 0x0F4 and ws_scan.active then
        local p = packets.parse('incoming', data)
        local name = p['Name']
        local index = p['Index']
        local level = p['Level']
        local x_off = p['X Offset']
        local y_off = p['Y Offset']

        if name and name ~= '' then
            ws_scan.results[#ws_scan.results+1] = {
                index = index, name = name, level = level,
                x_off = x_off, y_off = y_off,
            }

            if ws_scan.mode == 'nm' and not ws_scan.nm_found then
                if NYZUL_NM_SET[name] then
                    ws_scan.nm_found = { index = index, name = name, level = level }
                end
            elseif ws_scan.mode == 'count' then
                if not FILTER_NAMES[name] then
                    ws_scan.mob_count = ws_scan.mob_count + 1
                end
            end
        end

    elseif id == 0x0F5 and ws_scan.active then
        local p = packets.parse('incoming', data)
        local x = p['X']
        local z = p['Z']
        local y = p['Y']
        local index = p['Index']
        if ws_scan.nm_found and ws_scan.nm_found.index == index then
            ws_scan.nm_found.x = x
            ws_scan.nm_found.y = y
            ws_scan.nm_found.z = z
            windower.add_to_chat(200, ('Genie: %s coordinates: (%.1f, %.1f, %.1f)'):format(
                ws_scan.nm_found.name, x, y, z))
        end

    elseif id == 0x0F6 then
        local p = packets.parse('incoming', data)
        if p['Type'] == 2 and ws_scan.active then
            ws_scan.active = false
            windower.add_to_chat(200, ('Genie: Scan complete. %d entities found.'):format(#ws_scan.results))
            if ws_scan.callback then
                ws_scan.callback(ws_scan.results)
                ws_scan.callback = nil
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- Status change: solver combat pause/resume
-------------------------------------------------------------------------------
windower.register_event('status change', function(new, old)
    if solver_active and not solver_paused and new == 1 then
        solver_pause()
    elseif solver_active and solver_paused and new == 0 then
        solver_resume()
    end
end)

-------------------------------------------------------------------------------
-- Zone change
-------------------------------------------------------------------------------
windower.register_event('zone change', function(new_id, old_id)
    currentZone = new_id
    poke_target = nil
    rune_active = false
    rune_mode = 'up'
    clear_check_cache()
end)

windower.register_event('unload', function()
    if genie_state_debug then
        windower.add_to_chat(200, ('Genie UNLOAD: globals at unload: auto_solve=%s warp[nm=%s all=%s family=%s single=%s] runner=%s'):format(
            tostring(auto_solve), tostring(auto_warp_nm), tostring(auto_warp_all),
            tostring(auto_warp_family), tostring(auto_warp_single), tostring(rune_runner_name)))
    end
    genie_settings.auto_solve        = auto_solve
    genie_settings.auto_warp_nm      = auto_warp_nm
    genie_settings.auto_warp_all     = auto_warp_all
    genie_settings.auto_warp_family  = auto_warp_family
    genie_settings.auto_warp_single  = auto_warp_single
    genie_settings.rune_runner       = rune_runner_name or ''
    pcall(function() settings_save() end)
end)

-------------------------------------------------------------------------------
-- IPC: receive certify command from other instances
-------------------------------------------------------------------------------
windower.register_event('ipc message', function(msg)
    local subcmd = msg:match('^genie (%S+)')
    if not subcmd then return end
    if subcmd == 'certify' then
        local zone_id = windower.ffxi.get_info().zone
        local p = windower.ffxi.get_player()
        local me = p and p.name or '?'
        if zone_id ~= 77 then
            windower.add_to_chat(200, ('Genie IPC [%s]: certify ignored - not in Nyzul (zone=%d).'):format(me, zone_id))
            return
        end
        if not autocertify_enabled then
            windower.add_to_chat(167, ('Genie IPC [%s]: certify received but autocertify is OFF. Toggle //genie autocertify.'):format(me))
            return
        end
        if poke_target ~= nil then
            windower.add_to_chat(167, ('Genie IPC [%s]: certify received but a poke is already in progress. Trying anyway in 5s...'):format(me))
            coroutine.schedule(function()
                if poke_target == nil then do_certify() end
            end, 5.0)
            return
        end
        windower.add_to_chat(200, ('Genie IPC [%s]: certify received - poking lamp in 3s...'):format(me))
        coroutine.schedule(do_certify, 3.0)

    elseif subcmd == 'runner_set' then
        local target = msg:match('^genie runner_set (%S+)')
        if target == 'none' then
            rune_runner_name = nil
            genie_settings.rune_runner = ''
            settings_save()
            windower.add_to_chat(200, 'Genie IPC: Rune runner cleared.')
        elseif target then
            rune_runner_name = target
            genie_settings.rune_runner = target
            settings_save()
            local p = windower.ffxi.get_player()
            local me = p and p.name or '?'
            if me:lower() == target:lower() then
                windower.add_to_chat(200, ('Genie IPC: I (%s) am now the rune runner.'):format(me))
            else
                windower.add_to_chat(200, ('Genie IPC: Rune runner set to %s (I am %s).'):format(target, me))
            end
        end

    elseif subcmd == 'runtest' then
        local p = windower.ffxi.get_player()
        local me = p and p.name or '?'
        if is_rune_runner() then
            windower.add_to_chat(200, ('Genie IPC: [%s] I AM the designated runner.'):format(me))
        else
            windower.add_to_chat(200, ('Genie IPC: [%s] I am NOT the runner (assigned: %s).'):format(
                me, rune_runner_name or 'none'))
        end

    elseif subcmd == 'mode_set' then
        local new_mode = msg:match('^genie mode_set (%S+)')
        if new_mode == 'up' or new_mode == 'exit' then
            rune_mode = new_mode
            local p = windower.ffxi.get_player()
            local me = p and p.name or '?'
            local tag = is_rune_runner() and ' (I am the runner)' or ''
            windower.add_to_chat(200, ('Genie IPC [%s]: Rune mode set to %s%s.'):format(
                me, rune_mode:upper(), tag))
        end
    end
end)

-------------------------------------------------------------------------------
-- Incoming text: detect lamp floor, objective complete, certification
-------------------------------------------------------------------------------
local function handle_check_response(original)
    if not check_current then return end
    local stripped = string.strip_format(original)
    if string.match(stripped, '[Ii]mpossible to gauge') then
        check_cache[check_current.index] = 'itg'
        local mob = windower.ffxi.get_mob_by_index(check_current.index)
        if mob and mob.name then
            if specified_enemy_floor
               and not name_filter_match(mob.name)
               and not specified_enemy_excluded(mob.name) then
                if not specified_enemy_list[mob.index] then
                    specified_enemy_list[mob.index] = {
                        index = mob.index, id = mob.id, name = mob.name,
                        x = mob.x, y = mob.y, z = mob.z,
                    }
                    windower.add_to_chat(200, ('Genie: >>> ITG candidate: %s (index=%d) <<<'):format(mob.name, mob.index))
                end
            end
            if specified_enemies_floor and NAME_TO_FAMILY[mob.name] then
                local family_id = NAME_TO_FAMILY[mob.name]
                if not specified_enemies_family then
                    specified_enemies_family = family_id
                    specified_enemies_name = mob.name
                    windower.add_to_chat(200, ('Genie: >>> ITG FAMILY: %s (member: %s) <<<'):format(family_id, mob.name))
                    local found = 0
                    for idx, entry in pairs(ws_cache.mobs) do
                        if family_name_match(entry.name, family_id) then
                            specified_enemies_list[idx] = {
                                index = idx, name = entry.name,
                                x = entry.x, y = entry.y, z = entry.z,
                            }
                            found = found + 1
                        end
                    end
                    windower.add_to_chat(200, ('Genie: Found %d %s family members in widescan cache.'):format(found, family_id))
                elseif NAME_TO_FAMILY[mob.name] == specified_enemies_family and not specified_enemies_list[mob.index] then
                    specified_enemies_list[mob.index] = {
                        index = mob.index, id = mob.id, name = mob.name,
                        x = mob.x, y = mob.y, z = mob.z,
                    }
                end
            end
        end
        check_current = nil
    elseif string.match(stripped, 'Incredibly [Tt]ough')
        or string.match(stripped, 'Very [Tt]ough')
        or string.match(stripped, '[Tt]ough')
        or string.match(stripped, 'Even [Mm]atch')
        or string.match(stripped, 'Decent [Cc]hallenge')
        or string.match(stripped, 'Easy [Pp]rey')
        or string.match(stripped, '[Tt]oo weak') then
        check_cache[check_current.index] = 'normal'
        check_current = nil
    end
end

local function handle_nyzul_text(original)
    if currentZone ~= 77 then return end
        local stripped = string.strip_format(original)

        if string.find(stripped, 'objective complete') then
            objectiveCompleted = true
            local clear_floor = tonumber(string.match(stripped, 'Floor (%d+) objective complete'))
            if clear_floor then
                current_floor_number = clear_floor
                if starting_floor == 0 then starting_floor = clear_floor end
            end
            token_credit_floor()
            floors_completed = floors_completed + 1
            if solver_active then
                local perm = solver_perms[solver_perm_idx]
                local order_str = ''
                if perm then
                    local order = {}
                    for i, lamp_pos in ipairs(perm) do
                        local lamp = solver_lamps[lamp_pos]
                        if lamp then order[i] = get_lamp_letter(lamp.index) end
                    end
                    if #order > 0 then order_str = ' (order: ' .. table.concat(order, ' -> ') .. ')' end
                end
                windower.add_to_chat(200, 'Genie SOLVER: Solved!' .. order_str)
                solver_active = false
                solver_paused = false
                solver_wait_time = 0
                solver_poke_time = 0
                poke_target = nil
            end
            if simultaneous_floor then
                simultaneous_floor = false
                simultaneous_lamps = {}
                simultaneous_step = 0
                simultaneous_done_time = 0
            end
            eliminate_leader_floor = false
            eliminate_leader       = nil
            eliminate_all_floor    = false
            specified_enemy_floor  = false
            specified_enemy        = nil
            specified_enemy_list   = {}
            specified_enemies_floor  = false
            specified_enemies_family = nil
            specified_enemies_name   = nil
            specified_enemies_list   = {}
            lampFloorDetected = false
            if is_rune_runner() and not rune_active then
                rune_active = true
                rune_attempts = 0
                windower.add_to_chat(200, ('Genie: Objective complete - clicking Rune (mode=%s)...'):format(rune_mode))
                poke_rune()
            end
        end

        local floor_num = string.match(original, 'Welcome to Floor (%d+)')
        if floor_num then
            current_floor_number = tonumber(floor_num)
            if floor_start_time > 0 and floor_count > 0 then
                floor_times[#floor_times+1] = os.clock() - floor_start_time
            end
            floor_count = floor_count + 1
            floor_start_time = os.clock()
            reset_lamps()
            if starting_floor == 0 then
                starting_floor = current_floor_number
            end
            local rf = token_relative_floor()
            if rf - starting_floor > floors_completed then
                floors_completed = rf - starting_floor
            end
            floor_penalties = 0
            windower.add_to_chat(200, ('Genie: Floor %d entered.'):format(current_floor_number))
            if is_boss_floor() then
                windower.add_to_chat(200, ('Genie: Floor %d is a boss floor - automation disabled.'):format(current_floor_number))
            end
        end

        if is_boss_floor() then
            return
        end

        local obj_text = string.match(original, '^Objective:%s*(.+)$')
        if obj_text and not original:find('^Genie:') then
            local clean = string.strip_format(obj_text):gsub('[\1-\31]', ''):gsub('%s+$', '')
            if clean ~= '' then
                current_objective = clean
            end
        end

        if not original:find('^Genie:') and not archaic_gear_warning then
            local lower = original:lower()
            if lower:find('archaic gear') and (lower:find('avoid') or lower:find('do not')
               or lower:find('not destroy') or lower:find('detect')) then
                local clean = string.strip_format(original)
                clean = clean:gsub('[\1-\31]', '')
                archaic_gear_warning = clean
                windower.add_to_chat(200, 'Genie: Archaic Gear restraint detected.')
            end
        end

        local penalty_min = string.match(original, 'Time limit has been reduced by (%d+) minute')
        if penalty_min and not original:find('^Genie:') then
            local n = tonumber(penalty_min)
            if n and n > 0 then
                time_penalty_minutes = (time_penalty_minutes or 0) + n
                windower.add_to_chat(200, ('Genie: Time penalty applied (-%d min, total: -%d).'):format(n, time_penalty_minutes))
            end
        end

        if string.find(stripped, 'Potential token reward reduced') and not original:find('^Genie:') then
            floor_penalties = floor_penalties + 1
        end

        if string.match(original, 'Objective:') and string.match(original, 'lamps') then
            if auto_solve then
                windower.add_to_chat(200, 'Genie: Lamp floor detected. Auto-solve ON: Solving automatically, please wait warmly...')
            else
                windower.add_to_chat(200, 'Genie: Lamp floor detected. Auto-solve OFF: Run //genie solve to start.')
            end
            lampFloorDetected = true
            needLampScan = true
            scanClock = os.clock()
            if auto_solve and not solver_active then
                coroutine.schedule(function()
                    if not solver_active and not simultaneous_floor and lampFloorDetected then
                        windower.add_to_chat(200, 'Genie: Auto-solving lamp floor...')
                        request_all_lamps()
                        solver_opt = 1
                        coroutine.schedule(function()
                            solver_lamps = {}
                            for _, idx in ipairs(SORTED_LAMP_INDEXES) do
                                local npc = windower.ffxi.get_mob_by_index(idx)
                                if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
                                    if npc.name == 'Runic Lamp' then
                                        solver_lamps[#solver_lamps+1] = {
                                            index = npc.index,
                                            npc_id = npc.id,
                                            x = npc.x, y = npc.y, z = npc.z,
                                        }
                                    end
                                end
                            end
                            if #solver_lamps < 1 then
                                windower.add_to_chat(167, 'Genie: No lamps found for auto-solve.')
                                return
                            end
                            solver_perms = generate_permutations(#solver_lamps)
                            solver_perm_idx = 0
                            solver_step = 0
                            solver_wait_time = 0
                            solver_active = true
                            objectiveCompleted = false
                            windower.add_to_chat(200, ('Genie SOLVER: Found %d lamps. %d permutations to try. Starting...'):format(
                                #solver_lamps, #solver_perms))
                            log_lamp_states('BASELINE - all lamps unlit')
                            solver_start_next_perm()
                        end, 1.5)
                    end
                end, 3.0)
            end
        elseif string.match(original, 'Eliminate all enemies') then
            windower.add_to_chat(200, 'Genie: Kill all enemies floor detected.')
            eliminate_all_floor = true
            coroutine.schedule(function() ws_refresh_cache(true) end, 1.0)
        elseif string.match(original, 'Eliminate enemy leader') then
            windower.add_to_chat(200, 'Genie: NM floor detected - searching for enemy leader...')
            eliminate_leader_floor = true
            eliminate_leader = nil

            local function lock_nm(name, index, id, x, y, z)
                if eliminate_leader then return end
                eliminate_leader = { index = index, id = id, name = name, x = x, y = y, z = z }
                windower.add_to_chat(200, ('Genie: >>> FOUND NM: %s <<<'):format(name))
                if auto_warp_nm and x then
                    windower.add_to_chat(200, 'Genie: Auto-warping to NM...')
                    teleport_to(x, y, z)
                end
            end

            local function try_widescan(callback)
                if eliminate_leader then if callback then callback(true) end return end
                start_widescan('nm_ws', function(results)
                    if eliminate_leader then if callback then callback(true) end return end
                    local candidate = nil
                    for _, r in ipairs(results) do
                        if nm_match(r.name) and not defeated_nm_set[r.index] then
                            candidate = r
                            break
                        end
                    end
                    if not candidate then
                        if callback then callback(false) end
                        return
                    end
                    local req = packets.new('outgoing', 0x016)
                    req['Target Index'] = candidate.index
                    packets.inject(req)
                    coroutine.schedule(function()
                        if eliminate_leader then if callback then callback(true) end return end
                        local mob = windower.ffxi.get_mob_by_index(candidate.index)
                        if mob and mob.x and (mob.x ~= 0 or mob.y ~= 0) then
                            lock_nm(mob.name, candidate.index, mob.id, mob.x, mob.y, mob.z)
                            if callback then callback(true) end
                        else
                            if callback then callback(false) end
                        end
                    end, 0.7)
                end)
            end

            local function poll_widescan_for_nm()
                if eliminate_leader or not eliminate_leader_floor then return end
                try_widescan(function() end)
                if not eliminate_leader and eliminate_leader_floor then
                    coroutine.schedule(poll_widescan_for_nm, 15.0)
                end
            end

            local function attempt_dat_scan(retry_count)
                start_nm_scan(function(found)
                    if found and not eliminate_leader then
                        lock_nm(found.name, found.index, found.id, found.x, found.y, found.z)
                    elseif not eliminate_leader and retry_count < 1 then
                        windower.add_to_chat(200, 'Genie: DAT scan miss, second sweep in 5s...')
                        coroutine.schedule(function() attempt_dat_scan(retry_count + 1) end, 5.0)
                    elseif not eliminate_leader then
                        windower.add_to_chat(200, 'Genie: DAT scan exhausted, switching to periodic widescan polling...')
                        coroutine.schedule(poll_widescan_for_nm, 5.0)
                    end
                end)
            end

            coroutine.schedule(function()
                windower.add_to_chat(200, 'Genie: Trying widescan first...')
                try_widescan(function(ok)
                    if not ok and not eliminate_leader then
                        windower.add_to_chat(200, 'Genie: Widescan miss, falling back to DAT scan...')
                        coroutine.schedule(function() attempt_dat_scan(0) end, 1.0)
                    end
                end)
            end, 3.0)
        elseif string.match(original, 'Eliminate specified enemies') then
            windower.add_to_chat(200, 'Genie: Specified enemies floor detected - scanning for ITG family...')
            specified_enemies_floor = true
            specified_enemies_name = nil
            specified_enemies_list = {}
            coroutine.schedule(ws_preload_for_check, 1.0)
        elseif string.match(original, 'Eliminate specified enemy') then
            windower.add_to_chat(200, 'Genie: Specified enemy floor detected - scanning all mobs...')
            specified_enemy_floor = true
            specified_enemy = nil
            coroutine.schedule(ws_preload_for_check, 1.0)
        elseif string.match(original, '%S+ defeats the (%S[%S ]-)%.') then
            local victim = string.match(original, '%S+ defeats the (%S[%S ]-)%.')
            if victim and NYZUL_NM_SET[victim] then
                local mob_array = windower.ffxi.get_mob_array()
                for _, m in pairs(mob_array) do
                    if m and m.name == victim then
                        defeated_nm_set[m.index] = true
                        windower.add_to_chat(200, ('Genie: %s (index=%d) marked as defeated.'):format(victim, m.index))
                        break
                    end
                end
            end
        elseif string.match(original, 'Transfer complete.') then
            rune_active = false
        elseif string.match(original, 'Rune of Transfer activated.') then
            objectiveCompleted = true
            if solver_active then
                local perm = solver_perms[solver_perm_idx]
                local order_str = ''
                if perm then
                    local order = {}
                    for i, lamp_pos in ipairs(perm) do
                        local lamp = solver_lamps[lamp_pos]
                        if lamp then order[i] = get_lamp_letter(lamp.index) end
                    end
                    if #order > 0 then order_str = ' (order: ' .. table.concat(order, ' -> ') .. ')' end
                end
                windower.add_to_chat(200, 'Genie SOLVER: Solved!' .. order_str)
                solver_active = false
                solver_wait_time = 0
                poke_target = nil
            end
            eliminate_leader = nil
            if simultaneous_floor then
                simultaneous_floor = false
                simultaneous_lamps = {}
                simultaneous_step = 0
                simultaneous_done_time = 0
                windower.add_to_chat(200, 'Genie: Simultaneous lamps activated successfully!')
            end
            if debugmode then
                windower.add_to_chat(200, 'Genie: Floor objective completed!')
            end
        elseif string.match(original, 'certification code has been registered') then
            if certify_state.active then
                windower.add_to_chat(200, 'Genie: Certification confirmed!')
                certify_state.active = false
                certify_state.retry_count = 0
            end
            if solver_active then
                windower.add_to_chat(200, 'Genie SOLVER: Certification floor detected! Cancelling solver.')
                solver_active = false
                solver_paused = false
                poke_target = nil
                windower.send_ipc_message('genie certify')
            end
        elseif string.match(original, 'Event skipped') then
            local now = os.clock()
            local recent_confirm   = last_poke_time_for_skip > 0 and now - last_poke_time_for_skip < 5.0
            local recent_solver_pk = solver_poke_time > 0 and now - solver_poke_time < 5.0
            if recent_confirm or recent_solver_pk then
                if last_poke_was_simultaneous and simultaneous_floor then
                    if debugmode then
                        windower.add_to_chat(167, 'Genie: Event skipped - retrying lamp poke.')
                    end
                    simultaneous_step = math.max(0, simultaneous_step - 1)
                    simultaneous_done_time = 0
                    last_poke_time_for_skip = 0
                    coroutine.schedule(simultaneous_activate_next, 1.0)
                elseif solver_active then
                    if debugmode then
                        windower.add_to_chat(167, 'Genie SOLVER: Event skipped - retrying lamp.')
                    end
                    last_poke_time_for_skip = 0
                    solver_retry_current()
                end
            end
        elseif string.match(original, 'cannot be activated unless all other lamps are activated at the same time') then
            if solver_active and not simultaneous_floor then
                windower.add_to_chat(200, 'Genie SOLVER: Simultaneous lamp floor detected! Switching to rapid poke...')
                solver_active = false
                solver_paused = false
                poke_target = nil
                local already_poked_idx = solver_step_clicks[solver_step]
                simultaneous_floor = true
                simultaneous_lamps = {}
                for _, lamp in ipairs(solver_lamps) do
                    if lamp.index ~= already_poked_idx then
                        simultaneous_lamps[#simultaneous_lamps+1] = {
                            index = lamp.index,
                            npc_id = lamp.npc_id,
                            x = lamp.x, y = lamp.y, z = lamp.z,
                        }
                    end
                end
                simultaneous_step = 0
                if debugmode then
                    windower.add_to_chat(200, ('Genie: %d lamps remaining to poke (skipping already-poked).'):format(#simultaneous_lamps))
                end
                coroutine.schedule(simultaneous_activate_next, 1.0)
            end
        elseif string.match(original, 'Apparently, this lamp must be activated in a specific order') then
            if debugmode then
                windower.add_to_chat(200, 'Genie: Order floor confirmed.')
            end
        end
end

windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, blocked)
    handle_check_response(original)
    handle_nyzul_text(original)
end)

-------------------------------------------------------------------------------
-- Main loop (prerender)
-------------------------------------------------------------------------------
windower.register_event('prerender', function()
    if specified_enemy_floor or specified_enemies_floor then
        process_check_queue()
    end

    if nm_scan.active and nm_scan.last_req_time > 0 and os.clock() - nm_scan.last_req_time > 0.5 then
        nm_scan_next()
    end

    if simultaneous_floor and simultaneous_done_time > 0
       and os.clock() - simultaneous_done_time > 30.0 then
        windower.add_to_chat(167, 'Genie: Simultaneous activation timed out. Cleaning up.')
        simultaneous_floor = false
        simultaneous_lamps = {}
        simultaneous_step = 0
        simultaneous_done_time = 0
        poke_target = nil
    end

    if (eliminate_all_floor or specified_enemy_floor or specified_enemies_floor)
       and ws_cache.last_refresh > 0
       and os.clock() - ws_cache.last_refresh > ws_cache.refresh_interval
       and not ws_scan.active then
        ws_refresh_cache()
    end

    if (eliminate_all_floor or specified_enemy_floor or specified_enemies_floor)
       and ws_cache.last_refresh > 0 then
        ws_throttled_position_refresh()
    end

    if certify_state.active and os.clock() - certify_state.last_poke_time > certify_state.retry_interval then
        if certify_state.retry_count >= certify_state.max_retries then
            windower.add_to_chat(167, ('Genie: Certify failed after %d attempts. Giving up.'):format(certify_state.max_retries))
            certify_state.active = false
            certify_state.retry_count = 0
        elseif poke_target == nil then
            certify_state.retry_count = certify_state.retry_count + 1
            certify_state.last_poke_time = os.clock()
            do_certify(true)
        end
    end

    if solver_active and not solver_paused and not objectiveCompleted and not rune_active
       and solver_poke_time > 0 and solver_wait_time == 0 then
        if poke_target and poke_target.is_solver and os.clock() - solver_poke_time > 5.0 then
            if debugmode then
                windower.add_to_chat(167, 'Genie SOLVER: Lamp poke timed out - retrying...')
            end
            solver_retry_current()
        end
    end

    if solver_active and solver_wait_time > 0 then
        if objectiveCompleted then
            local perm = solver_perms[solver_perm_idx]
            local order = {}
            for i, lamp_pos in ipairs(perm) do
                order[i] = get_lamp_letter(solver_lamps[lamp_pos].index)
            end
            windower.add_to_chat(200, 'Genie SOLVER: Solved! (order: ' .. table.concat(order, ' -> ') .. ')')
            solver_active = false
            solver_wait_time = 0
        elseif os.clock() - solver_wait_time > solver_delay then
            log_lamp_states(('Perm %d FAILED - before reset'):format(solver_perm_idx))
            if debugmode then
                windower.add_to_chat(167, ('Genie SOLVER: Perm %d/%d failed. Trying next...'):format(
                    solver_perm_idx, #solver_perms))
            end
            solver_wait_time = 0
            solver_start_next_perm()
        end
    end

    if os.clock() - clock > 1 then
        if currentZone == 0 then
            currentZone = windower.ffxi.get_info().zone
        end

        if lastZone ~= currentZone then
            if currentZone == 77 then
                if debugmode then
                    windower.add_to_chat(200, 'Genie Debug: Nyzul Isle entered.')
                end
                eventClock = os.clock()
                run_start_time = os.clock()
                floor_count = 0
                floor_times = {}
                floor_start_time = os.clock()
                defeated_nm_set = {}
                current_floor_number = 0
                time_penalty_minutes = 0
                starting_floor   = 0
                floors_completed = 0
                floor_penalties  = 0
                potential_tokens = 0
                token_refresh_armband()
                token_refresh_party_size()
            elseif lastZone == 77 then
                if debugmode then
                    windower.add_to_chat(200, 'Genie Debug: Nyzul Isle exited.')
                end
                reset_lamps()
                hide_display()
                eventClock = nil
            end
            lastZone = currentZone
        end

        if currentZone == 77 or debugmode then
            local player = windower.ffxi.get_player()
            local playerpos = windower.ffxi.get_mob_by_index(player.index)

            if playerpos ~= nil then
                if currentZone == 77 then

                    if needLampScan and os.clock() - scanClock > 5 then
                        if debugmode then
                            windower.add_to_chat(200, 'Genie: Scanning for lamps...')
                        end
                        needLampScan = false
                        update_entities()
                    end
                end

                display()
            end
        end

        clock = os.clock()
    end
end)
