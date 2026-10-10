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

`src/loading/LoadingScreen.client.luau` is a loading screen for Grow a Phone.
A phone grows out of a dirt plot under a neon night city while a battery bar
charges. At 100% the phone lights up and a PLAY button pops in. Pressing PLAY
zooms into the phone's screen and into the game.

The bar follows real loading: the game itself, then the images, sounds and
meshes in ReplicatedStorage and StarterGui, then the player's character. It
stays up for at least 4 seconds, and a SKIP button appears after 8 seconds.

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
