# Yankovinator GitHub Pages

Source for the Yankovinator website deployed from this `docs/` directory.

**Live site:** https://shyamalschandra.github.io/Yankovinator/

## Structure

| File | Role |
|---|---|
| `index.html` | Main marketing / install page |
| `styles.css` | Layout, gradients, motion |
| `script.ts` | TypeScript UI source (edit this) |
| `script.js` | Compiled JS from `tsc` (generated) |
| `RELEASES.md` | Binary release install notes |
| `CERTIFICATION.md` | Release certification battery guide |
| `certification-latest.txt` | Latest local certification report |
| `DEPLOYMENT.md` | Pages deployment status |
| `yankovinator.tex` | Technical paper |
| `presentation.tex` | Beamer slides |
| `reference.tex` | API reference |

## Development

### Prerequisites

- Node.js 20+
- npm

### Setup and build

```bash
# from repository root
npm install
npm run build    # compiles docs/script.ts → docs/script.js
npm run watch    # optional live recompile
```

Do not hand-edit `script.js`; change `script.ts` and rebuild.

### Preview locally

Open `docs/index.html` in a browser, or serve the folder:

```bash
cd docs && python3 -m http.server 8080
```

## Deployment

GitHub Actions builds a clean `_site/` artifact and deploys it with the official Pages actions (see `.github/workflows/pages.yml`):

1. Checkout + Node 20 (`npm ci`, `tsc`)
2. Build LaTeX PDFs (`yankovinator`, `presentation`, `reference`)
3. Stage only publishable assets into `_site/`
4. Upload Pages artifact + deploy

Manual trigger:

```bash
gh workflow run "Deploy GitHub Pages"
```

Details: [DEPLOYMENT.md](DEPLOYMENT.md)

## Site features

- Interactive demo UI with progress / loading states
- Smooth scroll, parallax accents, SVG hover motion
- Responsive layout for desktop and mobile
- Install tabs (Homebrew vs source) with Ollama setup
- Links to releases, docs, and Ollama

## Related docs (repo root)

- [../README.md](../README.md) — full product guide
- [../QUICK_START.md](../QUICK_START.md) — fastest path to a working parody
- [RELEASES.md](RELEASES.md) — pre-built binaries
