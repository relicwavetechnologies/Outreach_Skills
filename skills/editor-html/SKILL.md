---
name: editor-html
description: Use this skill ANY time the user wants to edit, sort, triage, organize, tag, clean up, prioritize, or "make a tool to handle" a list, dataset, set of items, config, or prompts. Triggers include "make me a tool to sort these", "build a kanban for", "I need to triage X", "let me edit this data", "build a quick editor", "make a prompt tuner", "I want to drag these around", "give me a UI to organize". Generates a single-file HTML throwaway editor — kanban / sortable list / inline table / filter+tag / config form / prompt tuner — with always-on export, undo, search, and localStorage auto-save. Default to this when the goal is "I need to interact with data, then get it back out".
---

# editor-html

Generate a custom, single-file HTML throwaway editor for the user's data. Pick the right interaction pattern (kanban / sortable / table / filter+tag / config form / prompt tuner). EVERY editor must include: export button, undo, search/filter (if >10 items), count indicator, localStorage auto-save, keyboard shortcuts with `?` overlay.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for design style preference.
2. Read `../../shared/design-tokens.css` — copy into the page's `<style>` block.
3. Read `## User Preferences` at the bottom. If export format and interaction pattern preference are learned, narrow questions.

## Step 1: Gather What You Need

**Always ask:**
- What data are we editing? (paste it, file path, or describe the shape)
- What operations do you need to do? (sort / move between categories / tag / score / edit fields / arrange / compare)

**If unclear:**
- What format do you want to export back? (JSON / CSV / markdown / plain text)
- Roughly how many items? (changes which interaction pattern fits)

**Never ask:**
- "Do you want export?" — always yes, always.
- "Do you want undo?" — always yes, always.

**How to ask:**

Good: *"Paste me the data (or point me to the file) and tell me what you wanna do with it — move stuff around? tag things? edit fields? I'll build whichever shape of editor fits."*

Bad: *"Provide input dataset and operation_type ∈ {sort, categorize, tag, edit, arrange, compare}."*

## Step 2: Pick The Interaction Pattern

Match data shape + operation to pattern. Don't over-think — pick one and commit.

| Pattern | When to use |
|---|---|
| **Kanban / triage board** | Items need to move between buckets (todo/doing/done, accept/reject, hot/warm/cold). |
| **Sortable list** | Items need ordering (priority, sequence, ranking). |
| **Inline table editor** | Multi-field per row, spreadsheet-like editing, lots of cells to fill. |
| **Filter + tag interface** | Many items, need to search/filter, attach tags or categories. |
| **Config / settings editor** | Single object with named fields, validation matters, form-style. |
| **Prompt tuner** | Iterating on a prompt — text on left, output preview on right, save versions. |

If ambiguous, ask the user briefly which feels right.

## Step 3: Build The HTML Editor

Single self-contained `.html` file. Tokens copied. All state in a single JS object, persisted to `localStorage` under a key like `html-editor-{topic-slug}`.

### Universal requirements (every editor MUST have)

1. **Export button** — top-right, always visible, never hidden behind a menu. One click → downloads the current state as the user's chosen format. Show a toast confirming "Exported acme-triage.json".
2. **Undo** — Ctrl+Z / Cmd+Z. Maintain a snapshot stack (cap at 50 snapshots). After every state-changing action, push a snapshot. Undo pops + restores.
3. **Redo** — Ctrl+Shift+Z / Cmd+Shift+Z. Standard redo stack behavior.
4. **Search/filter** — if dataset has >10 items, a search input filters items in real-time. Fuzzy match across all string fields.
5. **Count indicator** — somewhere in the chrome: "47 of 52 shown" or "Progress: 23/40 triaged".
6. **Auto-save to localStorage** — debounced 400ms after any change. Show subtle "saved" indicator that fades.
7. **Keyboard shortcuts** — pattern-specific. Always include `?` to open a help overlay listing them all.
8. **Reset / clear** — confirm-dialogued button. Wipes localStorage for this editor and reloads.
9. **Import** — paste-or-drop area accepts the same format the export produces. Useful for resuming.

### Pattern-specific specs

