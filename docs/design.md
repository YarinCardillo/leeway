# Leeway: design

Source: `docs/spec.md`. Reference keys identify the interface patterns behind each choice.

## Principles

1. **Native macOS components only.** Use NSMenu and native submenus, native selection, grouped Forms, LabeledContent, Pickers, Toggles, system colours and materials. No hand-drawn boxes or borders. Submenu indicators use the system chevron. Account selection uses the neutral drawing exception described below. A custom component is allowed only when no native component supplies the required behavior; document that exception here. Controls inherit the system accent, including Multicolour. [A2] [A4]
2. **A compact native menu.** NSStatusItem presents NSMenu. Attributed menu item titles carry account identity, a meter with numbers, and the reset below. Account rows use native menu item cell measurements, attributed content and an appearance-aware neutral selection; standard commands retain AppKit selection. Native submenus host the accessible Swift Charts detail without a popover arrow. Escape and arrow navigation belong to AppKit. [A1] [A2]
3. **Words first, colour second.** Status is always written ("Over target"). Colour repeats it, never carries it alone. [A4] [A6]
4. **Tint is rationed.** Under uses the system accent to signal quota available to use. On target is plain label colour. Over uses systemOrange for amber or systemRed for red. [R9]
5. **Numbers are text, not decoration.** SF Pro with tabular figures. No monospace, no slashed or dotted zeros. [A3]
6. **One shape for every account.** Same row, same chart, same order of facts everywhere. [A5]

## Scope of the references

Mobbin covers iOS and web only, so it holds no macOS menu bar screens (the search "macOS menu bar app dropdown showing usage with a chart" returned nothing). The Mobbin references are used for information patterns (usage meters, reset wording, forecast and limit lines on charts, settings rows), not for macOS chrome. macOS chrome comes from Apple's HIG. Apple's own Battery, Wi-Fi and Focus menus could not be screenshotted in this session (UI scripting of the menu bar is not permitted), so what is said about them below is recalled, marked [unverified], and must be checked side by side in the design review.

### Visual references, 2026-11-03

Source: six Mobbin references inspected locally. Images remain outside the repository; these are information and layout references, with all chrome supplied by macOS.

| Key | Source | Applied choice |
|-|-|-|
| M1 | Mobbin, Apple Health, Blood Pressure weekly range | Large used percentage, forecast-range headline, period underneath, light native grid and trailing vertical axis in account detail |
| M2 | Mobbin, Unify, Usage | Thin per-account usage and forecast meter, used and forecast values trailing, muted reset below |
| M3 | Mobbin, Searchable, Usage | Numbers carry the hierarchy; account context and reset remain secondary |
| M4 | Mobbin, Apple Fitness, Build Your Plan grouped rows | Native grouped Form sections with a common left label and trailing control column |
| M5 | Mobbin, Apple Health, Sleep aligned list | One alignment for every Settings row; folder metadata belongs to its account section |
| M6 | Mobbin, Apple Fitness, Today's Move Goal | A prominent goal value beside its control. A two-handle Target range replaces the earlier ceiling Stepper |

## Menu bar title

Compact is the default: a 16 pt Phosphor bold vector template icon, with no text: trend-down for under, target for on target, trend-up for over. Every glyph remains an untinted template. macOS supplies the foreground, including white against a dark menu bar. Since 2026-11-03 this replaces verdict tinting in compact mode. General offers Menu bar: Compact / Percentages. Percentages mode uses the text treatment below. VoiceOver retains the full account reading in both modes.

| Property | Value | Reference |
|-|-|-|
| Height available | 24 pt | [A1] |
| Content | `name used% → forecast%`, for example `Work 62% → 84%` | spec 6, [R8] |
| Account shown | The first enabled account in the shared Account order, even without a reading. Risk-first ranking: red over, amber over, under, on target; ties by higher forecast | spec 6 |
| Forecast shown | The higher of the two projections | title only; verdict compares both bounds |
| Font | System menu bar font, 13 pt regular, tabular figures | [A3] |
| Name length | Up to 14 characters, then tail truncation with an ellipsis. Account names are free text, so the title never grows unbounded | [A1] (menus can be truncated when space is tight) |
| Colour | Accent for under, label colour for on target, systemOrange for amber over, systemRed for red over. The whole title takes the tint, not a separate badge | [R9] |
| No data yet, or no accounts | Phosphor target template only, untinted | [A1] |

