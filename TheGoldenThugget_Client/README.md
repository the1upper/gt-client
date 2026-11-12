# The Golden Thugget (WoW Forever)

A casino run by one house: the bank. Players join from anywhere in the world, the house keeps the only ledger, losers send the house their gold, and the house pays out winners. Everyone can see the ledger and a lifetime leaderboard.

## Install
Unzip into `World of Warcraft/_forever_/Interface/AddOns/`. Both addons can sit in the same AddOns folder:

| Addon | Folder | Who enables it |
|---|---|---|
| **Golden Thugget Client** | `TheGoldenThugget_Client` | players |
| **Golden Thugget Host** | `TheGoldenThugget_Host` | the house only (it includes everything the Client has) |

Enable **one** per character. At character select, click **AddOns**, pick the character in the dropdown at the top, then tick Client *or* Host. If both are ticked, the Host takes over and the Client turns itself off.

The TOC Interface is **16001**. After a patch, run `/dump select(4, GetBuildInfo())` and update both TOC files if the number changed.

## The house
The default house is **Toilet Bowl**. Players don't need to set anything up; the addon only trusts tables and ledgers from that character. To use another: `/gt host First Last`.

## Connecting a player
1. Install **Golden Thugget Client** and log in on the same ruleset as the house. Forever rulesets can't talk to each other.
2. Be reachable on the route the house uses:
   - **Guild:** be in the house's guild.
   - **Party/Raid:** group with the house, anywhere in the world.
   - **Channel:** nothing to do. The addon quietly joins a hidden `GoldenThugget` channel. The house uses it to see who's around, then whispers each player the invite. (Forever drops addon messages sent *to* a chat channel, so all traffic goes by whisper.)
   - **Whisper:** the house types your full name (`First Last`) in the Invite box.
3. Open `/gt` and click **Join** when a table appears.

## Games
Wagers, antes and bets can be any mix of gold, silver and copper: `5g`, `50s`, `1g 20s`, `75c`. A plain number means gold.

**Dice** (the dice table window opens by itself)
- **Death Roll** (2 players): take turns clicking **Roll**. Each roll is 1 to the previous roll; whoever rolls 1 pays the wager. A turn rolls itself after 20 seconds.
- **High Roll** (2-12): everyone clicks **Roll**; the highest roller collects the wager from each player.
- In High Roll and High-Low, everyone rolls at the same time. Your number lands a moment after you click, and the others fill in as each player clicks. The result (and any tie-break rolls) shows once everyone has rolled. The numbers are fixed by the sealed rolls before anyone clicks, so the order people click in changes nothing.
- **High-Low** (2-12): everyone rolls from 1 up to the bet, counted in its smallest coin, and the lowest roller pays the highest roller the difference. A 75s bet rolls 1-75: rolls of 55 and 25 mean 30s. A 1g 25s bet rolls 1-125 (silver); a 5g bet rolls 1-5 (gold).
- If you don't click within 40 seconds, it rolls for you.

**Thugget Dice** (2-8 players, everyone plays at once)
- Everyone antes. You get 5 dice and up to 3 rolls. Click dice to **hold** them between rolls, then **Roll** again or **Stand**. The house sets the time limit (60s by default); when it runs out, you stand with what you have.
- Your dice stay private until the showdown. Then everyone's dice flip over, and the best hand takes the pot. Ties split it. If nobody makes anything, everyone gets their ante back.
- Hands are ranked by how hard they are to complete in 3 rolls (exact odds with best play):
  **Five of a Kind** (4.6%) > **Straight** (26.1%) > **Four of a Kind** (29.1%) > **Full House** (36.3%) > **Small Straight** (61.5%) > **Three of a Kind** (74.3%) > **Pair** (99.9%) > nothing (scores 0).
- Ties within a hand go to the higher dice: pair of 4s beats pair of 2s, 6-high straight beats 5-high, and so on. Then the remaining dice decide.

**Cards** (the card table window opens by itself)
- **Guts** (2-8): 3-card poker. Everyone antes, then secretly picks **In** or **Out**. Staying in costs the stay-in bet on top of your ante (the same as the ante unless the house sets it). Going out costs only your ante.
  - Only one player in: they take the pot. Several in: the best hand takes the whole pot. Everyone out: the cards are dealt again with the antes still in the pot (no new ante). After 5 redeals in a row with nobody in, the antes come back.
  - The **IN** button shows what staying costs, e.g. "IN +25s".
  - Hands, best first: Straight Flush > Three of a Kind > Straight > Flush > Pair > High Card. Equal hands go to the next card, then the last card, so A-K-5 beats A-9-3. Only the same three ranks split the pot. The showdown lists every hand that stayed in.
