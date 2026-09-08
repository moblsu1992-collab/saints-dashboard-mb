# ⚜ Saints NFL Scouting Dashboard — 2025 → 2026

A single-page scouting dashboard: team ratings, league-wide EPA, opponent scouting,
a situational **Tendencies & Matchups** explorer (all 32 teams, both sides, filterable by
play type / score state / down, with head-to-head matchups), interactive **Field Position**
throw & run charts, and coaching philosophy. Built from [nflverse](https://github.com/nflverse) data.

Open `index.html` in a browser to use it. It works offline too (the play-level data loads
from `data/plays.js` via a `<script>` tag), but hosting it makes it reachable from your phone.

## Layout

```
index.html            the whole dashboard (styles + logic + the aggregate DATA)
data/
  plays.js            window.PLAYS = { all 32 teams' play-level data }  ← what refreshes weekly
  plays/<TEAM>.json   per-team play data (same data, split by team)
  plays_index.json    season + field order + per-team passer/rusher lists
build_plays.ps1       regenerates data/ from nflverse pbp + participation (PowerShell, no Python)
build_*.py            original aggregate builds (coverage / field-zone / personnel)
.github/workflows/rebuild.yml   the weekly auto-refresh Action
```

## Weekly auto-refresh

`.github/workflows/rebuild.yml` runs every **Wednesday** (and on demand from the Actions tab).
It pulls the latest nflverse play-by-play + participation, re-runs `build_plays.ps1` on the
runner's PowerShell, and commits `data/`. With Pages set to deploy from the branch, that commit
redeploys the live site automatically.

**Scope:** only the **play-level data** (Tendencies + Field Position tabs) refreshes weekly —
that's the part that changes as games are played. The **aggregate/curated tabs** (Team Ratings,
League EPA framing, Opponents' 2026 staff & proxies, Philosophy, Draft) are a maintained baseline
and are edited by hand in `index.html`, not rebuilt by the Action.

**Season bump:** the workflow's `SEASON` env is `2025`. Change it to `2026` once the 2026 regular
season starts (Sept 2026), when nflverse begins publishing `play_by_play_2026`.

## One-time setup (get it hosted)

1. **Create a repo** on GitHub (e.g. `saints-dashboard`), empty.
2. **Push this folder** to it:
   ```bash
   git remote add origin https://github.com/<you>/saints-dashboard.git
   git branch -M main
   git push -u origin main
   ```
   (This folder is already a git repo with an initial commit.)
3. **Enable Pages:** repo **Settings → Pages → Source: Deploy from a branch → `main` / `/ (root)`**.
   The site goes live at `https://<you>.github.io/saints-dashboard/`.
4. **Let the Action commit:** **Settings → Actions → General → Workflow permissions → Read and write**.
5. (Optional) Run the workflow once now: **Actions → "Weekly nflverse data refresh" → Run workflow**,
   to confirm the pipeline works end-to-end.

## Refresh locally (Windows, no cloud)

```powershell
# download the two nflverse files, then:
./build_plays.ps1 -Gz pbp.csv.gz -Part part.csv -OutDir . -Year 2025
```
