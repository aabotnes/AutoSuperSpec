<p align="center"><img src=".github/logo.png" width="200" alt="Auto Super Spec logo"></p>

# Auto Super Spec

*by [Soeta's]*

Import talent builds from Wowhead, pick the one you're leveling, and Auto Super Spec learns its talents in order every time you ding. It's made for WoW: Forever (interface 16001) and also works on classic-style clients.

## Install

**Easiest:** download `AutoSuperSpec.zip` from the [latest release](https://github.com/aabotnes/AutoSuperSpec/releases/latest) and unzip it into your `Interface\AddOns` folder.

**From the code:** click **Code → Download ZIP**, unzip it, rename the folder `AutoSuperSpec-main` to `AutoSuperSpec`, and move it into `Interface\AddOns`.

Either way you should end up with `Interface\AddOns\AutoSuperSpec\AutoSuperSpec.toc`. The folder must be named exactly `AutoSuperSpec`, or the game won't load it. Restart the game and make sure **Auto Super Spec** is ticked in the AddOns list on the character screen.

## The window (`/ass` or the minimap button)

- **Classes (left).** Your class is selected when the window opens. Click another class to see or import its builds; the number is how many builds you have saved for that class.
- **Import a build (top).** Paste a Wowhead talent calculator link on the first line, type a name on the second, and press **Import**. If the link is for another class, it's saved under that class.
  On Wowhead, open the **Talent Order** section before you copy the link, so the link includes the order you spent points in.
- **Your builds (middle).** Each build shows its points per tree. **Click a build** to open it in the talent calculator. **New build** makes one from scratch.
  - **Activate / Deactivate** sets the build this character levels with. Only one is active at a time, and the active build is marked in green.
  - **Spec now** spends your free points on the build right away. If your current talents don't match the build, it offers to reset them and spec from scratch, when the game allows it. Otherwise reset at your class trainer first.
  - **...** (or right-click) opens **Share in chat**, **Rename** and **Delete**. Shift-click a build to share it.
- **Following (bottom).** Shows progress on the active build and its next talent, with two options:
  - **Learn on level up** learns automatically when you ding.
  - **Ask first** shows a popup with a Learn button instead.

## Talent calculator

Click a build, or **New build** on the list page, to open it in the talent calculator. The calculator opens inside the same window; **< Back** takes you back to your builds.

- **Trees:** shows the real talent trees with icons, ranks and prerequisite arrows. Hover a talent for its description at the current and next rank, what it requires, and the levels you learn it at.
- **Editing:** left-click a talent to add a point, right-click to remove one. The order you add points in is the learning order, shown on the right one row per level. Right-click a row to remove that exact point. The usual talent rules apply: 5 points per row, prerequisites maxed, and your max level's points (51 at level 60). A point can't be removed if a later point depends on it. **Clear** empties one tree.
- **Saving:** rename the build in the name box, then use **Save**, **Save as new** or **Revert**. If you go Back with unsaved changes, it asks first.
- **Using it:** **Activate**, **Spec now** and **Share** work on the saved build. **Share** also works on an unsaved draft.
- **Other classes:** you can see the learning order of another class's builds, but you can only see and edit their talent tree on a character of that class.

## Account-wide builds, per-character activation

- **Saved for your whole account:** builds and the minimap button position. Every character can see, edit and share every build.
- **Saved per character:** which build is active, plus **Learn on level up** and **Ask first**. Each character follows its own build.

## Minimap button

- **Left-click:** open your builds.
- **Right-click:** open the build you follow in the calculator.
- **Drag:** move the button around the minimap.
- **Hover:** see your progress and next talent. A red dot means learning is paused.
- `/ass minimap` hides or shows the button.

## Sharing

- **Shift-click** a build in the list (or shift-click **Share** in the calculator) to put it into the chat message you're typing, just like linking an item. If no chat box is open, it opens one.
- **Share...** (in a build's **...** menu, or the calculator's **Share** button) lets you pick where to post it:
  - Say, Party, Raid, Instance, Guild, Officer
  - a whisper to your target, or to anyone you type in
  - any numbered channel you've joined (General, Trade, ...)

Everyone with the addon sees the build as a clickable, class-colored **[Auto Super Spec: name]** link, and clicking it imports the build. Players without the addon see plain text, which they can paste into the import box once they install it.

## Commands

| Command | What it does |
|---|---|
| `/ass` | open or close the window |
| `/ass view` | open the build you follow in the talent calculator |
| `/ass status` | the build you follow, progress and next talent |
| `/ass list` | the whole order, with learned points in green |
| `/ass learn` | "Spec now" for the active build |
| `/ass on` / `/ass off` | learning on level up on or off |
| `/ass ask` / `/ass auto` | ask before learning, or learn without asking |
| `/ass resume` | try again after learning paused |
| `/ass minimap` | hide or show the minimap button |
| `/ass debug` | shows what the addon sees of your talent tree, ready to copy, for bug reports |

## Good to know

- On Forever, the addon puts the points in the build's order and then applies them in one go, the way the talent window's Apply button does. It won't touch changes you haven't applied in your own talent window yet.
- It waits until you're out of combat. If the game refuses a talent, it pauses and tells you why instead of retrying forever.
- If an import says the trees don't line up with Wowhead, run `/ass debug`, copy the text and send it to the author.
- Wowhead's link format was worked out with help from the open-source TalentSequence addon (MIT).
