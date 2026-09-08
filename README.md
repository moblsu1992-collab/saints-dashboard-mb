# Saints Dashboard — redesign options (static)

Drop these two items at the root of the `saints-dashboard-mb` repo branch that GitHub Pages serves:

- `index.html` — self-contained page (all code, fonts and styles inlined)
- `logos/` — the 32 team logos the page loads by relative path

If you want to keep the existing dashboard live at the root, put both inside a subfolder instead, e.g. `redesign/index.html` + `redesign/logos/`, and it will serve at `/saints-dashboard-mb/redesign/`.

Nothing else is required — no build step, no dependencies.