The title width must not jitter on refresh: tabular figures keep `62%` and `71%` the same width. [A3]

## Menu

### Structure, top to bottom

1. One row per enabled account in the shared Account order: risk-first or Manual.
2. Separator.
3. Muted disabled line: `Updated 2 min ago` (relative, localised). Shows the age of the newest successful reading across accounts. [R1] [R2]
4. `Account order` submenu with the two checked choices `Most at risk first` and `Manual`, synchronized with Settings.
5. `Refresh Now` with Command-R.
6. `Settings…` with Command-comma.
7. Separator.
8. `Quit Leeway` with Command-Q.

Labels use title-style capitalisation, verb first, ellipsis only where more input follows, standard shortcuts only. [A2] Items that cannot act stay visible and dimmed (for example Refresh Now while a refresh runs). [A2]

### Dimensions

| Property | Value | Reference |
|-|-|-|
| Menu width | 340 pt minimum; native AppKit sizing accommodates localized facts without truncating the reset | [A2] |
| Row content inset | AppKit-owned account measurements. The hosted detail uses 16 pt leading and 14 pt trailing padding, with no selection-state inset | [A2] |
| Account row height | Native attributed title height, with an inline usage and forecast meter and a muted reset line below | [M2] [M3] |
| Standard item height | AppKit-owned standard menu item height | [A2] |
| Selection highlight | Account rows use semantic non-emphasized selection grey, retaining text and meter colours. Standard commands retain native accent selection | Revision 2026-11-03 |
| Chevron column | 10 pt at the trailing edge of account rows, system chevron, secondary label | [A2] submenu rule |
| Separator | System separator | [A2] |

### Account row

Revision 2026-11-03: every meter uses the same 0-100% domain. Usage fills from zero; the forecast segment is clipped at 100% with no extension. Two 1 pt target ticks, each with a contrasting 3 pt outline and extending above and below the track, are drawn last at the configured low and high. Endpoint ticks stay inside the image. Very narrow policy ranges keep at least 5 pt between tick centres, with their exact bounds retained in text. No target band is drawn. The caption and detail chart retain the full forecast values, including overflow.

The account name and status lead. A thin usage and forecast meter sits beside the emphasized usage/forecast numbers. Reset stays visible in a muted trailing line below, for every reading, including stale ones. [M2] [M3]

```
Work                                          On target   >
[usage and forecast meter]                  62% now, 70-84% at reset, target 75-100%
                                        Resets Tue 5:00 AM
```

| Element | Style | Reference |
|-|-|-|
| Name | Body, 13 pt regular, label colour | [A3] |
| Status word | Callout, 12 pt regular, right aligned. Accent for under, label colour for on target, systemOrange or systemRed for over severity | [A3] [R9] |
| Facts line left | Subheadline, 11 pt regular, label colour: `62% now, 70-84% at reset, target 75-100%` | [R1] [R8] |
| Reset, muted trailing line below the meter | Subheadline, 11 pt, label colour, right aligned, never truncated: `Resets Tue 5:00 AM` | [R1] [R2] |
| Truncation order | The forecast stays complete. Reset follows it when space permits; otherwise reset moves below it | [A2] |

Numbers use tabular figures. Ranges are written `70-84%`, using a hyphen between the bounds. The weekly window is the one shown here. The five-hour window lives in the submenu. [R1] shows the same split: a short session meter and a weekly meter.

Hover starts only when the pointer is inside the row. Click, Return or Right Arrow opens account detail. Arrow keys move through enabled rows and commands. Tab uses the system focus order.

### Chart submenu

Opened by native menu tracking, click, Return or Right Arrow as an NSMenu submenu beside the account row. Escape returns to the parent menu. The chart and facts are the only hosted custom item. There is no account-selection command in the detail. [A5]

