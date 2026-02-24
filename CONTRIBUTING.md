# Contributing to CSF

This repository is a community-maintained fork focused on keeping CSF secure, stable, and compatible with modern Linux systems.

## Ground Rules

- Keep changes focused and minimal.
- Prefer backward-compatible behavior unless a breaking change is necessary and agreed by the community.
- For security issues, **do not open a public issue**. See [SECURITY.md](SECURITY.md).

## Development Workflow

1. Fork the repository and create a feature branch from `main`.
2. Make your changes in small, reviewable commits.
3. Open a Pull Request with clear context:
   - what changed
   - why it changed
   - how it was tested

## Testing

Before opening a PR, validate as much as possible:

- syntax and path sanity of changed shell scripts
- installer flow on at least one Debian/Ubuntu and one RHEL/Alma-based environment
- CSF install output and basic checks (`csf -v`, `csftest.pl`)

CI exists, but local/reproducible validation is still strongly encouraged.

## Pull Request Checklist

- [ ] Change is scoped and documented
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