---
name: create-pr
description: Create a PR. Creates a branch, commits changes, pushes, and opens a draft PR via GitHub CLI. Use when the user wants to commit and open a pull request for their current changes. NEVER commits on main.
---

# Create PR

Create a branch, commit all changes, push, and optionally open a draft PR via GitHub CLI.

## Usage

```
/create-pr <brief description of the changes>
```

Examples:
- `/create-pr add SKAdImpression Sendable wrapper`
- `/create-pr bump bundled OMID xcframework to v1.6.4`
- `/create-pr fix Bundle.module fallback for CocoaPods consumers`

---

## Instructions

You are creating a pull request for the user's current changes. Follow these steps exactly.

### Step 0: Safety Check — Protected Branches

**CRITICAL: You must NEVER commit on `main`.**

Run `git branch --show-current` to determine the current branch.

- If the current branch is `main`, you **MUST create a new branch** before committing.
- If the current branch is already a feature/fix branch, you may commit on it directly.

### Step 1: Determine Branch Name

If you need to create a new branch, derive a short, descriptive kebab-case name from the user's description. Prefix with a conventional type:

- `feat/` — new features
- `fix/` — bug fixes
- `refactor/` — code restructuring
- `chore/` — maintenance, config, CI
- `docs/` — documentation only

Example: `/create-pr fix Bundle.module fallback for CocoaPods consumers` → `fix/bundle-module-cocoapods-fallback`

Create and switch to the branch:
```bash
git checkout -b <branch-name>
```

### Step 2: Review Changes

Run these commands to understand what will be committed:
```bash
git status
git diff
git diff --staged
```

Review the output. If there are no changes at all, inform the user there is nothing to commit and stop.

Do NOT commit files that likely contain secrets (`.env`, `*.pem`, `*.key`). Warn the user if such files are present.

### Step 3: Stage and Commit

Stage the relevant files. Prefer staging specific files rather than `git add -A`:
```bash
git add <files>
```

Write a concise commit message based on the actual changes. Follow conventional commit style:

```
<type>: <short summary>

<optional body explaining why>
```

Commit:
```bash
git commit -m "<message>"
```

### Step 4: Push

Push the branch to origin:
```bash
git push -u origin <branch-name>
```

If the push fails due to diverged history, **do NOT force push**. Instead, inform the user and ask how they want to proceed.

### Step 5: Create Draft PR (if GitHub CLI available)

Check if `gh` is available:
```bash
which gh
```

If `gh` is available, create a **draft** pull request targeting `main`:

```bash
gh pr create --draft --title "<PR title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing the changes>

## Test plan
- [ ] swiftlint lint passes
- [ ] xcodebuild test passes (iPhone 16 Pro simulator)
- [ ] pod lib lint KontextKit.podspec passes
- [ ] <any manual testing steps>

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

The PR title should be concise (under 70 characters). Use the body for details.

If `gh` is NOT available, print the URL the user can visit to create the PR manually:
```
https://github.com/kontextso/kontextkit-ios/compare/<branch-name>?expand=1
```

### Step 6: Report

Print a summary:
- Branch name
- Files committed
- Commit hash (short)
- PR URL (if created) or manual link

---

## Error Handling

- **On `main`**: Always create a new branch. Never commit directly.
- **No changes**: Inform the user and stop.
- **Push rejected**: Do not force push. Ask the user.
- **gh auth issues**: Fall back to printing a manual PR URL.
- **Pre-commit hook failure**: Fix the issue, re-stage, and create a NEW commit (never amend).