Width 340 pt, leading padding 16 pt and trailing padding 14 pt. Content, top to bottom:

1. **Forecast headline**, account name above the forecast range in SF Pro Display Light 34 pt, with an 18 pt regular secondary `%` on the same baseline. The verdict sits opposite in words and its semantic color. Below, a 10 pt secondary caption names the reset or shows the chart inspection readout. Without a forecast, show measured usage and `used so far`; without a reading, show the typed reading state. Figures remain tabular. Chosen 2026-11-03. [A5]
2. **Chart**, native plot with a 170 pt inspection area (below).
3. **Facts**, Subheadline 11 pt, two columns, labels and values in label colour, 16 pt rows:

| Label | Value |
|-|-|
| Weekly used | 62% |
| Five-hour used | 18%, resets 3:20 PM |
| Forecast, week pace | 84% |
| Forecast, last 24 hours | 97% |
| Target | 75-100% |

   Rows with unknown values are omitted, including five-hour usage and recent pace before a qualifying six-hour history. The obsolete Inspect Readings hint and submenu are absent.

   This follows the label-left, value-right rows of [R3] and the "x% used, resets" phrasing of [R1] and [R2].

### Chart

Swift Charts, one line chart, one visual system for every account. [A5]

| Mark | Style | Reference |
|-|-|-|
| X axis | The weekly window from its start exactly to the reset, with zero horizontal scale padding. Y labels occupy space outside the plot. Ticks at each day start, labelled with day initials (S M T W T F S), 10 pt, label colour, so the week reads at a glance | [R5] |
| Y axis | 0 through the maximum of 100, both forecasts and measured values, plus 10 percentage points. Labels remain 0, 50, 100, trailing side, with light native gridlines | [R14] |
| Used curve | Solid, 1.5 pt, label colour, round joins, from week start to now | [R6] this week as a solid dark line |
| Today marker | 6 pt filled circle in label colour at the latest point. Static, no pulse | [R6] [R9] |
| Projections | Two dashed lines (dash 4, gap 3), 1.5 pt, secondary label, from now to the reset. They never fall below the current used value | spec 4, [R6] |
| Projection range | The area between the two projections, filled at 14% opacity. Neutral grey on target, accent under, systemOrange or systemRed for over severity | [R7] [R6] |
| Target bounds | Two dotted 1 pt neutral rules, target low labelled below and target high above, at the trailing edge | [R5] [R9] |
| 100% line | Hairline 1 pt solid, separator colour, with the label `Limit 100%` above it at the leading edge | [R9] |
| Legend | None. The headline names the range, the labels name the lines. Solid means measured, dashed means forecast | [A5] |
| Hover readout | Native RuleMark at the inspected date and plain text above the chart showing date/time and measured usage, or the interpolated projected range. The plot ends at reset; native axis labels use space outside it | [A5] |
| Animation | None. The chart renders in place | Design signature (restraint) |

The tint is applied only to the projection range. Target rules and the 100% line stay neutral.

Forecasts above 100 remain visible. The limit and target labels occupy opposite sides of their rules. VoiceOver adjustable actions step through measured samples and daily projected positions using the chart selection. The audio graph uses the same measured anchor, forecast endpoints, target bounds, limit and vertical domain. The hover readout has no instructional placeholder.

### Section order in the menu, rationale

Accounts first because they are the answer. The age line sits right above the commands because it qualifies every number above it, a pattern the usage pages [R1] and [R2] share. Quit is last and alone, as in the system menus. [A8] [unverified]

## States

Each state is one concrete treatment, not a spinner.

