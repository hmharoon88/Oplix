# Adding Support Page to Existing GitHub Repository

## Quick Steps

### Option 1: Add to Your Main Oplix Repo (Recommended)

1. **Push the support page to your existing repo:**
   ```bash
   cd /Users/haroon/Desktop/Oplix
   git add support.html
   git commit -m "Add support page for App Store"
   git push origin main
   ```

2. **Enable GitHub Pages:**
   - Go to your repository on GitHub
   - Click **Settings** → **Pages** (left sidebar)
   - Under **Source**, select:
     - Branch: `main` (or `master`)
     - Folder: `/ (root)` or `/docs` (if you want it in a docs folder)
   - Click **Save**

3. **Rename for GitHub Pages:**
   - If you want it as the main page, rename `support.html` to `index.html`
   - Or keep it as `support.html` and access it at:
     ```
     https://YOUR_USERNAME.github.io/REPO_NAME/support.html
     ```

### Option 2: Create a Separate `gh-pages` Branch

If you want to keep the support page separate from your main code:

```bash
# Create and switch to gh-pages branch
git checkout -b gh-pages

# Add support page
git add support.html
git commit -m "Add support page"
git push origin gh-pages

# Switch back to main
git checkout main
```

Then in GitHub Settings → Pages, select the `gh-pages` branch.

### Option 3: Use `/docs` Folder

1. Create a `docs` folder in your repo:
   ```bash
   mkdir docs
   cp support.html docs/index.html
   ```

2. Push it:
   ```bash
   git add docs/
   git commit -m "Add support page in docs folder"
   git push origin main
   ```

3. In GitHub Pages settings, select `/docs` as the source folder.

## Your Support URL Will Be:

- If using root: `https://YOUR_USERNAME.github.io/REPO_NAME/`
- If using docs: `https://YOUR_USERNAME.github.io/REPO_NAME/`
- If using gh-pages: `https://YOUR_USERNAME.github.io/REPO_NAME/`

## Use in App Store Connect

1. Go to App Store Connect → Your App → App Information
2. Enter your GitHub Pages URL in the **Support URL** field
3. Save

## Notes

- GitHub Pages is free for public repositories
- Changes take a few minutes to appear
- You can update the page anytime by editing and pushing the HTML file
