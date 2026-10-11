# Gamepass Shop (Roblox)

A copy of the rainbow pixel-style gamepass shop from the Framewisp video,
built entirely in Luau. No plugin and no Figma needed.

It has a VIP banner, three gamepass cards (Magnet, x2 Money, x2 Gems), a
close button, and a small SHOP button on the left that opens it.

## Effects

| Tag in the video | What it does here |
| --- | --- |
| `_spin` | Light rays slowly rotate behind the VIP crown and each card icon |
| `_gleam` | A white shine sweeps across VIP, MAGNET, x2 MONEY and x2 GEMS |
| `_jelly` | The S H O P letters wobble |
| `_smooth` | Cards and buttons grow on hover and squish when clicked |
| `_lean` | Card icons tilt while you hover them |
| `_turn` | The red X spins while you hover it |
| `_fall` | The VIP squares and the little card icons keep falling |

## Install with one file (easiest)

1. Download `GamepassShop.rbxmx` from this repo to your computer.
2. In Roblox Studio, right-click **ServerScriptService** in the Explorer and
   pick **Insert from File...**, then choose `GamepassShop.rbxmx`.
   Dragging the file into the Studio window also works.
3. Press Play and click the rainbow SHOP button on the left.
4. Click **File > Publish to Roblox** to save it to your game.

The settings live in the `ShopConfig` inside the `GamepassShop` script.
When the game runs, it moves itself into ReplicatedStorage and the shop UI
moves into StarterPlayerScripts. Use either this method or the copy and
paste method below, not both.

To rebuild the file after changing the scripts, run
`rojo build install.project.json -o GamepassShop.rbxmx`.

## Install by copy and paste

Create these three scripts in Roblox Studio and paste in the matching file.
The names must match exactly.

| Create this | Inside | Paste this file |
| --- | --- | --- |
| ModuleScript named `ShopConfig` | ReplicatedStorage | `src/shared/ShopConfig.luau` |
| Script named `ShopServer` | ServerScriptService | `src/server/ShopServer.server.luau` |
| LocalScript named `ShopClient` | StarterPlayer > StarterPlayerScripts | `src/client/ShopClient.client.luau` |

Press Play and click the rainbow SHOP button on the left side of the screen.

## Install with Rojo

```
rojo serve
```

Then connect from the Rojo plugin in Studio.

## Make the buttons sell real gamepasses

1. Create each gamepass on the Creator Dashboard for your experience.
2. Copy each gamepass ID into `GamepassId` in `ShopConfig`.
3. The shop loads the real Robux price automatically once the ID is set.

While an ID is still `0`, clicking that pass only prints a warning in Output.

## Use the perks in your game

The server marks owners with player attributes. Your own game code reads them:

```lua
local money = 10 * (player:GetAttribute("MoneyMultiplier") or 1)
local gems = 1 * (player:GetAttribute("GemsMultiplier") or 1)
local magnetRadius = 20 + (player:GetAttribute("MagnetRadiusBonus") or 0)
local isVip = player:GetAttribute("VIP") == true
```

Each pass also sets `Owns_<Key>`, for example `Owns_DoubleMoney`.

## Open the shop from another script

```lua
player.PlayerGui.GamepassShop:SetAttribute("Open", true)
```

Set `OpenOnJoin = true` in `ShopConfig` to pop it open when players join.

## Differences from the video

- **Icons are emoji.** The crown, magnet, money, gem and cart in the video are
  pixel-art images. Upload your own and paste `rbxassetid://...` into each
  `Icon` in `ShopConfig` to match them exactly.
- **The font is Roblox's built-in Arcade pixel font**, which is close to the
  video's font but not identical.
- **Hover and click sounds are off.** Paste sound IDs into `HoverSound` and
  `ClickSound` in `ShopConfig` to turn them on.
- The "+500 IDK" and "+2x IDK" text is copied from the video as is. Change
  `Line1` and `Line2` in `ShopConfig` to your real currency name.

# Loading screen

`src/loading/LoadingScreen.client.luau` is a loading screen for Grow a Phone,
drawn to look hand-made. Outlines are wobbly marker lines that jitter like
hand-drawn animation, the night sky is coloured in with crayon strokes, the
text is handwritten and tips sit on a sticky note.

