# Contributing to ClipNest

Bug reports, focused fixes, localization improvements, and documentation corrections are welcome. For a larger feature or architecture change, open an issue describing the user problem before starting implementation.

## Report a problem

Use [GitHub Issues](https://github.com/Kryptonzy/ClipNest/issues) for ordinary bugs. Include the macOS version, Mac architecture, app build or commit, steps to reproduce, and expected versus actual behavior. For build failures, also include the Xcode and Swift versions.

Use synthetic clipboard examples. Remove personal data from screenshots and logs; never attach your clipboard history, backups, encryption keys, passwords, or signing credentials. Report suspected security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Make a change

1. Fork the repository and create a branch for one focused change.
2. Follow [BUILDING.md](docs/BUILDING.md) to build and run the existing checks.
3. Add a regression test for a behavior change. Use temporary test storage, not your live history.
4. Keep English and Simplified Chinese strings in sync and run the localization checker.
5. In the pull request, explain the user-visible change, tests run, and any checks you could not perform. Include screenshots only when they help review a UI change.

Changes to capture, paste, permissions, or privacy need the relevant manual checks in addition to automated tests. Do not add telemetry, a network service, or a third-party dependency without discussing the need and privacy implications first.

Keep generated builds and local data out of commits. Include only code and assets you have permission to contribute, and preserve any required third-party notices. Contributions are licensed under the project's [MIT license](LICENSE).
