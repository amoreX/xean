## Summary

What does this change do, and why?

## Scope

- [ ] Bug fix
- [ ] UI or behavior change
- [ ] Cleanup policy, deletion, or scan caching
- [ ] Documentation
- [ ] Tests
- [ ] Build, release, or packaging

## Checks

- [ ] I kept the PR focused on one change.
- [ ] I ran the relevant checks and listed the results (or explained what could not be run).
- [ ] For UI changes: I attached before/after screenshots made with synthetic data
      (`BLITZCLEAN_DESIGN_DIR=artifacts/cleaner swift test --filter CleanerRenderTests`), checked the running app,
      and followed `docs/DESIGN.md`.
- [ ] For cleanup or scan changes: I added tests against disposable fixtures and kept the safety rules in
      `CONTRIBUTING.md`.
- [ ] I did not include secrets, private paths, process command lines, or personal data.

## Notes

Larger changes should start with a draft PR describing the proposed scope.