**Kanban / triage board:**
- Columns are the categories. Items are cards.
- Drag-and-drop between columns (HTML5 drag API). Card lifts with shadow on grab.
- Keyboard: ←/→ moves the focused card between columns, ↑/↓ within a column. Tab/Shift-Tab navigates cards.
- Each column header shows count.
- Optional: "card detail" side panel on click — show all fields, allow inline edit.

**Sortable list:**
- Vertical list. Drag handle on left of each row.
- Drop zones highlight on hover.
- Keyboard: Space picks up an item, ↑/↓ moves it, Space again drops.
- Numbered ranks update live.

**Inline table editor:**
- Standard table layout. Click cell → edits inline (input pops in place). Esc cancels, Enter commits.
- Tab moves to next cell, Shift-Tab back, Enter moves down.
- Column headers sortable (click to sort asc/desc, Shift-click for multi-column sort).
- Add row button at bottom. Delete row via row-end ✕ button (confirm if row has content).

**Filter + tag interface:**
- Left sidebar: tag list with counts, click to filter. Multi-select.
- Top: search bar.
- Right: filtered item list. Each item has chip-style tag badges, click chip to remove tag, "+ tag" inline-creates.
- Tag autocomplete from existing tags.

**Config / settings editor:**
- Form layout. One field per setting. Right-side help text on focus.
- Validation inline: red border + message on blur if invalid.
- Section dividers for grouped settings.
- Reset-to-default per field (small icon in field corner).
- Export = JSON dump of current values.

**Prompt tuner:**
- Two columns: prompt editor (left, monospace textarea, big), output preview (right).
- "Run" button + Ctrl-Enter shortcut. Output area shows last N runs (collapsible cards), most recent on top.
- Save Version button — names + freezes current prompt as a version. Sidebar lists saved versions, click to restore.
- Variable interpolation: `{{var_name}}` in the prompt opens an inputs panel below the prompt for var values.

### Design rules

- Dark theme default. Use design tokens — never hardcode hex.
- Never seed with placeholder data. If the user gave nothing, show an empty state with a clear "paste your data here" prompt — not Lorem ipsum.
- No stock images or clipart icons. Use SVG icons inline or simple CSS shapes.
- Whole editor fits in viewport on desktop — no scroll if data fits, internal scroll for list areas.
- Mobile: collapse multi-column layouts to single column with section tabs.
- Loading state on Run / Export / Import (subtle spinner on the button itself).
- Toast notifications bottom-right for actions: "Exported", "Imported 23 items", "Undone".

## Step 4: Save and Present

- Filename: `editor-{topic-slug}-{YYYY-MM-DD}.html`.
- Save to working directory. Open in browser.
- 2-line summary: which interaction pattern was picked, how many items loaded, where the file is.
- Mention: "Your data auto-saves to your browser. Hit Export when you want it back out."
- Ask: *"Anything to tweak — different columns, more fields, a different shortcut?"*

## Step 5: Update Preferences

Rewrite preferences ONLY when:
- User picks the same pattern 2+ times for similar data shapes.
- Export format is consistent.
- User adds the same field/column repeatedly across runs.

## Common Mistakes to Avoid

1. **Hiding the Export button** — must be visible without a menu. The user came here to GET DATA OUT eventually; never make them hunt for it.
2. **No undo** — drag-and-drop without undo is a recipe for rage. Ctrl+Z is required, not optional.
3. **No localStorage** — losing 20 minutes of triage because of a browser refresh is unacceptable. Auto-save is non-negotiable.
4. **Wrong pattern for the data** — a sortable list for things that need categorization is wrong. Pick the pattern that matches the operation.
5. **Forgetting keyboard nav** — power users will pick up the same editor weekly. Keyboard shortcuts make it 5x faster.
6. **No import** — exporting matters; being able to re-import the same file to resume matters just as much.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten after every successful run. Max 20 lines.
-->

- Preferred export format: [not yet learned — ask first time]
- Common interaction pattern: [not yet learned]
- Auto-save to localStorage: yes (default, never disable)
- Keyboard help overlay key: `?` (default)
- Toast notifications: yes (default)
- Mobile responsive: yes (default)
- Last updated: [never]
