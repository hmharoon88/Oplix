# Setting Up Support Page on GitHub Pages

## Step 1: Create a GitHub Repository

1. Go to [GitHub](https://github.com) and sign in
2. Click the "+" icon in the top right → "New repository"
3. Name it something like `oplix-support` or `oplix-website`
4. Make it **Public** (required for free GitHub Pages)
5. Click "Create repository"

## Step 2: Upload the Support Page

### Option A: Using GitHub Web Interface

1. In your new repository, click "Add file" → "Upload files"
2. Drag and drop the `support.html` file
3. Rename it to `index.html` (or keep it as `support.html`)
4. Click "Commit changes"

### Option B: Using Git Command Line

```bash
# Clone your repository
git clone https://github.com/YOUR_USERNAME/oplix-support.git
cd oplix-support

# Copy support.html to the repository
# Rename it to index.html (optional, but recommended)
cp support.html index.html

# Add, commit, and push
git add index.html
git commit -m "Add support page"
git push origin main
```

## Step 3: Enable GitHub Pages

1. Go to your repository on GitHub
2. Click **Settings** (top menu)
3. Scroll down to **Pages** (left sidebar)
4. Under **Source**, select:
   - Branch: `main` (or `master`)
   - Folder: `/ (root)`
5. Click **Save**
6. Wait a few minutes for GitHub to build your site

## Step 4: Get Your Support URL

After GitHub Pages is enabled, your support page will be available at:

```
https://YOUR_USERNAME.github.io/oplix-support/
```

Or if you used a custom domain:
```
https://yourdomain.com
```

## Step 5: Use in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to your app → App Information
3. In the **Support URL** field, enter:
   ```
   https://YOUR_USERNAME.github.io/oplix-support/
   ```
4. Save your changes

## Customization

### Update Contact Email
Edit `support.html` and change:
```html
<p><strong>Email:</strong> support@oplix.app</p>
```
to your actual support email.

### Add More FAQs
Add more FAQ items in the "Frequently Asked Questions" section:
```html
<div class="faq-item">
    <h3>Your Question Here</h3>
    <p>Your answer here</p>
</div>
```

### Custom Domain (Optional)
If you have a custom domain:
1. In GitHub Pages settings, add your custom domain
2. Update DNS records as instructed
3. Use your custom domain in App Store Connect

## Testing

Before submitting to App Store:
1. Visit your GitHub Pages URL
2. Test on mobile devices
3. Ensure all links work
4. Verify contact information is correct

## Notes

- GitHub Pages is free for public repositories
- Changes may take a few minutes to appear after pushing
- The page is automatically mobile-responsive
- You can update the page anytime by editing the HTML file
