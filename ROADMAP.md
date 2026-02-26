# RxBurn Roadmap

## 1. ~~Rename to RxBurn~~ ✓

Prescribed burn. Controlled spending. California fire ecology meets developer tooling.

## 2. Smart threshold from subscription tier

Currently hardcoded to $50. Should reflect actual Claude subscription.

**Approach:** Let users pick their plan tier (Pro $20, Max 5x $100, Max 20x $200). Calculate daily budget as plan price / 30. Support multiple threshold lines — daily budget (green zone) and a hard ceiling.

- Config file at `~/.config/rxburn/config.json`
- First-run picker: "What's your Claude plan?" with tier options
- Derived thresholds: daily budget line + monthly ceiling
- Custom manual threshold for API-only users

## 3. Dependency check / first-run experience

What happens when a user doesn't have npm/npx installed?

- Check for npx on launch, show friendly error state instead of cryptic failure
- Suggest install: "RxBurn needs Node.js to fetch usage data. Install via homebrew: `brew install node`"
- Maybe a one-time "Setup" view that validates dependencies

## 4. Better X-axis labels

Current labels are crowded on the Month view (30 bars). Improvements:

- **Week view:** Show day names (Mon, Tue, ...) for each bar
- **Month view:** Show labels every ~7 days, not every bar
- **Year view:** Show month abbreviations (Jan, Feb, ...) at month boundaries

## 5. Future ideas (not prioritized)

- Sparkline in menu bar instead of just text
- Notification when approaching daily/monthly budget
- Export usage data
- Multiple org/workspace support
- Dark/light theme following system