- **Acey-Deucey** (2-8): everyone antes into the pot, then each player gets one turn. On your turn you see two cards and bet (up to the max bet or the pot) that the next card lands strictly between them.
  - In between: you win your bet from the pot.
  - Outside: you pay your bet into the pot.
  - Hitting the post (matching either card): you pay double.
  - Aces are high. A pair or two adjacent cards means no bet that turn.
  - When everyone has had a turn (or someone empties the pot), the table closes and whatever is left in the pot is split evenly among the players.
- **Texas Hold'em** (2-6): no-limit cash game. Everyone buys in for the same amount and starts with **50 big blinds** (big blind = buy-in / 50, small blind half that, so the buy-in must be a whole number of silver). The house sets how many hands the table plays; it also closes early if one player has all the chips.
  - Seats and the first dealer button are drawn from the sealed rolls; the button moves one seat each hand (past anyone who's busted). Busted players sit out until the table closes; there are no rebuys, and seats are fixed (no joining or leaving mid-table).
  - Normal no-limit rules: minimum bet 1 BB, a raise at least the size of the last bet or raise, an all-in for less doesn't reopen the raising, proper side pots. Heads-up, the button posts the small blind and acts first before the flop.
  - When nobody can bet any more (all-in), every live hand flips face up and the board runs out. At a showdown the last player to bet or raise shows first; losing hands are mucked. If everyone folds to you, you can click **Show cards**.
  - **15 seconds** per decision unless the house set another turn time (5-120 s), with a chime and a pulsing gold glow round the table when it's your turn; the glow turns red with a warning sound at 5 seconds. Time out and you check if you can, otherwise fold. Two timeouts in a row and you're **sitting out** (you check/fold automatically but still post blinds) until you click **I'm back**. **Sit out** does the same on purpose; Leave also just sits you out.
  - **Bet sizing:** 1/2 Pot, Pot and All-in buttons, a slider (mouse wheel moves it a big blind at a time), **+1 gold / silver / copper** buttons (right-click takes one off, shift-click for 10), or type an amount. **Pre-actions** when it isn't your turn: Check/Fold, Check, Call any.
  - Your hand's name shows under your cards ("Two Pair, Kings and Sevens"); at a showdown the five winning cards glow. **Last hand** shows who showed what and how every pot, side pots included, was split. Stacks show in big blinds and gold, e.g. "34 BB (1,700g)".
  - At close, each player's **stack minus the buy-in** goes on the ledger (the nets always add up to zero). The ledger is updated after every finished hand, so if the house disconnects or reloads mid-hand, that hand is void: everyone keeps their chips from before it and the table ends.
  - Your client re-checks every pot split and showdown, and audits every card it saw against the shuffled decks when the table closes.
- Card tables deal **one hand and close** by default. The house can set **Hands** to deal more, or 0 to keep dealing until it clicks **End table**. On longer tables, missing two turns in a row stands you up, and the worst case shown when you join is per hand.
- **Leave** closes the table window. Leaving mid-hand counts as Out in Guts, a pass in Acey-Deucey, and standing where you are in Thugget Dice.

## Players: `/gt`
- **Tables tab:** a list of tables. The top card is your table (or the newest open one); below it, every other table from this session, newest first. Each is labeled and colored: **Open** (green), **In progress** (gold), **Closed** (grey), **Cancelled** (red).
  - **Open:** **Join** and **Watch**.
  - **In progress:** **Watch**.
  - **Your table:** **Show table** and **Leave** (or **Stop watching**).
  - **Closed:** the result, and **Review** to reopen the table window as it ended. Tables you played or watched this session open straight away. Anything else is fetched from the house (it shows *Loading...* for a second or two), so the house needs to be online.
  - Opening `/gt` also asks the house for its recent tables, so the list isn't empty after a `/reload` or a fresh login.
- **Activity tab:** the running log of everything that happened (Quiet chat still sends it here).
- **Ledger tab:** your balance, everyone's balances, your history. **Pay the house** fills in a mail at any mailbox, tagged with your name so paying from an alt still credits you.
- **Leaderboard tab:** lifetime standings (game results only; payments don't count).
- **Joining:** each open table shows its **max loss** (for card tables dealing several hands, per hand). Join seats you straight away. If the button says *update needed* or *over credit limit*, you can't join until you update the addon or pay down what you owe.
- **New-table pop-up:** when the house opens a table and your /gt window is closed, a small card with a Join button appears at the top of the screen for 30 seconds. `/gt alerts` turns it off or on.
- **Results:** every game ends with the headline, then one line per player saying who won or lost what, then what it means for you. Your history on the Ledger tab reads the same way: "Guts, 25s: you won 75s".
- **Your turn:** whenever a table is waiting on you (your roll, In/Out at Guts, your Acey-Deucey bet, your Thugget Dice rolls, your Hold'em decision) the table window gets a pulsing red outline, faster and brighter in the last 5 seconds. If the table window is closed, a red **Your turn** card appears at the top of the screen with a **Show table** button, and the Tables tab says *Your turn!*.
- **Result pop-up:** when a hand or table ends, a card rises over the table: **YOU WON +58s** in green (with a coin burst and the loot-coin sound) or **YOU LOST -58s** in red, counting up, with the headline underneath. It fades after a few seconds; click it to dismiss sooner. Guts and Hold'em pop up after each hand, Acey-Deucey after your own turns, and tables of more than one hand finish with your total. Watchers see the headline only. Reviewing an old table doesn't pop up.
- **Closing:** the table window closes itself 5 seconds after the table ends. The Leave button turns into **Close (5)** counting down, so you can close it sooner. While your mouse is over the table window the countdown pauses (the button just says **Close**); move away and it closes 2 seconds later.
- **Money:** amounts show with WoW's gold, silver and copper coin icons, like the money on your bags. `/gt coins` switches to colored letters (1g 50s) and back.
- **Class colors:** player names are shown in their class color once the addon has seen their class: from your guild roster, your party or raid, targeting or mousing over them, or their chat. Classes are remembered between sessions, so someone outside your guild shows in white until you've seen them once.
- **Window positions:** drag any Golden Thugget window and it opens in the same spot next time (per character). `/gt resetpos` puts them all back in the middle.
- **Watching:** every table has a **Watch** button, open or already in progress (tables in progress show as **In progress** with only Watch). You see the table window the players see: rolls as they land, cards as they're shown, results and payouts. You never see anyone's private cards or dice, and watching costs nothing and isn't on the books. **Stop watching** in the table window or on the Tables tab, or click **Join** on an open table you're watching to take a seat. `/gt watch` watches the newest table.
- **Rules:** every table window has a **Rules** button explaining the game you're in.
- **Reminders:** when you owe the house you get one reminder in chat, and opening a mailbox offers to fill in the payment for you.
- **Chat: Quiet / Full** (bottom of the window, or `/gt quiet`): Quiet keeps chat to your turns, results and anything you need to act on. Everything else is still in the windows.
- **Settling up by trade:** open a trade with the house and a Golden Thugget panel appears under the trade window showing what you owe (or what the house owes you). **Pay** puts exactly that gold in your side of the trade; if you don't have it all, **Pay what I have** puts in what you have. When the trade completes the house's ledger records it and your balance updates.
- **Hold'em hand rankings:** hover your hand's name (the line above your seat, with the (?)) for every hand from Royal Flush down to High Card, with yours highlighted.
- `/gt join`, `/gt watch`, `/gt leave`, `/gt table`, `/gt balance`, `/gt ledger`, `/gt top`, `/gt pay`, `/gt quiet`, `/gt alerts`, `/gt coins`, `/gt resetpos`, `/gt version`, `/gt host <First Last>`, `/gt channel <name>`

## The house: `/gth`
- **Table tab:** pick the game, the wager/ante, the extra setting (start number, max roll, stay-in bet, max bet or turn time), **Hands** for card tables, and where to announce. Then **Open table**, optionally **Take a seat**, and **Start**. **End table** closes a card or Thugget Dice table.
- When you sit, you play through the normal player windows and see only your own hand. Decks and dice exist only in memory while a table runs, never on disk.
- **Table tab:** one main button walks you through a table: **Open table**, then **Start (3 seated)** once enough players have joined, then **End table** for card tables, then **Open table** again. **Take a seat**, **Watch** and **Cancel table** appear beside it only when they apply, and **Open again** reopens the last table with the same game, wager, setting, route, invites and hands. The form is locked while a table runs (it sets up the next one), and an empty setting box shows in grey the default it will use.
- **Current table:** a line with where the table is at (pot, whose turn, seconds left), then one cell per player with what they're doing: joined, sealed/rolled, thinking/decided (Guts - never in or out), betting, rolling (2/3), stacks and folded/all-in/away at Hold'em, and each player's result at the end. The player the table is waiting on is lit gold. Before the start, the **x** on a player's cell removes them (`/gth kick <player>`); they can't rejoin that table.
- **Bank tab safety:** **Settled** asks before zeroing a balance. **Pay** and **Next payout** only work with a mailbox open (their tooltips say so, and point to trading instead). Hover the three totals for what each one counts.
- **Player tab:** the house window's **Player** tab swaps to the player window in the same spot (your tables, ledger, leaderboard, and **Review** for past tables). Its gold **House** button swaps back.
- **Trade panel:** when you trade a player who's on the books, a panel under the trade window shows what you owe them (with a **Pay** button that puts the payout in the trade) or what they owe you (they fill it from their side). A trade that moves exactly the balance owed is recorded straight away, no Yes/No; any other amount asks as before (or records automatically with **Auto**). After a trade settles, the player is whispered their new balance.
- **Bank tab:** what you owe players, what they owe you, gold held, every balance with **Pay** (fills a payout mail) and **Settled**, **Next payout**, **Post ledger**, and **Trade/mail: Ask / Auto** for recording gold that changes hands.
- **Credit limit** (Bank tab, or `/gth limit <amount>`, e.g. `50g`; 0 = no limit): a player can't join a table if what they already owe plus that table's worst case would go over it. The house checks this too, not just the player's addon.
- **Version check:** tables tell players which addon version they need. Anyone older is turned away with a whisper telling them to update.
- **Saving the ledger:** WoW only writes addon data to disk when you log out or reload. If the game crashes, anything since the last save is lost. **Save now** on the Table tab (or `/gth save`) reloads your UI to write it; it's disabled while a table is running. The tab shows when the ledger was last saved and turns red after 30 minutes, and you get a chat reminder after games once it's been that long.
- **Payout reminders:** at login you get a summary of who you owe, and opening a mailbox offers to start the next payout mail.
- **Leaderboard tab:** same lifetime standings the players see.
- **Watching as the house:** **Watch** on the Table tab (or Watch in your own /gt list) opens the table window for a table you aren't sitting at.
- **Recent tables:** the house keeps the last 20 finished or cancelled tables in its saved file, so players can review tables they never saw. It keeps only what a watcher would have seen, never anyone's private cards or dice. Sending a table takes a handful of low-priority whispers (one or two for dice, a few more for card tables), and those never hold up a live table.
- **Watchers:** the Table tab shows how many people are watching, and the log says "<name> is watching" when someone starts. Watchers get the same public messages as the players. On guild or group tables that costs nothing extra. On channel or whisper tables each watcher is one more whisper per update, so a crowd of watchers slows a channel table down.
- `/gth open <game> <wager> [setting] [hands=N] [guild|group|channel|whisper] [First Last, ...]`, e.g. `/gth open guts 50s guild`, `/gth open acey 1g 3g hands=3 channel` or `/gth open holdem 50g hands=3 guild` (Hold'em: the wager is the buy-in), `/gth sit`, `/gth stand`, `/gth start`, `/gth cancel`, `/gth ledger`, `/gth top`, `/gth history [player]`, `/gth post`, `/gth in|out <player> <gold>`, `/gth adjust <player> <+/-gold> [note]`, `/gth settle <player>`, `/gth payout [player]`, `/gth auto on|off`, `/gth limit <amount>`, `/gth save`, `/gth resetbook` (wipe every game and payment after a confirmation, e.g. after testing; settings stay and every player is sent the cleared ledger), `/gth resetbook undo` (bring the last wiped ledger back, merged with anything played since)
- Game names for `/gth open`: `deathroll`, `highroll`, `highlow`, `thugget`, `guts`, `acey`, `holdem`.
- **Hold'em on the Table tab:** pick Texas Hold'em, enter the **Buy-in** (the blinds follow from it), **Turn time (s)** (blank = 15, 5-120) and **Hands** (at least 1). By command: `/gth open holdem 50g 30 hands=3 guild` gives 30 seconds per decision. Players need v3.14.0 or newer; older clients don't see Hold'em tables. On Whisper and Channel tables each update is whispered to every player, so the 15-second clock waits for the house's queue to reach them.

## Channel tables
Forever never delivers addon messages sent to a chat channel, so on the channel route the house whispers each player instead, one copy per player, so big channel tables are slower than guild or group tables. Since v3.14.3 the addon paces whispers by size (about 800 bytes a second, ~4-5 typical messages) instead of one message a second: `/gt speedtest` showed Forever's client doesn't throttle at those rates. In testing that made a 5-player whispered Hold'em table about 4x faster. If you ever see players missing updates, run `/gt speedtest <First Last>` between two characters and check the full-size line. Your dice and private cards go only to you, progress updates are combined, and repeat requests are dropped, but in testing a 7-player Thugget Dice table took about 36 seconds from Start to result on the channel, against about 12 in a guild. Use guild or group when you can.

## Fairness
Every table starts the same way: each player seals a random secret, the secrets are combined into one seed, and the seed sets every die and shuffles every deck.
- Private cards and Thugget Dice are encrypted with a key from your own secret, so only you can read them.
- When a table closes, every secret is published. Each player's addon rebuilds the dice and decks, checks everything it was shown, and re-checks every result against the rules.
- If anything doesn't match, the player is warned and the game is marked **disputed** in their history.
