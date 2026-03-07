# X12Translator Setup Error - Rebar3 Permission Issue

## Error Description

When running `mix setup`, the following error occurs:

```
Error reading file /Users/papabear/.config/rebar3/rebar.config: permission denied
** (Mix) Could not compile dependency :telemetry, "/Users/papabear/.mix/elixir/1-19-otp-28/rebar3 bare compile --paths /Users/papabear/X12Translator/_build/dev/lib/*/ebin" command failed.
```

## Root Cause

This is a file permission issue with the rebar3 configuration file on the local machine. The file `/Users/papabear/.config/rebar3/rebar.config` has incorrect permissions that prevent the build system from reading it.

**Note:** This is not an application code issue - it's a local environment configuration problem.

---

## Solutions (In Order of Preference)

### Solution 1: Fix the Permissions ⭐ RECOMMENDED

Run the following command in your terminal:

```bash
chmod 644 ~/.config/rebar3/rebar.config
```

Then retry:

```bash
mix setup
```

---

### Solution 2: Remove and Regenerate Rebar3 Config

This is the cleanest approach if Solution 1 doesn't work:

```bash
rm -rf ~/.config/rebar3
```

Then run setup again:

```bash
mix setup
```

Rebar3 will automatically recreate the configuration directory with correct permissions.

---

### Solution 3: Clean and Rebuild Dependencies

If the above solutions don't work, try a complete clean rebuild:

```bash
# Clean all dependencies
mix deps.clean --all

# Remove build artifacts
rm -rf _build

# Run setup again
mix setup
```

---

### Solution 4: Fix Ownership (Advanced)

If none of the above work, there may be an ownership issue. 

First, check the current ownership:

```bash
ls -la ~/.config/rebar3/
```

If the files are owned by a different user or have incorrect permissions, fix them:

```bash
# Fix ownership (replace 'papabear' with your actual username)
sudo chown -R papabear:staff ~/.config/rebar3/

# Fix permissions
chmod -R 755 ~/.config/rebar3/
```

Then retry:

```bash
mix setup
```

---

## Expected Result

After applying the fix, `mix setup` should complete successfully:

```
Resolving Hex dependencies...
Resolution completed in 0.063s
All dependencies have been fetched
Compiled successfully
...
```

---

## Additional Notes

- This issue typically occurs when rebar3 configuration files were created with incorrect permissions, often after system updates or when files were copied from another machine.
- The `telemetry` dependency specifically uses rebar3 for compilation, which is why it fails at this step.
- After fixing the permissions once, this issue should not recur.

---

## Contact

If you continue to experience issues after trying these solutions, please provide:
1. Output of `ls -la ~/.config/rebar3/`
2. Your macOS version
3. Elixir and Erlang versions (`elixir --version`)

---

**Document Created:** January 20, 2026  
**Application:** X12Translator  
**Issue Type:** Environment Setup
