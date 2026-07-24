# GitHub Pages Deployment

## Live site

**URL:** https://shyamalschandra.github.io/Yankovinator/

> GitHub Pages URLs follow the repository name casing (`Yankovinator`).

## How it works

Deployment uses the **GitHub Actions** Pages flow (not the legacy “deploy from `/docs` branch folder” mode).

| Setting | Value |
|---|---|
| Workflow | [`.github/workflows/pages.yml`](../.github/workflows/pages.yml) |
| Trigger | push to `main` (docs/site paths) or manual `workflow_dispatch` |
| Build job | Node 20 (`npm ci` + `tsc`) + LaTeX PDF builds |
| Deploy job | `actions/deploy-pages` → `github-pages` environment |
| Published URL | https://shyamalschandra.github.io/Yankovinator/ |

## What gets published

The workflow stages a clean `_site/` artifact (not the raw `docs/` tree):

- `index.html`, `styles.css`, `script.js`
- `yankovinator.pdf`, `presentation.pdf`, `reference.pdf`
- `README.md`, `RELEASES.md`, `DEPLOYMENT.md` (from `docs/`)
- `PROJECT_README.md` (copy of repo-root README)

Source-only files (`.tex`, `.ts`, Beamer aux files, etc.) are **not** uploaded.

## When the workflow runs

Pushes to `main` that touch:

- `docs/**`
- `.github/workflows/pages.yml`
- `package.json` / `package-lock.json`
- `tsconfig.json`
- `README.md`

Or run manually:

```bash
gh workflow run "Deploy GitHub Pages"
gh run watch --workflow "Deploy GitHub Pages"
```

## Local preview (site assets)

```bash
npm ci
npm run build
cd docs && python3 -m http.server 8080
```

Rebuild PDFs locally (optional; CI also builds them):

```bash
cd docs
latexmk -pdf -interaction=nonstopmode yankovinator.tex
latexmk -pdf -interaction=nonstopmode presentation.tex
latexmk -pdf -interaction=nonstopmode reference.tex
```

## Verification

1. Open https://shyamalschandra.github.io/Yankovinator/
2. Confirm PDFs open: `/yankovinator.pdf`, `/presentation.pdf`, `/reference.pdf`
3. Pages settings: https://github.com/shyamalschandra/Yankovinator/settings/pages  
   Source should be **GitHub Actions**
4. Actions: https://github.com/shyamalschandra/Yankovinator/actions/workflows/pages.yml

## Troubleshooting

1. Hard-refresh (Cmd+Shift+R / Ctrl+Shift+R)
2. Wait 1–5 minutes after a green deploy job
3. Confirm **build** and **deploy** both succeeded
4. Confirm Pages source is **GitHub Actions**, not a branch folder
5. Confirm URL casing: `Yankovinator`
