# Yankovinator GitHub Pages

Source for the Yankovinator website deployed from this `docs/` directory.

**Live site:** https://shyamalschandra.github.io/Yankovinator/

## Structure

| File | Role |
|---|---|
| `index.html` | Compact brand-first landing (hero + install/docs) |
| `styles.css` | Stage Brass theme (Syne/Sora, teal + brass) |
| `script.ts` | Tabs, copy, sample demo, lyric typewriter |
| `script.js` | Compiled JS from `tsc` (generated) |
| `RELEASES.md` | Binary release install notes |
| `CERTIFICATION.md` | Release certification battery guide |
| `certification-latest.txt` | Latest local certification report |
| `DEPLOYMENT.md` | Pages deployment status |

## Design notes

- First viewport: **Yankovinator** as the hero brand, one headline, one lede, CTAs, full-bleed lyric plane
- Second band: Homebrew/Source install + capabilities + docs (minimal scroll)
- Motions: brand entrance, score-wave dash, lyric typewriter

## Development

```bash
npm install
npm run build    # docs/script.ts → docs/script.js
cd docs && python3 -m http.server 8080
```

## Deployment

GitHub Actions (`.github/workflows/pages.yml`) builds TypeScript + LaTeX PDFs and deploys `_site/`.

```bash
gh workflow run "Deploy GitHub Pages"
```

Details: [DEPLOYMENT.md](DEPLOYMENT.md)