| State | Menu bar title | Row |
|-|-|-|
| **under** | Untinted trend-down template | `Room to use` / `Quota da usare`, accent colour |
| **on_target** | Untinted target template | `On target` / `Nell'intervallo`, label colour |
| **over**, amber | Untinted trend-up template | `Over target` / `Sopra l'intervallo`, systemOrange |
| **over**, red | Untinted trend-up template | Same verdict words, systemRed |
| **Loading, first reading** | Symbol only | Name, status word `Reading`, facts line `Reading usage`. The text breathes slowly (opacity 0.55 to 1.0, 1.6 s ease in out). Reduce Motion turns it static |
| **Loading, refresh** | Unchanged | Rows unchanged, the age line reads `Updating`. Refresh Now dimmed. No row flicker |
| **Stale** (latest reading failed, last good kept) | Unchanged, computed from the last good reading | Status word unchanged. Reset remains in the right column. Only readings older than twice the polling interval gain a compact amber age after the usage numbers, with a full VoiceOver reading-age label. A failed attempt alone does not add age. Menu timestamps update every 30 seconds while open. |
| **Error, no reading yet** | Symbol only | Status word `No reading`. Facts line carries the reason, one of: `Claude CLI not found`, `Not signed in, run claude to sign in`, `Timed out`, `Unexpected output` |
| **No accounts** | Symbol only | A single dimmed item `No accounts found`, a muted second line `Sign in with Claude Code or Codex, then choose Refresh Now`, then `Settings…` and `Quit Leeway`. Refresh Now stays visible and dimmed; Account order remains available [A1] |
| **All accounts disabled** | Symbol only | Same as No accounts, second line `All accounts are turned off in Settings` |

Enabling an account starts a refresh immediately. If another read is in flight, a follow-up read includes the newly enabled account. When a reading supplies a reason, display it. The current core otherwise reports only staleness, so use the localized instruction to check CLI sign-in and choose Refresh Now. A first reading in progress shows only native Reading usage text, with no sign-in hint. Leeway never logs in for the user.

## Settings window

The standard macOS Settings window, opened with Command-comma, toolbar tab style, not a sidebar. A three tab app is small enough that the sidebar of the web references ([R10] [R11]) would be wasted space. Their row anatomy is what is borrowed.

| Property | Value |
|-|-|
| Window | Native resizable window, minimum 520 by 440 pt, initial 560 by 500 pt, saved frame. One sizing policy for all tabs; changing panes never changes the user-selected size, and long native Forms scroll internally. First opening centers on the pointer screen, using the full screen to detect a menu bar pointer and the visible area to center. Native frame autosave restores user placement afterward. On each opening, fit a partly offscreen saved frame within its display; if that display is disconnected, center on the active screen. Install the toolbar before restoring, and restore before registering autosave, so the provisional frame never replaces a saved frame |
| Tabs | Accounts, General, Updates, each with an SF Symbol in the toolbar |
| Form | Grouped form. Row: label and an optional description on the leading side, control on the trailing side, hairline between rows [R10] [R11] |
| Label | Body 13 pt. Description Subheadline 11 pt, secondary label |
| Row height | 28 pt without description, 44 pt with |
| Window padding | 20 pt |

### Accounts tab

One Account order picker leads the pane: Most at risk first (default) or Manual.
It reads and writes AppPreferences.accountOrderMode, shared with the menu's
Account order submenu. The status item shows the first enabled account in this
same order. A single account order replaced the previous separate pin/order model on
2026-11-03. A legacy pin becomes the first Manual ID; the old field is decode-only
and is never written again. Existing Manual order without a pin is preserved.
A native SwiftUI List below it shows the current names and supports native
drag and drop through onMove in Manual mode. An initially empty, UI-only
selection binding enables native row selection and drag initiation on macOS. The setting and stable account IDs
are stored in presentation preferences. Failed saves restore the previous order.
Unavailable IDs retain their saved positions, and newly discovered accounts
append. Existing grouped account controls follow the same order below the list.
There is no separate status-account picker or detail pin command.

One settings group per discovered account (two directories that are the same account appear once, spec 1). The Form scrolls within the native window.

Each account is one native grouped Form section. Its header contains the current name and the selectable source folder as one piece of section metadata, with wrapping for long paths. Every control has a separate LabeledContent row, with labels in one column and a shared 180 pt trailing control column:

| Element | Detail | Reference |
|-|-|-|
| Name | Plain native trailing TextField, no custom box, fill or border. Folder-based defaults such as Claude, Claude (claude-work), Claude (Orca profile), Codex; explicit renames always win, never infer identity from an email | spec 1, [R13] |
| Show in menu | Native Toggle with automatic styling | [R13] |
| Target | Value `75-100%` above one two-handle range control, default 75..100, steps of 5, minimum gap 5, limits 0..100. Explanation: Your weekly usage at reset | Decision 2026-11-03, [M6] value hierarchy |
| Reserve account | Pop-up menu with `None` and every other account name. Used by steering as the account to move to | spec 7 |

The source path belongs to the section header, never a free-standing view below a group. While any account retains its default name, Accounts shows one localized naming hint. Below the list: `Add Folder…` opens a folder chooser. User-added folders get a remove button. Discovered ones cannot be removed, only turned off.

### General tab

| Row | Control | Reference |
|-|-|-|
| Refresh interval | Pop-up: 5, 10, 15, 30 minutes (default 15). Description: `How often Leeway reads your usage` | [R11] |
| Language | Pop-up: System default, English, Italiano, with a checkmark on the selected item | [R12] |
| Launch at login | Native Toggle; state reloads whenever the app becomes active | [R13] |
| Menu bar | Native Picker: Compact (default), Percentages | [A1] |

### Updates tab

| Row | Control |
|-|-|
| Check for updates automatically | Native Toggle, default on |
| Current version | Native read-only labeled value from build metadata |
| Updates | Native Check Now button. Without a configured HTTPS feed and public key, explicitly says updates are not set up. No channel selection is exposed; Sparkle uses the default stable channel |

### Focus and fields

No autofocus: opening the window puts the caret nowhere. Clicking a field or control shows no focus ring and no outline change while typing. A subtle focus indicator appears only for keyboard navigation (Tab). Plain native fields have no custom background, border or focus decoration. Return in the account name field saves the trimmed name and resigns focus. Escape restores the saved name and resigns focus. Failed saves restore the persisted name. Neither key focuses another field. Opening Settings activates the app and makes the existing or new window key and frontmost, including when it was behind another app.

## Typography

SF Pro only, the system font. No Dynamic Type on macOS, so sizes below are fixed points from the HIG table. [A3]

| Use | Style | Size and leading | Weight |
|-|-|-|-|
| Menu bar title | Menu bar font | 13 | Regular |
| Account name, form labels | Body | 13 / 16 | Regular |
| Status word | Callout | 12 / 15 | Regular |
| Detail forecast range | SF Pro Display | 34 | Light |
| Detail percent suffix | SF Pro | 18 | Regular, secondary color |
| Detail reset/readout caption | SF Pro | 10 | Regular, secondary color |
| Facts, descriptions, reset | Subheadline | 11 / 14 | Regular |
| Chart axis and line labels | Caption 1 | 10 / 13 | Regular (10 pt is the macOS minimum) |

Numbers in every place (title, rows, submenu, chart, Settings) use tabular figures through the font's own tabular feature. Forbidden: any monospace font for numbers, and the slashed or dotted zero alternates. The design review checks a rendered zero in the menu bar title and in the chart. Monospaced text is allowed only for literal paths and commands.

Separators between values are structure (two columns, a right aligned slot, a muted second line) or plain words and commas. There are no middle dots.

## Colour

Semantic label colours for essential text and neutral lines. Risk text uses semantic systemOrange and systemRed. Account selection uses unemphasizedSelectedContentBackgroundColor blended 12% toward labelColor in both appearances. Names, captions, verdicts and meters keep their semantic colours when highlighted. AppKit owns command selection and menu materials, including Increase Contrast and Reduce Transparency. Controls have no tint, colour or toggle-style override. [A4]

| Role | Colour | Used for |
|-|-|-|
| Primary text | Label | Names, values, used curve, today marker |
| Essential text | Label | Facts, reset and status words |
| Chart labels | Label | Chart axes and target labels |
| Lines | Separator | 100% line, separators |
| Controls | The user's accent colour | Switches, pop-ups, focus (system) |
| Under target | System accent | Status word, percentage title, projection range |
| Over target, amber | System orange | Status word, percentage title, projection range |
| Over target, red | System red | Status word, percentage title, projection range |

