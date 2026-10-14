# EllesmereUI-Actionbar_Spell_Cost_Display
<img width="1315" height="1089" alt="{15974157-23E9-469A-B92C-475531F7953E}" src="https://github.com/user-attachments/assets/aaf86c71-7055-48a1-84e2-5dba5c16ccd4" />
<img width="1309" height="1089" alt="{8BA8D6F6-1D52-41D3-A073-B888B5E148BD}" src="https://github.com/user-attachments/assets/3ff19ae0-0a87-4d7d-a15f-c2ee4554edc6" />

Shows the **mana / rage / energy / focus cost** of the spell on each EllesmereUI action button: a small number in the corner of the button, colored by power type if you want.

Built for **WoW Forever** (Interface 16001). EllesmereUI is required.

---

## Features

- The cost of the spell on every action button, including spells cast from macros.
- **Every bar has its own settings.** Turn it on for some bars and leave it off on others.
- **Text color:** a custom color, or the color of the power type.
- **Background:** none, a custom color, or the color of the power type. Opacity and padding are adjustable.
- **Font:** any font from the EllesmereUI font list (including SharedMedia fonts), with size and outline (Action Bars default, Outline, Thick Outline, or none with a shadow).
- **Position:** 9 anchor points (corners, edges, center) plus X/Y offsets.
- **Short numbers:** shows `1200` as `1.2k` (optional).
- **Apply to all bars:** copy one bar's spell cost settings to every bar, or to bars you pick.
- **Live preview:** hover the *Text Color* or *Cost Background* label to see a sample `65` for each power type, drawn with the current settings of the bar.
- Updates on page changes, stance/form changes (e.g. Cat Form energy), new spell ranks, level ups, talents, macro edits, and conditional macros (`[mod:shift]`, `[harm]` / `[help]`).
- Saved in your EllesmereUI profile, so profile switching and export/import include it.

### Power type colors

| Power type | Color |
|---|---|
| Mana | blue |
| Rage | red |
| Energy | yellow |
| Focus | orange |

---

## Requirements

- **WoW Forever** client (Interface 16001). The `.toc` also lists the retail 12.x interface numbers that EllesmereUI supports.
- **EllesmereUI** with the **EllesmereUI Action Bars** module enabled. Tested with EllesmereUI **v9.4** and **v9.5.4**.

---

## Installation

1. Download the code (green **Code** button → **Download ZIP**), or download a release.
2. Copy the `EllesmereUI_SpellCost` folder into:
   ```
   World of Warcraft\_classic_beta_\Interface\AddOns\
   ```
   The folder name must stay `EllesmereUI_SpellCost`, with the `.toc` file directly inside it:
   ```
   Interface\AddOns\EllesmereUI_SpellCost\EllesmereUI_SpellCost.toc
   Interface\AddOns\EllesmereUI_SpellCost\SpellCost.lua
   Interface\AddOns\EllesmereUI_SpellCost\SpellCost_Options.lua
   ```
3. **Restart the game completely.** `/reload` is not enough for a newly added addon.
4. Make sure **EllesmereUI Spell Cost** is enabled in the AddOns list on the character select screen.

---

## Usage

Open the EllesmereUI options:

**Action Bars → Bar Display → choose a bar → scroll to the bottom → EXTRAS**

Turn on **Show Spell Cost**. The other settings appear under it.

| Setting | What it does |
|---|---|
| Show Spell Cost | Turns the cost text on or off for the selected bar. The sync icon next to it copies all spell cost settings to other bars. |
| Cost Font | Font of the number. *EUI Global Font* follows the EllesmereUI Action Bars font. |
| Cost Text Size | Size of the number. The arrow icon next to it opens **Position** (9 anchor points) and **X / Y Offset**. |
| Text Color | *Custom Color* (color swatch) or *Power Type Color*. Hover the label for samples. |
| Cost Text Outline | Action Bars default, Outline, Thick Outline, or None (shadow). |
| Short Numbers | `1200` → `1.2k`. |
| Cost Background | *None*, *Custom Color*, or *Power Type Color*. The color swatch sets the custom color; its opacity is used in every mode. Hover the label for samples. |
| Background Padding | Space between the number and the edge of its background. |

Defaults: bottom-left corner, size 11, white text, power type colored background at 80% opacity.

---

## How it works

- It is a **separate addon** and does **not modify any EllesmereUI file**, so an EllesmereUI update does not overwrite it.
- At runtime it connects to the EllesmereUI Action Bars module and draws a small label on each button. It does not touch the secure action buttons themselves: the label is a separate frame, created outside combat.
- The cost comes from the game's own spell cost data (`C_Spell.GetSpellPowerCost`). Spells without a cost show nothing.
- The **EXTRAS** section is added to the EllesmereUI options page at runtime. Other EXTRAS addons (for example *EllesmereUI Spell Rank*) share the same section, and each one works without the others.
- If a future EllesmereUI update changes the internal parts this addon relies on, the addon **turns itself off without errors**, and the rest of EllesmereUI keeps working.

---

## Known limitations

- **Stance bar and pet bar** have no spell costs, so the option is not shown for them.
- The default bottom-left position can **overlap EllesmereUI's macro name text** (the bottom of the button) on macros with long names. Turn on *Hide Macro Text* for that bar, or move the cost to another corner.
- Items and other non-spell actions show nothing.

---

## Troubleshooting

- **No EXTRAS section:** check that the addon is enabled and that you restarted the game after installing it.
- **No numbers on the buttons:** *Show Spell Cost* is set per bar. Turn it on for each bar you want.
- **Errors after an EllesmereUI update:** please open an issue with your EllesmereUI version and the error text (BugSack / BugGrabber output helps).

---

## Changelog

### 1.1.1
- Cost updates immediately for conditional macros (modifier keys, target changes).
- Added the 120105 interface number to the `.toc`.

### 1.1.0
- The EXTRAS section is shared with other EllesmereUI extras addons.
