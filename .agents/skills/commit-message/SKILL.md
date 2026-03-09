---
name: commit-message
description: >-
  Write high-quality Git commit messages following the Conventional Commits specification.
  Use this skill whenever the user provides a git diff, describes code changes, or asks
  for help writing a commit message. Triggers include: write a commit, commit message,
  git commit, how do I commit this, what should my commit say, or when the user pastes
  a diff or describes what they changed. Always use this skill proactively, even if the
  user just describes what they changed without explicitly asking for a commit message.
---

# Commit Message Skill

Write commit messages that follow Conventional Commits v1.0.0, capturing both **What** changed and **Why** it changed.

## Core Philosophy

A good commit message is like a good code comment — don't just describe *what* you did, explain *why* you did it. Future maintainers (including your future self) need context, not just a summary.

Every commit message should answer:
- **What** — what changed in this commit
- **Why** — the reason or motivation behind the change
- **How** — (when non-obvious) the approach taken

---

## Format

```
<type>[optional scope]: <subject>

[optional body]

[optional footer(s)]
```

### Header: `<type>(<scope>): <subject>`

**type** (required) — signals the nature of the change so reviewers know how to approach it:

| Type | Description | When to use |
|------|-------------|-------------|
| `feat` | New feature | Adding an API endpoint, new UI component |
| `fix` | Bug fix | Correcting logic errors, patching security issues |
| `docs` | Documentation only | Updating README, adding JSDoc comments |
| `style` | Formatting, no logic change | Fix indentation, missing semicolons, whitespace |
| `refactor` | Code restructure, not a feat or fix | Extracting shared functions, improving structure |
| `perf` | Performance improvement | Faster queries, reduced re-renders |
| `test` | Adding or updating tests | New unit tests, fixing test assertions |
| `chore` | Build process or tooling | Updating dependencies, modifying CI config |
| `revert` | Reverting a previous commit | Rolling back a bad release |
| `ci` | CI/CD pipeline changes | Updating GitHub Actions workflows |
| `build` | Build system changes | Adjusting webpack, turbo, or bundler config |

**scope** (optional) — the area of the codebase affected, enclosed in parentheses:
- Module: `auth`, `api`, `ui`, `db`
- Package in a monorepo: `web`, `server`, `shared`
- Feature area: `login`, `payment`, `search`

**subject** (required) rules:
- Max **50 characters**
- No trailing period
- Use **imperative mood**: `add`, `fix`, `update` — not `added`, `fixed`, `updated`
- Start with a lowercase letter

### Body (optional)

- Separated from the header by one blank line
- Wrap lines at **72 characters**
- Explain *why* the change was made and how it differs from previous behavior
- Bullet points are fine for listing multiple changes

### Footer (optional)

- Separated from the body by one blank line
- Reference issues: `Closes #123`, `Refs #456`
- Breaking changes: start with `BREAKING CHANGE:` followed by description and migration steps
- Alternatively, append `!` after type/scope: `feat!:` or `feat(api)!:`

---

## Output Rules

1. **Always produce a ready-to-copy commit message** as the primary output, wrapped in a code block
2. If the change is a breaking change, use `!` or include a `BREAKING CHANGE:` footer — never omit it
3. If the user provides insufficient context, produce the best-guess message first, then ask if anything needs adjusting
4. If the user's changes cover multiple unrelated concerns, flag this and suggest splitting into separate commits, with a message drafted for each
5. Default to English for the subject and body

---

## Examples

### Simple bug fix
```
fix(auth): redirect to login when session token expires

Previously the app crashed with an unhandled promise rejection when
the token expired mid-session. Now it gracefully redirects the user
to the login page and clears the stale session data.

Closes #234
```

### New feature with scope
```
feat(api): add pagination to GET /users endpoint

Add `page` and `limit` query parameters for cursor-based pagination.
Default page size is 20, maximum is 100. Responses now include a
`meta.total` field for client-side pagination UI.

Refs #189
```

### Breaking change
```
feat(db)!: replace Prisma with Drizzle ORM

BREAKING CHANGE: All database query APIs have changed.
Prisma Client calls must be replaced with Drizzle equivalents.
See docs/migration-drizzle.md for the full migration guide.
```

### Style only
```
style: fix indentation and remove trailing whitespace
```

### Refactor with context
```
refactor(scraper): extract product parser into separate module

Parsing and fetching were tightly coupled, making the scraper hard
to unit test. Separating them allows each part to be tested in
isolation without mocking HTTP calls.
```

### Chore
```
chore: upgrade eslint to v9 and migrate flat config

ESLint v8 reaches EOL in 2025. Migrated to the new flat config
format (`eslint.config.js`) and updated all plugin configurations
accordingly.
```

---

## Workflow

1. **Analyze input** — read the diff, description, or problem statement
2. **Determine type** — pick the type that best matches the nature of the change
3. **Determine scope** — add one if the affected area is identifiable
4. **Write the subject** — concise What, under 50 characters, imperative mood
5. **Evaluate body** — include it if there's meaningful Why or context that isn't obvious
6. **Evaluate footer** — add issue references or breaking change notices as needed
7. **Output** — deliver the complete message in a code block, ready to copy