No green state. On target is neutral; under invites more usage; over warns about pace. [R9] colours only the breached limit, and nothing around it.

Colour repeats the status words. The only additional semantic colour is the requested amber stale-reading marker. Standard controls, command selection, checkmarks and links inherit the current system accent. [A4] [A6]

## VoiceOver

Every status is spoken as words, numbers as numbers, never colour names.

| Element | Label | Value or hint |
|-|-|-|
| Menu bar item | `Leeway` | Value: `Work, 62 percent used, forecast 84 percent, on target`. When no data: `No readings` |
| Account row | `Work, on target` | Value: `62 percent of weekly quota used. Forecast between 84 and 97 percent at reset. Resets Tuesday at 5:00 AM.` Hint: `Opens the weekly chart` |
| Stale row | as above | Value ends with `Reading is 42 minutes old` |
| Error row | `Work, no reading` | Value: the reason in full, for example `Claude CLI not found` |
| Age line | `Last updated` | Value: `2 minutes ago` |
| Chart | `Weekly usage for Work` | Value: the headline sentence. Provides an audio graph descriptor with series Used, Forecast week pace, Forecast last 24 hours, and Target low and Target high as reference lines [A5] [A6] |
| Settings name field | `Account name` | Value: the name |
| Settings target handles | `Target low` / `Target high` | Independently adjustable values in percent; Tab visits low then high, arrow keys step by 5 |
| Settings reserve | `Reserve account for Work` | Value: `None` or the account name |
| Settings switches | Their visible label | `On` or `Off` |

Keyboard: the whole menu works with arrow keys and Return, Command-R refreshes, Command-comma opens Settings, Command-Q quits. Settings is fully operable with Full Keyboard Access. There is no Inspect Readings submenu. The chart remains accessible through its audio graph and adjustable action. [A6] Loading text is static; no custom animation runs in the menu or Settings. [A6]

## Localisation

Strings exist in English and Italian. The layout must survive Italian lengths. Sample pairs the review checks:

| English | Italiano |
|-|-|
| Room to use | Quota da usare |
| On target | Nell'intervallo |
| Over target | Sopra l'intervallo |
| Refresh Now | Aggiorna ora |
| Account order | Ordine degli account |
| Most at risk first | Il più a rischio prima |
| Manual | Manuale |
| 62% now, 70-84% at reset, target 75-100% | 62% ora, 70-84% al reset, target 75-100% |
| Resets Tue 5:00 AM | Reset mar 05:00 |
| Account name | Nome account |

Times and dates come from the locale, never from string templates. Percent sign placement follows the locale.

## Implementation decisions and verification

1. **Verdict and title.** The title shows the forecast high. The verdict compares the entire forecast interval with the target: high below target low is under, low above target high is over, overlap (including equality) is on target. No forecast is neutral, with explicit unavailable forecast text.
2. **Early blocking.** Over is amber up to 12 hours between exhaustion and reset, red above 12. Without an exhaustion prediction it stays amber, with unknown early hours. Measured weekly usage at 95 does not override the interval verdict; five-hour blocking belongs to advisor policy.
3. **Native menu drawing.** NSMenuItem attributed titles support multiline text and a meter attachment. AccountMenuRow measures the content with NSMenuItemCell, draws the attributed title and uses a neutral selection background, a deliberate revision on 2026-11-03. NSMenu retains tracking, type selection, keyboard navigation and submenu placement. Commands use ordinary NSMenuItem drawing. Offscreen tests cover multiline sizing, semantic colours and target tick visibility.
4. **Hiding the extra.** The HIG asks that people, not the app, decide whether the extra is shown, and suggests a second entry point such as a Dock menu. The spec has no "show in menu bar" setting. Worth deciding before release. [A1]
5. **Apple menu measurements.** AppKit owns standard command selection geometry. Account rows use native cell measurements, while the chart detail has a single stable content inset with no pin-state column.

