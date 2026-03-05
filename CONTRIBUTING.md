# Contributing to CSF

This repository is a community-maintained fork focused on keeping CSF secure, stable, and compatible with modern Linux systems.

## Ground Rules

- Keep changes focused and minimal.
- Prefer backward-compatible behavior unless a breaking change is necessary and agreed by the community.
- For security issues, **do not open a public issue**. See [SECURITY.md](SECURITY.md).

## Before You Start

1. Check existing issues/PRs to avoid duplicate work.
2. For larger changes, discuss approach in an issue first.
3. Keep PRs small and reviewable.

## Branching Model (Single-Main)

We use a single-main workflow:

- `main` → stable + integration branch
- `feature/*`, `fix/*`, `chore/*` → short-lived branches from `main`
- `hotfix/*` → urgent production fix branch from `main`

📘 Full guide with examples: [CSF Wiki: Contributing](https://github.com/Black-HOST/csf/wiki/Contributing)

### Default PR target

- **All contributor PRs target `main`**.

### Releases

- Releases are done by maintainers only, from `main`.
- Contributors should not create release branches.
- PRs that modify `version.txt` are rejected for now (maintainers-only change).

## Development Workflow

1. Sync your base branch (`main`).
2. Create a branch with one of these formats:
   - `feature/<issue-id>-<short-description>`
   - `fix/<issue-id>-<short-description>`
   - `chore/<short-description>`
   - `hotfix/<version>-<short-description>`
3. Commit in small, logical steps.
4. Push branch and open PR with clear context:
   - what changed
   - why it changed
   - how it was tested

## Testing

Before opening a PR, validate as much as possible:

- syntax and path sanity of changed shell scripts
- installer flow on at least one Debian/Ubuntu and one RHEL/Alma-based environment
- CSF install output and basic checks (`csf -v`, `csftest.pl`)

CI exists, but local/reproducible validation is strongly encouraged.

## Pull Request Checklist

- [ ] Change is scoped and documented
- [ ] Target branch is `main`
- [ ] Paths updated consistently across installer scripts
- [ ] No secrets, tokens, or private material committed
- [ ] Security-sensitive behavior explained
- [ ] Testing notes included in PR description

## Coding Style

- Keep shell scripts POSIX-friendly where practical
- Use consistent formatting with surrounding code
- Avoid unrelated refactors in the same PR

## License

By contributing, you agree that your contributions are licensed under the same license as this project (GPLv3).

Thanks for helping improve CSF ❤️
