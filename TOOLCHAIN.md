# Toolchain Setup

Reproduces the pinned toolchain from [specs/phase-1/toolchain-baseline.md §2](specs/phase-1/toolchain-baseline.md#2-pinned-toolchain-versions) on a clean macOS checkout (TR-19). Run from the repo root unless noted.

## 1. Homebrew

If not already installed: https://brew.sh

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"   # add to ~/.zprofile for persistence
```

## 2. Node.js v22 LTS

```sh
brew install node@22
brew link --force node@22
```

## 3. Foundry v1.7.1 (forge, anvil, cast)

```sh
brew install foundry
```

## 4. circom v2.2.3

No Apple Silicon binary is published for this tag (only Linux/Windows/macOS-Intel) — build natively from source instead of relying on Rosetta:

```sh
git clone --branch v2.2.3 --depth 1 https://github.com/iden3/circom.git ~/src/circom
cargo build --release --manifest-path ~/src/circom/Cargo.toml
cp ~/src/circom/target/release/circom /opt/homebrew/bin/circom
```

Requires Rust/cargo (any recent stable toolchain — mopro's own dependency, so already required elsewhere in this project). Building circom from source needs only a stable toolchain; the *newer* toolchain requirement in §7 is specific to mopro-cli.

## 5. snarkjs v0.7.6 + circomlib (pinned commit)

Project-scoped, not global — pinned in `circuits/package.json` for reproducibility:

```sh
cd circuits
npm install
```

`circomlib` has no tagged releases, so it's pinned by commit (`35e54ea21da3e8762557234298dbb553c175ea8d`) via a `github:` dependency in `circuits/package.json`.

## 6. Verify

```sh
node -v        # v22.23.2
forge --version   # 1.7.1
anvil --version   # 1.7.1
circom --version  # circom compiler 2.2.3
cd circuits && npx snarkjs --version   # snarkjs@0.7.6
```

## 7. iOS toolchain

- **Xcode 26.3**, not the App Store default. As of this writing the App Store only offers Xcode 26.4+, which requires macOS 26.2 (Tahoe); Xcode 26.3 is the newest release that still supports macOS 15.6 (Sequoia). Download it directly from [developer.apple.com/download/all](https://developer.apple.com/download/all/) (requires a signed-in Apple ID — free tier is fine), unarchive the `.xip`, and drag `Xcode.app` into `/Applications`. Re-check this constraint before reproducing on a machine running a newer macOS — the App Store version may be usable by then.
- Accept the license and run first-launch component install (needs an interactive terminal — `xcode-select -s` alone does not do this):
  ```sh
  sudo xcodebuild -license
  sudo xcodebuild -runFirstLaunch
  ```
- **Apple Developer account** — free personal team is sufficient to start (expect the 7-day on-device resign limit during iteration). Sign in via Xcode → Settings → Accounts → "+" → Apple ID; confirm a team appears under the account.
- **CMake** (mopro-ffi build dependency):
  ```sh
  brew install cmake
  ```
- **Rust toolchain ≥ 1.85** (mopro-cli's dependency tree requires the `edition2024` Cargo feature, stabilized in 1.85; circom itself builds fine on older stable Rust, so this is specifically a mopro-cli requirement):
  ```sh
  rustup update stable
  ```
- **iOS Rust compilation targets**:
  ```sh
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim
  ```
- **mopro-cli v0.3.7**:
  ```sh
  cargo install mopro-cli --version 0.3.7
  ```
- **iPhone 14 Pro** — enable Developer Mode (Settings → Privacy & Security → scroll to Developer Mode → toggle on → restart → confirm), connect via cable, tap "Trust This Computer". Verify pairing:
  ```sh
  xcrun devicectl list devices   # should show the iPhone as "connected"
  ```
