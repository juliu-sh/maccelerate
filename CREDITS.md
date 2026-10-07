# Credits

Maccelerate is derived from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), created by jurplel. The complete original MIT license and copyright notice are preserved in [LICENSES/InstantSpaceSwitcher-MIT.txt](LICENSES/InstantSpaceSwitcher-MIT.txt).

Original Maccelerate contributions to the code, packaging, and documentation are offered under the [MIT License](LICENSE). Upstream material remains under MIT, including when modified or combined in the same source file. See [NOTICE](NOTICE) for the short attribution summary.

The Maccelerate icon was developed from Imagegen-generated design concepts; the source PNG used for packaging is in `dist/`.

The original project is independent of Maccelerate. Downloads from jurplel's Homebrew tap and GitHub releases install InstantSpaceSwitcher, not Maccelerate.

The horizontal velocity policy for macOS 27 and later uses the 9999
terminal-velocity / near-zero-progress finding from
[InstantSpaceSwitcher PR #102](https://github.com/jurplel/InstantSpaceSwitcher/pull/102),
commit `734173730fd962299ea7da1175904656c4dd82df`, by markokovac16 and
co-author maxvelkir. Maccelerate retains its own asynchronous coordinator and
uses separate preset velocities; it does not import that PR's event counter,
companion-event posting, or gesture-termination changes. The upstream MIT
license remains in `LICENSES/InstantSpaceSwitcher-MIT.txt`.

Software updates use [Sparkle](https://sparkle-project.org/), version 2.10.0. Its complete license, including bundled component notices, is preserved in [LICENSES/Sparkle.txt](LICENSES/Sparkle.txt).

The macOS 27 and later trackpad cleanup is informed by the neutral physical
terminal approach in [InstantSpaceSwitcher PR #95](https://github.com/jurplel/InstantSpaceSwitcher/pull/95),
by SimpleWood217, inspected at `ea59bcd079f875e41fb00b1ae79f38c3e3d22b0e`.
Maccelerate implements its own payload validation, request-result handling and
bounded recovery; it does not import that PR's direction or pairing changes.
The post-deserialization marker placement is also informed by
[PR #104](https://github.com/jurplel/InstantSpaceSwitcher/pull/104).
Only newly introduced neutral cleanup events carry this marker. The original
MIT license remains in `LICENSES/InstantSpaceSwitcher-MIT.txt`.
