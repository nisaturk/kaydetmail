---
name: kaydetmail-git-workflow
description: >
  Project-specific Git/GitHub discipline for the kaydetmail repository
  (github.com:nisaturk/kaydetmail.git). Use for every branch, commit, PR, and
  merge in this repo — encodes this project's actual conventions (commit
  format, branch naming, validation commands, merge strategy), which differ
  from generic trunk-workflow defaults (this repo keeps merge commits, does
  not squash).
---

# kaydetmail Git/GitHub workflow

Repo: `git@github.com:nisaturk/kaydetmail.git` (SSH remote, `gh` already
authenticated). Default branch: `main`, PR-only — never push directly to it.

## 1. Start every task from a clean `main`

```bash
git checkout main
git pull --ff-only
git checkout -b <type>/<kebab-slug>
```

Branch naming — `<type>/<kebab-slug>`, matching observed history
(`docs/readme-rewrite`, `chore/remove-stale-mock-references`,
`perf/push-tap-routing-latency`). `<type>` is one of `feat`, `fix`, `docs`,
`chore`, `perf`, `refactor`, `test`. Never branch off anything but `main`.

## 2. Validate before every commit

```bash
flutter analyze          # must be clean
flutter test              # full suite (~180 tests) — fast enough to always run in full
flutter test test/some_file.dart          # single file while iterating
flutter test --plain-name "name"          # single test/group by name, any file
```

Never commit with `flutter analyze` warnings or a red `flutter test`. There is
no separate lint config beyond `flutter_lints` in `analysis_options.yaml`.

## 3. Commit message format

`type: summary`, one line, present tense, describing *why* — matches the two
most recent commits on `main` at any given time (`feat:`, `fix:`, `perf:`,
`docs:`, `chore:`, `refactor:`, `test:`). Older history before that pair is
inconsistent (plain descriptive subjects, stray backslashes/quotes) —
**never imitate it**, always re-check the current tip of `main` for the
pattern in force.

Keep each commit/PR scoped to one logical change. Don't bundle an unrelated
fix with a feature.

```bash
git add <intentional files>
git commit -m "feat: short summary of why this change exists"
```

## 4. Push and open the PR

```bash
git push -u origin <branch>
gh pr create --title "<type>: <summary>" --body "$(cat <<'EOF'
## Problem
<what was broken/missing, with evidence>

## Fix
<what changed and why this approach>

## Verification
- flutter analyze: <result>
- flutter test: <result, test count>
- <manual/smoke verification performed, if any>
EOF
)"
```

This Problem/Fix/Verification body has worked well here — keep using it.

## 5. Merge strategy — merge commit, NOT squash

This repo's `main` history is full of explicit `Merge pull request #N from
nisaturk/<branch>` commits (check `git log --oneline` — every PR lands this
way). **Always merge with a merge commit**, never squash or rebase-merge:

```bash
gh pr merge <number> --merge --delete-branch
```

## 6. After merge

```bash
git checkout main
git pull --ff-only
```

`--delete-branch` on `gh pr merge` already removes the remote branch and, if
you're on it, offers to delete local too — confirm the local branch is gone
(`git branch` should no longer list it) after switching back to `main`.

## 7. Non-negotiables

- Never push directly to `main`.
- Never squash-merge or rebase-merge a PR in this repo — merge commit only.
- Never skip `flutter analyze`/`flutter test` before committing.
- Never fabricate a "tests pass" claim — run them, quote the actual count/result.
- One PR = one logical change; don't drive-by reformat or refactor unrelated code.
