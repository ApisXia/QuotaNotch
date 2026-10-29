# Contributing

Issues and pull requests are welcome at <https://github.com/ApisXia/QuotaNotch>.

- **Bugs and ideas**: open an issue with the bug report or feature request form. Search existing issues first.
- **Code**: fork the repository, branch from `main`, and open a pull request against `main`. Describe the change and include a screenshot or recording for UI changes.
- **Build**: open `boringNotch.xcodeproj` in Xcode 26 and run the `boringNotch` scheme (the product is QuotaNotch.app). `swift test --parallel` runs the account-free core tests. See [docs/Guide.md](docs/Guide.md).
- **Translations**: English and Simplified Chinese live in `boringNotch/Localizable.xcstrings`. Run `python3 scripts/verify-localization.py` after editing strings.