A phone grows out of the dirt while the battery gets coloured in with a
marker. At 100% the phone lights up and a PLAY button pops in. Pressing PLAY
zooms into the phone's screen and into the game.

The bar follows real loading: the game itself, then the images, sounds and
meshes in ReplicatedStorage and StarterGui, then the player's character. It
stays up for at least 4 seconds, and a skip link appears after 8 seconds.

## Install

1. Delete or disable your old loading screen so the two don't overlap.
2. In Roblox Studio, right-click **ReplicatedFirst** in the Explorer, pick
   **Insert from File...** and choose `LoadingScreen.rbxmx`.
   Or create a LocalScript in ReplicatedFirst and paste in the file's code.
   It must be in ReplicatedFirst, or it shows up too late.
3. Press Play to see it, then click **File > Publish to Roblox**.

## Change it

Everything you might change is in the `CONFIG` table at the top of the
script: the title, the status messages, the tips, how long it stays up,
whether it waits for PLAY, and optional music and sound IDs. Colours are in
the `COLORS` table right below it.

To rebuild the file after editing the script, run
`rojo build loading.project.json -o LoadingScreen.rbxmx`.

# Phone towers

`PhoneTowers.rbxmx` rebuilds the Pearl Phones and Starsung Phones
skyscrapers so they look like real office towers:

- Glass curtain walls with metal window frames and floor bands, and lit
  offices behind the glass (desks, blinds and ceiling lights). The top
  floors glow purple at night.
- A stone base with sloped sides, an entrance canopy, a backlit sign and a
  revolving door that slowly turns. You can walk through it into the lobby.
- A plant floor with louvres and a glass terrace railing at the setback, and
  thin LED lines on the corners in the brand colours.
- A louvred crown with the brand name on it, roof machinery, and a lattice
  antenna with microwave dishes and red aircraft lights.
- Paving, steps, trees, street lamps and a monument sign around the base.
- Real lights: street lamps, uplights on the stone, floodlights on the tower
  and lights in the lobby and under the canopy.

Each tower is about 600 parts.

## Install

1. In Roblox Studio, right-click **ServerStorage** in the Explorer, pick
   **Insert from File...** and choose `PhoneTowers.rbxmx`.
2. Click your old Pearl Phones building in the 3D view so it is selected.
3. Open **View > Command Bar**, paste this line and press Enter:

   ```lua
   require(game.ServerStorage.PhoneTowers).ReplaceSelected()
   ```

   The new tower appears in the same spot and at the same height, facing
   the same way as the old sign. The old building moves to
   **ServerStorage > OldTowers**, so nothing is lost.
4. Do the same for the Starsung Phones building.

The first time, it also adds a script called **TowerLights** to
ServerScriptService. It switches the office lights on at dusk and off at
dawn, turns a few offices on and off during the night, blinks the red
aircraft lights, and only runs the street lamps and floodlights at night.

The revolving door is turned by a motor (a HingeConstraint), so it only
moves while the game is running. Press Play to see it turn.

If it can't tell which tower you selected, give it the name:
`require(game.ServerStorage.PhoneTowers).ReplaceSelected("Pearl Phones")`.
If it faces the wrong way, add how many degrees to turn it:
`require(game.ServerStorage.PhoneTowers).ReplaceSelected("Pearl Phones", 180)`.

The towers look best with **Lighting > Technology** set to **Future**, and a
**Bloom** effect in Lighting so the neon glows.

## Update

Already built your towers with an older `PhoneTowers.rbxmx`? Delete
**PhoneTowers** from ServerStorage, insert the new file the same way, then
run this in the Command Bar:

```lua
require(game.ServerStorage.PhoneTowers).Rebuild()
```

It rebuilds every tower in the same spot and at the same size, puts the old
ones in **ServerStorage > OldTowers**, and updates TowerLights.

## Change it

Open **PhoneTowers > TowerConfig**. Each tower has its sign text, logo
(`pearl`, `star`, `ring`, `none` or an image ID), window tint, LED colours,
the purple of the top-floor offices, how many floors it has above and below
the setback, and whether to build the plaza. `Seed` changes which offices
have their lights on. Run `require(game.ServerStorage.PhoneTowers).Rebuild()`
after a change.

To build fresh towers without replacing anything, use
`require(game.ServerStorage.PhoneTowers).Build("Pearl Phones")` or
`.BuildAll()`.

