# Oplix — GitHub Pages setup

The public website lives in the **`docs/`** folder so it does not mix with the Xcode project at the repo root.

## Pages

| File | URL path |
|------|----------|
| Home (marketing) | `/` |
| Support | `/support.html` |
| Privacy | `/privacy.html` |

## Enable GitHub Pages (one time)

1. Open [github.com/hmharoon88/Oplix](https://github.com/hmharoon88/Oplix)
2. **Settings** → **Pages** (left sidebar)
3. Under **Build and deployment** → **Source**:
   - **Deploy from a branch**
   - Branch: `main` (or your default branch after merge)
   - Folder: **`/docs`**
4. Click **Save**
5. Wait 1–5 minutes for the site to build

## Your live URLs

After Pages is enabled:

```
https://hmharoon88.github.io/Oplix/
https://hmharoon88.github.io/Oplix/support.html
https://hmharoon88.github.io/Oplix/privacy.html
```

Use the **support** URL in App Store Connect → **Support URL**.

Use the **privacy** URL for the privacy policy link if required.

## Publish changes

From the repo root:

```bash
git add docs/
git commit -m "Update website"
git push origin main
```

Changes usually appear within a few minutes.

## App Store link

When the app is on the App Store, edit `docs/index.html` and replace the placeholder download button with your real App Store URL:

```html
<a href="https://apps.apple.com/app/idYOUR_APP_ID" class="btn btn-primary">Download on the App Store</a>
```

## Custom domain (optional)

1. Buy a domain (e.g. `oplix.app`)
2. In **Settings → Pages**, enter the custom domain
3. Add the DNS records GitHub shows at your registrar
4. Enable **Enforce HTTPS**

## Preview locally

Open `docs/index.html` in a browser (double-click or drag into Chrome/Safari). For correct CSS paths, open from the `docs` folder or use a simple local server:

```bash
cd docs && python3 -m http.server 8080
```

Then visit `http://localhost:8080`

## Notes

- `docs/.nojekyll` tells GitHub not to run Jekyll (avoids path issues)
- Free GitHub Pages requires a **public** repository
- iOS code in `Oplix/` is unaffected by website updates
