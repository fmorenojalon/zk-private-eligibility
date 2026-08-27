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

Requires Rust/cargo (any recent stable toolchain — mopro's own dependency, so already required elsewhere in this project).

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

## 7. iOS toolchain (F1.1 — blocked, not yet done on this machine)

- **Full Xcode** (not just Command Line Tools) — install from the App Store, then `sudo xcode-select -s /Applications/Xcode.app`.
- **Apple Developer account** — free personal team is sufficient to start; sign in via Xcode → Settings → Accounts.
- **mopro-cli v0.3.7** — `cargo install mopro-cli --version 0.3.7` (or per mopro's own install docs) once Xcode is in place.
- **iPhone 14 Pro** — enable Developer Mode (Settings → Privacy & Security → Developer Mode) and trust this Mac when connected.
