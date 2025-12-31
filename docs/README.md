# LingCode Website

This directory contains the GitHub Pages website for LingCode.

## Files

- `index.html` - Main landing page
- `privacy.html` - Privacy Policy
- `terms.html` - Terms of Service
- `support.html` - Support and FAQ page
- `_config.yml` - Jekyll configuration (optional)

## Setting Up GitHub Pages

1. Go to your repository settings on GitHub
2. Navigate to "Pages" in the left sidebar
3. Under "Source", select "Deploy from a branch"
4. Choose "main" branch and "/docs" folder
5. Click "Save"

Your site will be available at: `https://xavierhuang.github.io/LingCode/`

## Local Testing

You can test the site locally by opening the HTML files in a browser, or by using a simple HTTP server:

```bash
cd docs
python3 -m http.server 8000
```

Then visit `http://localhost:8000` in your browser.

