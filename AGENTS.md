# AGENTS Guidelines

This file collects repository-specific guidance for coding agents working on `mysqlfs`.

## Commit Messages

- Use a short imperative summary on the first line.
- Leave one blank line after the summary.
- Follow with a flat bullet list describing the concrete interventions.
- Leave one blank line after the bullet list.
- Sign the commit message with:
  `Coauthored by AI - Codex GPT 5.4`
- Before creating a release tag or other stable milestone tag, update the
  project changelog first so the tagged state always contains the
  corresponding release notes.

Example:

```text
Make rename target replacement transactional

- move rename target handling into query_rename
- remove preemptive unlink from mysqlfs_rename
- add rollback/commit flow for rename failure handling

Coauthored by AI - Codex GPT 5.4
```

## Change Scope

- Prefer small, reviewable commits focused on one issue at a time.
- Preserve the current architecture: FUSE entrypoints in `src/mysqlfs.c`, SQL logic in `src/query.c`, pooling in `src/pool.c`.
- Avoid mixing behavioral fixes with broad refactors unless required for correctness.

## Function Formatting

- Whenever you touch a function, also verify that the indentation inside that function is clean and consistent.
- Use spaces for indentation inside edited functions, not tabs.
- Prefer readable C formatting over tightly packed expressions; a little extra whitespace is better than hard-to-scan code.
- When practical, prefer fail-first control flow so error handling happens early and the main path stays easy to read.

## Markdown Links

- Inside repository Markdown files, use relative links instead of absolute local filesystem paths.
- Absolute paths are fine in Codex responses when referencing local files for the user, but they should not be committed into project documentation.

## Safety Expectations

- Be careful with filesystem semantics: changes should be checked against expected POSIX/FUSE behavior.
- Favor transactional handling for multi-step database mutations.
- Do not introduce destructive git operations such as history rewrites unless explicitly requested.
- Do not revert unrelated user changes in the worktree.

## Validation Notes

- When possible, verify both the SQL-side behavior and the FUSE-visible behavior.
- If local build or test tooling is unavailable, state that clearly in the handoff.