## References

Apple, Human Interface Guidelines (text read in this session):

| Key | Page | Used for |
|-|-|-|
| A1 | [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) | Menu bar extras: 24 pt height, show a menu not a popover, let people choose to show the extra, keep disabled items visible, do not rely on the extra being shown |
| A2 | [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) | Labels, capitalisation, ellipsis, dimmed unavailable items, separators, checkmarks, single level submenus |
| A3 | [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) | macOS default size 13 pt and minimum 10 pt, SF Pro, no Dynamic Type on macOS, built-in text style sizes and line heights |
| A4 | [Color](https://developer.apple.com/design/human-interface-guidelines/color) | System semantic colours, support for light, dark and Increase Contrast, do not rely on colour alone |
| A5 | [Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data) | Simple common chart types, descriptive text, consistency across charts, accessibility labels and elements |
| A6 | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | VoiceOver descriptions, Full Keyboard Access, Reduce Motion |

Apple's own menus [unverified, recalled, to be checked in the design review]:

| Key | Menu | Used for |
|-|-|-|
| A7 | Battery menu (Control Center item) | Menu width, text inset, 22 pt item height, a bold header then muted descriptive lines, a settings entry at the bottom |
| A8 | Wi-Fi and Focus menus | Command items last and alone, checkmarks on the active item, muted secondary line under a primary label |

Mobbin (web and iOS, used for information patterns only):

| Key | Screen | Used for |
|-|-|-|
| R1 | [Claude, Settings, Usage](https://mobbin.com/screens/ea02c392-d84c-4ce0-81bb-66d7bda183b3) | Session and weekly meters, "x% used", "Resets Tue 5:00 AM", "Last updated: just now" |
| R2 | [Google Gemini, Usage limits](https://mobbin.com/screens/1cb3c785-d4df-4a3a-992d-e887d1129667) | "x% used" against a reset time, weekly limit with its reset date, "Updated just now" |
| R3 | [ClickUp, AI Usage](https://mobbin.com/screens/74eb504f-0704-42bb-8960-be44df787a22) | Label and value columns with a percent column, a single total meter |
| R5 | [Google Health (Fitbit), Cardio load](https://mobbin.com/screens/42cd2707-6d4b-4fa8-830a-040422fb9be4) | Dotted target lines, day-initial x axis, sparse y labels |
| R6 | [Strava, Relative Effort](https://mobbin.com/screens/fff0b506-9862-44e7-80a9-e1e447d404d9) | Solid line for this week, muted line and dashed band for the expected range |
| R7 | [MacroFactor, Expenditure](https://mobbin.com/screens/dc0ce80f-0f1f-469c-a638-bab467b94edf) | A translucent range area around a trend line |
| R8 | [Noom, prediction screen](https://mobbin.com/screens/b581dfaf-98d3-417e-a7c0-8233f4994997) | A plain sentence that states the predicted landing value and date above the chart |
| R9 | [bunq, spending limit](https://mobbin.com/screens/5e4c3ce2-3316-412f-805a-750dfa197108) | A labelled limit line, colour reserved for the breach and its sentence |
| R10 | [Linear, Preferences](https://mobbin.com/screens/8720abc2-c855-44ee-911d-bc15fc1707eb) | Label and description on the left, control on the right, grouped rows |
| R11 | [Buffer, Preferences](https://mobbin.com/screens/0398e56b-5120-4055-9348-2b046ded2e97) | Hairline separated rows with pop-up menus on the trailing side |
| R12 | [Snowflake, Preferences](https://mobbin.com/screens/ba951441-1223-4c92-8ea2-6f2314d2968f) | Language pop-up with a checkmark on the selected item |
| R13 | [Quo, Preferences](https://mobbin.com/screens/3bac6bb7-602e-434b-a05e-83b414de3a78) | A "System" appearance pop-up and switches on the trailing side |
| R14 | [Starlink, Data usage](https://mobbin.com/screens/9d81051a-a7da-47b6-9043-25c9141b6411) | Minimal chart furniture: two axis labels, no grid |

## Native component exceptions and remaining runtime checks

The domain-specific Swift Charts view and its textual facts are hosted custom content. Apple supplies the marks, axes, cursor rule and audio graph; there is no standard NSMenu item that represents a weekly quota forecast. NSHostingView embeds this content in the native submenu. Its leading inset is stable because the detail has no native command or state column. The chart supports VoiceOver adjustment and its native audio graph.

AppKit owns the status item and standard Settings window because the required native NSMenu hierarchy must coexist with hosted Charts content. SwiftUI grouped Forms and LabeledContent own Settings rows; the native Settings window rejects automatic responder changes until the first user click or key event, and resets its native scroll containers to the top whenever opened. Offscreen tests cover both rules. The only custom Settings control is the Target range described below.

Packaged-app checks cover menu placement, focus, VoiceOver, accent variants and macOS 14 behavior.

The account meter is a custom SwiftUI visualization of measured usage and the
forecast range. `NativeUsageMeter` renders `ForecastMeter` into an image attachment
inside the attributed NSMenuItem title. It is not an NSProgressIndicator. AppKit
owns menu tracking and layout; account selection uses the neutral exception below,
and the meter keeps its semantic palette.
The target remains named in text and in the detailed chart.

### Exception: Target range control

macOS has no native two-handle range slider. The owner explicitly requested one
on 2026-11-03. `TargetRangeControl` is one small SwiftUI view with the system
slider track appearance, system control-background thumbs and accent selection.
The displayed range is `75-100%` above the control. Bounds move in steps of 5,
stay in 0..100 and retain a minimum gap of 5. A pointer chooses the nearest
handle even when the thumb hit areas overlap. An untouched fractional policy
bound is preserved; the edited handle snaps to the five-point grid.

Each handle is separately keyboard focusable and VoiceOver adjustable, labelled
`Target low` / `Target high` (localized). Tab follows low then high; left/down
arrows decrease and right/up increase. Opening Settings assigns no focus.
Pointer input shows no focus ring; keyboard navigation uses a subtle accent
indicator. This is the one owner-requested exception to native-only Settings
controls; native Forms, Toggles, Pickers and menus remain system-owned.

Compact mode loads the supplied Phosphor Core 2.1.1 bold SVG image sets,
with template rendering intent and preserved vector data in the asset catalog.
All three remain untinted templates. NSStatusBarButton has no content tint override
in any verdict. Percentages mode remains available with its existing text colours.
The MIT notice is in THIRD_PARTY_NOTICES and bundled with the app resources.
The compact status icon is a template asset; the account-row forecast meter uses ImageRenderer.


### Owner-requested exception: Neutral account selection

The owner changed the requirement on 2026-11-03: account rows must use silver or
grey instead of accent selection. AppKit has no public per-item selection-colour
setter. AccountMenuRow is a drawing-only NSMenuItem view using NSMenuItemCell to
measure the native title inset and row size. It draws the attributed title and
attachment directly, with a system chevron symbol for the submenu. A rounded neutral background uses
unemphasizedSelectedContentBackgroundColor blended 12% toward labelColor, with a
5 pt inset and corner radius. A native tracking area updates drawing on pointer
entry and exit; it never intercepts clicks or replaces native submenu tracking.
The row participates in native hit testing so pointer events reach its tracking
area; NSMenu owns command dispatch, keyboard tracking,
submenus and the menu item's accessibility. Caption, verdict and meter colours
remain unchanged. Refresh Now, Settings and Quit have no custom view.

### Layered app icon

App/Resources/AppIcon.icon contains an opaque graphite background and the white
Phosphor target SVG as a foreground layer. It contains no baked squircle, outer
padding or shadow. Xcode compiles the document for macOS 26 and generates the
fallback icon for macOS 14 and 15. The former raster app icon is no longer an
input. See Apple's [Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).


### Approved detail title, owner choice 2026-11-03

The owner selected A: SF Pro Display Light 34 pt, secondary 18 pt percent and 10 pt caption. The temporary preference and the other studies are removed. This replaces the previous heavy title requirement.
