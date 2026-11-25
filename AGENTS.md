# dji-mic-control

Linux-first desktop controller for DJI wireless microphones (DJI Mic Mini, DJI Mic Mini 2 transmitters, and DJI Mic Series Mobile Receiver), built on core Flutter and Dart libraries with zero third-party native Flutter plugins.

## Origin, License, and Upstream Attribution

- **License:** MIT ([LICENSE](LICENSE), Copyright (c) 2026 Chris Coetzee).
- **Upstream origin:** Ported from [ShadowBitBasher/DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control) (`v1.1.0`, commit `9ba7688`), originally dedicated to the public domain under The Unlicense. All DUML v1/v2 wire protocol reverse-engineering, UI design concepts, and original device PNG artwork originate from **ShadowBitBasher**.
- **Upstream PR ports:** Mobile Receiver identification, `Receiver Gain` / `Monitoring Gain` controls, and Simplified Chinese (`zh-CN`) UI localization originate from **VaderCheng** ([PR #3](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/3), [PR #4](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/4)).
- Always preserve upstream author attribution in `README.md`, `LICENSE`, `CHANGELOG.md`, and relevant file headers when porting additional upstream protocol or UI work.

## Layout

- `lib/protocol/`: Pure Dart DUML v1/v2 framing, CRC-16, and `MicMiniModel` (zero Flutter or FFI imports).
- `lib/transport/`: `UsbTransport` seam, `DeviceManager`, pure-Dart Linux `sysfs` + `usbfs` transport (`linux_usbfs_transport.dart`, default), and optional `nusb` FFI adapter (`nusb_ffi_transport.dart`).
- `lib/platform/`: Zero-plugin OS integrations (runtime capability probes, D-Bus wire client, notifications, tray, autostart, single-instance lock, config store, `pkexec` udev installer).
- `lib/l10n/`: Pure Dart `AppStrings` localization (`en` and `zh-CN`).
- `lib/sim/`: Byte-level DUML hardware simulator and `--demo` fixture.
- `lib/state/`: `AppServices` and `MicController` (`ChangeNotifier`).
- `lib/ui/`: Pure Flutter desktop UI, Diagnostics fold, Pending Operations strip, and modals.
- `native/dji_mic_usb/`: Optional thin Rust `nusb` `cdylib` (not required for Linux pure-Dart `usbfs` builds).
- `packaging/`: `60-dji-mic.rules` and `dji-mic-control.desktop`.
- `tool/`: Deterministic build (`build_linux.sh`) and Linux packaging (`package_linux.sh` for `.tar.gz`, `.deb`, `.rpm`, `.AppImage`) scripts.
- `scripts/`: Repo checks (git hooks + agent PreToolUse hooks) and release helper (`prepare_release.rb`), each with a sibling `test_<script>.rb` minitest suite.
- `docs/`: Feasibility analysis, specification, plan, and decision log (`docs/log.d/`).

## Setup and Checks

- Install git hooks with `lefthook install` (`lefthook.yml`). Never bypass with `--no-verify`.
- Run all Dart/Flutter checks: `flutter analyze && flutter test`.
- Run desktop integration test on Linux: `xvfb-run -a flutter test integration_test/app_desktop_test.dart -d linux`.
- Run all Ruby hook/release script tests: `for t in scripts/test_*.rb; do ruby "$t"; done`.

## Testing: Red-Green TDD, Always

- Write the failing test first, watch it fail, make it pass, then refactor.
- Every Ruby script in `scripts/` needs a sibling `test_<script>.rb` using Ruby 3 stdlib minitest (`test "..." do ... end` DSL; no gems, no Gemfile).
- Expose script logic as classes/modules and guard CLI entry with `if $PROGRAM_NAME == __FILE__`.
- Include the MIT header in every source file and script: copyright line, `SPDX-License-Identifier: MIT`, and pointer to `LICENSE`.

### Codify What Repeats

- Repeated build, packaging, check, or release steps become deterministic scripts with pinned versions, clear exit codes, and `--help`, `--debug`, and `--dry-run` (for state-changing scripts) flags.

## Naming and Writing

- **Branches:** slash-separated kebab-case (`feat/gain-sliders`, `fix/usbfs-write`), enforced by `scripts/check_branch_name.rb`.
- **No em-dashes:** Never use em-dashes in prose, code comments, commit messages, HTML entities, or `\u` escapes for U+2014. Enforced by `scripts/check_em_dashes.rb`.
- Use plain prose, headings, lists, and tables.

## Commits and Attribution

Enforced by `scripts/check_commit_message.rb` (commit-msg hook).

### Conventional Commits

- Subject: `type(scope): description` (optional scope; `!` before `:` for breaking changes).
- Types: `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `build`, `ci`, `perf`, `style`, `revert`.
- Scope: kebab-case.
- Description: lowercase start, no trailing period, total subject <=72 chars.
- Optional body: blank line after subject; explains what and why.

### Commit Attribution Approach

- AI tools are tools driven by human instruction, not authors or co-authors.
- Author every commit as the repo owner: `Chris Coetzee <chriscz93@gmail.com>`.
- Reserve `Co-Authored-By` trailers for human co-authors only; do not list AI models or tools as author or `Co-Authored-By`.
- Set local identity first (`git config --local user.name` and `git config --local user.email`). PreToolUse hook `scripts/check_claude_identity.rb` (`.claude/settings.json` and `.agents/hooks.json`) prevents committing under an AI identity or adding an AI `Co-Authored-By` trailer.
- Transparently record AI tool assistance at the end of each commit with two kebab-case trailers:
  - `Assisted-by-AI-model: <kebab-case-model>`
  - `Assisted-by-AI-harness: <kebab-case-harness>`

### Pull Requests

- Update PRs by rebasing onto `main` and force-pushing with `--force-with-lease`. Never merge `main` into a branch.

## Privacy and Outbound Requests

- Never send the owner's or any email address to external services (User-Agent, request header, URL, query string, or search).
- If a site requires a client identity, send only `Unknown Bobtronic Research` without any email address.
- PreToolUse hook `scripts/check_outbound_email.rb` (`.claude/settings.json` and `.agents/hooks.json`) blocks outbound calls containing an email. Do not work around it.