To rebuild the file after editing the scripts, run
`rojo build towers.project.json -o PhoneTowers.rbxmx`.

# BUY and SELL stalls

`PhoneStalls.rbxmx` gives the BUY and SELL stalls a new, hand-made look.
They keep the neon and the cyan and red colours, but are built like a real
market stall someone put together by hand. Every board sits a fraction of a
degree off true and has its own shade of wood.

- A plank deck, timber posts with corner braces, a plank back wall, and a
  roof of boards on rafters.
- A counter of vertical boards held by battens and a cross brace, with a
  butcher-block top and a lit icon panel in a wooden frame.
- A big neon sign hung slightly crooked on chains from a timber beam, a
  scrolling LED ticker, warm string lights, a little OPEN sign, and neon
  lines on the posts, roof and base.
- Hand-lettered signs: a chalk menu above the shopkeeper, painted signs on
  both sides, a chalkboard A-frame out front and a cardboard sign on the
  counter.
- Bulbs hanging on cords under little shades, and paper lanterns at the
  front corners.
- Rough shelves on brackets with phone boxes and price tags (and stacks of
  cash on the SELL stall), and a wooden crate of phones on the counter.
- On the counter, BUY gets a phone on a wooden turntable, phones on stands,
  a paper bag, a card reader and a service bell. SELL gets a cash register,
  cash and a phone being checked on a glowing tray.
- A woven rug, terracotta pots with flowers, and a glowing floor circle
  that pulses (and lights up while you stand on it), with a spinning icon
  and sparkles above it.
- Real lights from the hanging bulbs, lanterns, sign and under the deck.
- The shopkeepers stand idle and wave when someone walks up.

Each stall is about 300 parts.

Your shopkeepers and your buy/sell scripts are not touched. The old stall's
parts are made invisible but keep working: players can still step on, touch
or use its floor circle and prompts. The new floor circle goes on top of the
old one, and the new floor goes right under the shopkeeper's feet.

## Install

1. In Roblox Studio, right-click **ServerStorage** in the Explorer, pick
   **Insert from File...** and choose `PhoneStalls.rbxmx`.
2. Click your old BUY stall in the 3D view so it is selected.
3. Open **View > Command Bar**, paste this line and press Enter:

   ```lua
   require(game.ServerStorage.PhoneStalls).ReplaceSelected()
   ```

4. Do the same for the SELL stall.

It works out which stall is which from the old sign, and which way the
stall faces from the way the shopkeeper looks. If it can't tell, give it
the name: `ReplaceSelected("Sell Stall")`. To set the width yourself, add
it in studs: `ReplaceSelected("Sell Stall", 16)`.

The first time, it also adds a LocalScript called **StallFX** to
StarterPlayerScripts. It spins the floating icons and the turntable,
scrolls the ticker, makes the floor glow pulse and the neon signs flicker,
and plays the shopkeepers' idle and wave animations. These only move while
the game is running.

The shopkeepers keep their own look. If you'd like them to wear your
Roblox avatar, run `require(game.ServerStorage.PhoneStalls).DressShopkeepers()`
(or put someone's UserId in the brackets). Only the clothes, hair and hats,
face and skin colour are copied. The shopkeeper keeps its own body,
position and scripts, and its own outfit is saved in
**ServerStorage > PhoneStallsLooks**.

To take the avatar off again and put their own look back, run
`require(game.ServerStorage.PhoneStalls).UndressShopkeepers()`.
`Rebuild()` does the same while `Shopkeeper` is `false` in StallConfig.

To put an old stall back, select it (or its new look) and run
`require(game.ServerStorage.PhoneStalls).Restore()`.

## Change it

Open **PhoneStalls > StallConfig**. Each stall has its sign text, its neon
colour, the icon (`bag`, `cash`, `phone`, `none` or an image ID), the menu
board, ticker, painted sign, chalkboard and cardboard sign words, whether
to show the OPEN sign,
plants and string lights, and whether the shopkeeper wears an avatar
(`false` keeps their own look, `"me"` uses yours, or a UserId). After a
change, or after putting in a newer `PhoneStalls.rbxmx`, run
`require(game.ServerStorage.PhoneStalls).Rebuild()`.

To rebuild the file after editing the scripts, run
`rojo build stalls.project.json -o PhoneStalls.rbxmx`.
