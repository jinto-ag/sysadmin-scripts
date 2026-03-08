# Commit Message Format

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

## Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect code meaning (formatting) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `build` | Changes to build system or dependencies |
| `ci` | Changes to CI configuration |
| `chore` | Other changes that don't modify src or test files |
| `revert` | Reverts a previous commit |

## Scope (Optional)

Scopes describe the part of the codebase affected:

- `config` - Configuration files
- `deps` - Dependencies
- `ci` - CI/CD
- `docs` - Documentation
- `core` - Core functionality
- `api` - API changes
- `ui` - User interface
- `auth` - Authentication
- `db` - Database
- `security` - Security related

## Subject

- Use imperative mood: "add feature" not "added feature"
- No capitalize first letter
- No period at end
- Max 100 characters

## Body (Optional)

- Explain *what* and *why*, not *how*
- Wrap at 100 characters
- Separate from subject with blank line

## Footer (Optional)

- Breaking changes: `BREAKING CHANGE: description`
- Issue references: `Closes #123`, `Fixes #456`

## Examples

```
feat(auth): add OAuth2 login support

Add Google and GitHub OAuth2 authentication providers.
Includes token refresh and secure session management.

Closes #123
```

```
fix(api): resolve rate limiting issue

Fixed infinite retry loop when rate limited.
Added exponential backoff with jitter.

BREAKING CHANGE: API timeout increased to 30s
```

```
chore(deps): upgrade Node.js to v20
```

## Validators

This project uses commitlint to validate commits:

```bash
# Install
npm install

# Validate last commit
npx commitlint --last

# Validate all commits in PR
npx commitlint --from HEAD~1 --to HEAD
```
