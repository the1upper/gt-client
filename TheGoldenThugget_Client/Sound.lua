-- The Golden Thugget: every sound the addon makes, in one place.
--   ns.Sound.Play("event")  picks a random take for the event (never the same
--   take twice in a row), plays it on WoW's sound-effects channel, and falls
--   back to a built-in WoW sound if the file can't play.
--   /gt sound on|off|test  - one switch for all of it.
local _, ns = ...
if ns.skip then return end
local S = {}
ns.Sound = S

local DIR = ns.MEDIA .. "Sounds\\"

-- event -> { takes (files in Media\Sounds, no .ogg), fallback SOUNDKIT names, gap }
-- gap: minimum seconds between two plays of the event (cards dealt together
-- shouldn't stack into a roar)
S.EVENTS = {
	-- the table
	table_open   = { takes = { "chips_collide1", "chips_collide2", "chips_collide3", "chips_collide4" }, kit = { "IG_PLAYER_INVITE" } },
	player_join  = { takes = { "chip_lay1", "chip_lay2", "chip_lay3" }, kit = { "IG_PLAYER_INVITE" }, gap = 0 },
	invite       = { takes = { "chips_handle1", "chips_handle2" }, kit = { "READY_CHECK" } },
	start_cards  = { takes = { "card_shuffle1", "card_fan1", "card_fan2" } },
	start_dice   = { takes = { "dice_grab1", "dice_grab2" } },
	-- play
	dice_roll    = { takes = { "dice_shake1", "dice_shake2", "dice_shake3" }, gap = 0.3 },
	dice_throw   = { takes = { "dice_throw1", "dice_throw2", "dice_throw3" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.12 },
	coin_flip    = { takes = { "coin_flip1", "coin_flip2", "coin_flip3" }, kit = { "LOOT_WINDOW_COIN_SOUND" }, gap = 0.3 },
	coin_land    = { takes = { "coin_land1", "coin_land2", "coin_land3" }, kit = { "LOOT_WINDOW_COIN_SOUND" }, gap = 0.3 },
	-- Battle Slots: each spin is one recording with the reel pops built in
	slot_reels       = { takes = { "slot_reels" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.3 },
	slot_reels_tease = { takes = { "slot_reels_tease" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.3 },
	slot_reels_quick = { takes = { "slot_reels_quick" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.3 },
	reel_stop    = { takes = { "reel_stop1", "reel_stop2", "reel_stop3" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.08 },
	slot_pair    = { takes = { "slot_pair_hit" }, kit = { "LOOT_WINDOW_COIN_SOUND" }, gap = 0.3 },
	slot_win     = { takes = { "slot_win_full" }, kit = { "LOOT_WINDOW_COIN_SOUND" }, gap = 0.3 },
	double_offer = { takes = { "double_offer" }, kit = { "READY_CHECK" }, gap = 1 },
	slot_lose    = { takes = { "slot_lose" }, kit = { "IG_QUEST_FAILED" }, gap = 0.3 },
	dice_land    = { takes = { "die_throw1", "die_throw2", "die_throw3", "die_throw4" }, kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, gap = 0.12 },
	card_deal    = { takes = { "card_slide1", "card_slide2", "card_slide3", "card_slide4", "card_slide5", "card_slide6", "card_slide7", "card_slide8" }, gap = 0.07 },
	card_flip    = { takes = { "card_place1", "card_place2", "card_place3", "card_place4" }, gap = 0.07 },
	chips        = { takes = { "chips_stack1", "chips_stack2", "chips_stack3", "chips_stack4", "chips_stack5", "chips_stack6" }, gap = 0.08 },
	check        = { takes = { "knock1", "knock2", "knock3" } },
	fold         = { takes = { "card_shove1", "card_shove2", "card_shove3", "card_shove4" } },
	allin        = { takes = { "chips_handle5", "chips_handle1", "chips_handle6" } },
	-- you
	your_turn    = { takes = { "bell1", "bell2", "bell3" }, kit = { "READY_CHECK" }, gap = 0.3 },
	hurry        = { takes = { "tick1", "tick2" }, kit = { "RAID_WARNING" } },
	-- results
	win          = { takes = { "coins_small1", "coins_small2", "coins_small3" }, kit = { "LOOT_WINDOW_COIN_SOUND", "IG_BACKPACK_COIN_OK" } },
	win_big      = { takes = { "coins_big1", "coins_big2" }, kit = { "LOOT_WINDOW_COIN_SOUND", "IG_BACKPACK_COIN_OK" } },
	lose         = { takes = { "lose1", "lose2" }, kit = { "IG_QUEST_FAILED" } },
	push         = { takes = { "chip_lay1", "chip_lay2", "chip_lay3" } },
	jackpot      = { takes = { "jackpot1" }, kit = { "LOOT_WINDOW_COIN_SOUND" } },
	-- the bank (house)
	ledger_in    = { takes = { "chips_collide1", "chips_collide2", "chips_collide3" }, kit = { "LOOT_WINDOW_COIN_SOUND" } },
	ledger_out   = { takes = { "coins_small1", "coins_small2", "coins_small3" }, kit = { "LOOT_WINDOW_COIN_SOUND" } },
	reset        = { takes = { "chips_handle3", "chips_handle4" } },
}

-- which settings switch covers each event (Settings: Table alerts / Game
-- sounds / Win and lose); the rest are game sounds
S.GROUP = {
	table_open = "soundAlerts", invite = "soundAlerts", your_turn = "soundAlerts", hurry = "soundAlerts", double_offer = "soundAlerts",
	win = "soundResults", win_big = "soundResults", lose = "soundResults", push = "soundResults", jackpot = "soundResults",
	slot_pair = "soundResults", slot_win = "soundResults", slot_lose = "soundResults",
	ledger_in = "soundResults", ledger_out = "soundResults", reset = "soundResults",
}

-- a win counts as big from 5 gold up
S.BIG_WIN = 50000

function S.Enabled(event)
	if ns.hush then return false end
	local s = ns.db and ns.db.settings
	if s and s.sound == false then return false end
	if event and s and s[S.GROUP[event] or "soundGame"] == false then return false end
	return true
end

local function channel()
	local s = ns.db and ns.db.settings
	return s and s.soundChannel == "Master" and "Master" or "SFX"
end

local last, lastTake = {}, {}

local function playKit(names)
	if not (PlaySound and SOUNDKIT and names) then return false end
	for _, n in ipairs(names) do
		if SOUNDKIT[n] then return (pcall(PlaySound, SOUNDKIT[n], channel())) end
	end
	return false
end

-- play one take of an event now (force: ignore the gap and the switch)
function S.PlayNow(event, force)
	local e = S.EVENTS[event]
	if not e or (not force and not S.Enabled(event)) then return false end
	local now = GetTime()
	if not force and last[event] and now - last[event] < (e.gap or 0.05) then return false end
	last[event] = now
	local takes = e.takes
	if takes and #takes > 0 and PlaySoundFile then
		local i = math.random(#takes)
		if #takes > 1 and i == lastTake[event] then i = i % #takes + 1 end -- never the same take twice running
		lastTake[event] = i
		local ok, willPlay = pcall(PlaySoundFile, DIR .. takes[i] .. ".ogg", channel())
		if ok and willPlay then return true end
	end
	return playKit(e.kit)
end

-- play an event, optionally after a delay (seconds) and/or several times
-- (times, spacing) - e.g. three cards for the flop
function S.Play(event, delay, times, spacing)
	if not S.Enabled(event) then return end
	times = times or 1
	for k = 1, times do
		local at = (delay or 0) + (k - 1) * (spacing or 0.12)
		if at <= 0 then S.PlayNow(event) else C_Timer.After(at, function() S.PlayNow(event) end) end
	end
end

-- the result of a hand or table for you (delta in copper; nil = watching)
function S.Result(delta)
	if delta == nil then return end
	if delta > 0 then S.Play(delta >= S.BIG_WIN and "win_big" or "win")
	elseif delta < 0 then S.Play("lose")
	else S.Play("push") end
end

-- the start of a table: shuffle for cards, rattling dice otherwise
function S.TableStart(gtype)
	local def = gtype and ns.Games.types[gtype]
	S.Play(def and def.kind == "cards" and def.ui ~= "hand" and "start_cards" or "start_dice")
end

-- /gt sound test: every event once, a beat apart
S.ORDER = { "table_open", "player_join", "invite", "start_cards", "start_dice", "dice_roll", "dice_land", "dice_throw", "coin_flip", "coin_land", "slot_reels", "slot_reels_tease", "slot_reels_quick", "reel_stop", "slot_pair", "slot_win", "slot_lose", "double_offer", "card_deal", "card_flip",
	"chips", "check", "fold", "allin", "your_turn", "hurry", "win", "win_big", "lose", "push", "jackpot", "ledger_in", "ledger_out", "reset" }
function S.Test()
	ns.Print("Playing every sound, one every 1.5 seconds:")
	for k, ev in ipairs(S.ORDER) do
		C_Timer.After((k - 1) * 1.5, function()
			ns.Print("  " .. ev:gsub("_", " "))
			S.PlayNow(ev, true)
		end)
	end
end

function S.Slash(arg)
	arg = (arg or ""):lower()
	local s = ns.db.settings
	if arg == "on" then s.sound = true
	elseif arg == "off" then s.sound = false
	elseif arg == "test" then return S.Test()
	else s.sound = (s.sound == false) end
	ns.Print("Sounds " .. (s.sound == false and "|cffff6161off|r" or "|cff59d959on|r") .. ". (/gt sound test plays them all)")
	if ns.SettingsUI then ns.SettingsUI:Refresh() end
end
