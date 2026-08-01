# Contributing

## Scope

Notchwatch supports Claude Code only. Patches adding other agents will be declined — that narrowing is the point of the fork, not an oversight.

## Build and check

Full Xcode is not required; Command Line Tools suffice. SwiftPM builds the executable, and `scripts/build-app.sh` wraps it in the `.app` bundle — SwiftPM cannot emit one.

```bash
mise install                # the pinned toolchain (SwiftLint, SwiftFormat, pre-commit)
swift build                 # must be clean before you open a PR
mise run lint               # swiftlint --strict + swiftformat --lint
mise run fmt                # rewrite formatting in place
mise run lint:repo          # shellcheck, gitleaks, YAML/JSON — via pre-commit
mise run bundle             # assemble Notchwatch.app, so you can run it for real
pre-commit install          # once per clone
```

`mise run ci` chains everything the CI workflow runs: both lint tasks, a release build, and the
bundle assembly CI gates on.

The commit hook and CI enforce the **same** rule over the **same** files: `mise run lint` across the whole tree, never a subset. A commit that touches one file is rejected for a violation in another, because the tree is clean today and any violation is therefore something this branch introduced. The hook only checks — it will not rewrite your files behind your back; run `mise run fmt` and stage the result yourself.

`mise run lint:repo` is the same pre-commit hook set CI runs, so shellcheck reaches the release scripts in CI and not only on your machine. It is deliberately not folded into `mise run lint`: pre-commit invokes `mise run lint` itself, and the two would recurse.

Two vendored files (see [License](#license)) are excluded from both tools in `.swiftlint.yml` and `.swiftformat`. They are kept diffable against their upstreams, not conformed to house style; keep the two exclusion lists in step.

Do not add SwiftUI `#Preview` blocks. The macro lives in a plugin that ships inside Xcode.app, so a preview breaks the Command Line Tools build that CI and most contributors use.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) — `type(scope): summary`. The type drives release-please, so it decides the next version and the changelog entry:

- `fix:` → patch release
- `feat:` → minor release
- `feat!:` / `BREAKING CHANGE:` in the body → major release
- `chore:`, `docs:`, `ci:`, `refactor:`, `test:` → no release

Explain why the change is needed; the diff already shows how. Never edit `CHANGELOG.md` or create tags by hand — release-please owns both.

## Sign-off (DCO)

Every commit must carry a `Signed-off-by` line certifying the [Developer Certificate of Origin](https://developercertificate.org/):

```bash
git commit --signoff
```

If you forget it on the last commit: `git commit --amend --signoff`.

## Pull requests

Branch from `main`, keep commits atomic, and give the PR a title that reads as a conventional commit — it becomes the squash-merge subject. Say what changed and why in the body; leave the line-by-line story to the diff.

## License

Contributions are accepted under the BSD 3-Clause License. Two vendored files are the exceptions, and a patch touching either one stays under that file's licence rather than yours:

- `Sources/Notchwatch/Window/CGSSpace.swift` — MPL-2.0, from [Parrot](https://github.com/avaidyam/Parrot). MPL is file-level copyleft: modifications to this file must remain available under MPL-2.0.
- `Sources/Notchwatch/Views/Notch/NotchShape.swift` — MIT under a separate copyright, from [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit). Keep the header notice.

Code inherited from the upstream project is MIT. See [LICENSE](LICENSE) for how the three-way split works.
