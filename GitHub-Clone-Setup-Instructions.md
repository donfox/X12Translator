# X12Bridge: Setup Instructions for GitHub Clones

## Found the Problem! 🎯

**The issue:** Built CSS and JavaScript assets are **not tracked in Git** (by design), so people cloning the repo are missing critical frontend files.

### What's Missing for Fresh Clones

**Ignored files that exist locally but not on GitHub:**
- `priv/static/assets/css/app.css` (compiled CSS)
- `priv/static/assets/js/app.js` (compiled JavaScript)

These are in your `.gitignore`:
```
/priv/static/assets/
/priv/static/cache_manifest.json
```

### Why This Causes Anomalies

When people clone and run `mix phx.server` without building assets:
- ❌ No styling (missing Tailwind CSS)
- ❌ No JavaScript functionality (missing LiveView JS hooks)
- ❌ Broken UI layout
- ❌ Non-functional interactive elements

---

## The Solution

People cloning the repo **MUST run the setup command** first:

```bash
git clone https://github.com/donfox/X12Bridge.git
cd X12Bridge
mix setup    # ← THIS IS REQUIRED!
mix phx.server
```

The `mix setup` alias runs:
1. `deps.get` - Install Elixir dependencies
2. `ecto.setup` - Create and migrate database
3. `assets.setup` - Install Tailwind and esbuild
4. `assets.build` - **Build CSS and JS files**

---

## Recommendation: Update the README

The README already has this correct (`mix setup` in Quick Start), but you might want to emphasize it more. Add this warning:

```markdown
## ⚠️ Important: First Time Setup

**DO NOT skip `mix setup`!** The application will not work without building assets first.

**Symptoms of skipping setup:**
- Missing styles and broken layout
- Non-functional file uploads
- Broken LiveView interactions

**If you're experiencing issues:**
```bash
cd X12Bridge
rm -rf _build deps priv/static/assets
mix setup
mix phx.server
```
```

---

## Verify the Issue is Fixed

Anyone having problems should run:
```bash
cd X12Bridge
rm -rf _build deps priv/static/assets  # Clean everything
mix setup                               # Rebuild from scratch
mix phx.server
```

**This is normal behavior for Phoenix apps** - built assets are never committed to git. The issue is users not running `mix setup` before starting the server.
