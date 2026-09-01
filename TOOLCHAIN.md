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

Requires Rust/cargo (any recent stable toolchain — mopro's own dependency, so already required elsewhere in this project). Building circom from source needs only a stable toolchain; the *newer* toolchain requirement in §8 is specific to mopro-cli.

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

## 7. Why mopro? Rationale for the native-binding stack

Desktop (§1–§6) and iOS (§8) need fundamentally different proving stacks, not just different install commands. Worth understanding why before the §8/§9 steps read as arbitrary.

**What proving requires, mechanically.** Two things: (1) witness generation — execute the circuit's arithmetic to compute every wire value satisfying the constraints; (2) proving — run Groth16 (elliptic-curve scalar multiplications, FFTs) over that witness plus the proving key. Both are just computation; what differs is what's allowed to run that computation.

**Desktop never compiles an app.** `circom`, `node`, `snarkjs` run directly as command-line tools. `circom` compiles the circuit to `circuit.wasm`; `node` executes that WASM in its built-in runtime for witness generation; `snarkjs` (plain JS, using `ffjavascript` for field/curve math) does the proving. Node.js is already a native macOS program with a WASM runtime and JS engine built in — nothing needs packaging or shipping.

**iOS ships one compiled, sandboxed binary — no scripts, no Node.js inside it.** Whatever the app does at runtime has to already be compiled machine code linked into that binary before it ships. So the same two jobs need a completely different path:
- **Witness generation:** instead of interpreting the circuit's WASM at runtime (too slow on a phone), mopro's `rust-witness` component transpiles that WASM into native Rust/C code *at build time* (via `w2c2`, a WASM→C compiler) — producing a real compiled static library, not an interpreter. This is the `libcircuit.a` referenced in §9's underscore-naming gotcha.
- **Proving:** instead of snarkjs's JS implementation, mopro uses `arkworks`, a mature Rust cryptography library, compiled natively for `aarch64-apple-ios`.

Both end up as real ARM64 machine code inside the app binary — that's "native."

**"Native bindings" ≠ "Swift bindings."** The native part is the compiled Rust library. But Swift can't call Rust functions directly (different calling conventions, different memory models) — a bridge is needed. Mopro generates that bridge with **UniFFI** (Mozilla's cross-language binding generator): it reads annotated Rust functions and emits the Swift-side wrapper code that calls into the compiled Rust library through a C-compatible interface. That generated wrapper is `MoproiOSBindings/mopro.swift` — the `generateCircomProof`/`verifyCircomProof` functions used in `ContentView.swift`. So: *native binding* = compiled Rust + the generated cross-language glue, for whichever target platform; *Swift bindings* = specifically the Swift half of that (same UniFFI generator produces Kotlin for Android, etc. — one Rust core, many generated language-specific skins).

**What mopro actually is.** Not the prover itself — arkworks and rust-witness do the real cryptographic work. Mopro is the orchestration layer: wraps several proving backends (circom, halo2, noir, gnark) behind one Rust API, drives `rust-witness`'s WASM→native transpilation, runs UniFFI to generate per-platform bindings, and scaffolds the whole Xcode project (`mopro init/build/create`) so cross-compilation targets, module maps, and xcframework packaging aren't hand-configured. We hit real friction even *with* this automation (§9) — doing it by hand would mean re-deriving most of what mopro already does.

**Could this be built without mopro?** Yes, in principle — the underlying constraint (some compiled, native way to run Groth16 proving on iOS, exposed to Swift) is real and unavoidable, but mopro specifically is a choice, not a hard requirement:
- Hand-roll a thin Rust crate calling arkworks directly, wire up UniFFI (or Apple's native C-interop) manually, hand-configure the Xcode build — essentially rebuilding a slice of mopro ourselves.
- Skip Rust entirely and embed a WASM runtime in the app (Wasmer/Wasmtime, or JavaScriptCore running snarkjs-equivalent logic) — avoids Rust/Cargo, but gives up the performance win `rust-witness`'s native transpilation specifically exists to capture.
- Link a C++ prover (e.g. `rapidsnark`) directly via Xcode's native C++ interop, no Rust at all — still real cross-compilation/linking work mopro currently absorbs.

PRD §9.2 names mopro deliberately, and R3 ("no novel cryptography, use existing libraries") is the explicit reasoning — avoid reinventing this. Rust/Cargo showing up as a dependency (§8 below) is the direct consequence: mopro's core is Rust, so anything touching it needs the Rust toolchain present. The chain: Cargo → mopro-cli (`cargo install`) → the Rust crate mopro scaffolds → `cargo build --target aarch64-apple-ios` (invoked internally by `mopro build`) → the compiled xcframework → Xcode links it into the Swift app.

## 8. iOS toolchain

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

## 9. Building an F1.1-style mopro app for a physical device (gotchas)

Getting `holder-app-ios/mopro-baseline` running natively on the iPhone surfaced several non-obvious issues, recorded here so a clean checkout doesn't have to rediscover them:

- **`mopro build` / `mopro create` hang forever with no output in a non-interactive shell.** Their default flow shows an arrow-key menu (build mode, platform, architecture); with no real TTY attached, the menu redraws in an infinite loop burning 100% CPU while never receiving input — it is not "just slow." Always pass the flags that skip the prompts:
  ```sh
  mopro build --mode release --platforms ios --architectures aarch64-apple-ios aarch64-apple-ios-sim --no-auto-update
  mopro create --framework ios
  ```
  If a `mopro` process is pinned at ~100% CPU with near-zero memory and no `cargo`/`rustc` children, it's stuck in this loop, not building — kill it and re-run with explicit flags.
- **Circuit identifiers passed to `rust_witness::witness!(...)` must not contain underscores.** `w2c2` (used internally to transpile the circuit's `.wasm` to native code) sanitizes the wasm module name by stripping underscores when generating C symbol names, but `rust_witness`'s macro does not apply the same sanitization to the `extern "C"` bindings it generates. An underscored name (e.g. `poseidon_baseline`) produces a link-time "Undefined symbols" error (`_poseidon_baselineFreeInstance` expected vs. `_poseidonbaselineFreeInstance` actually generated) — not a compile error, so it's easy to misdiagnose. Name circuit `.wasm`/`.zkey` files without underscores (e.g. `poseidonbaseline.wasm`).
- **`mopro create`'s default bundle identifier (`mopro.MoproApp`) is not available** on a fresh account/team — registering it fails with "Failed Registering Bundle Identifier." Change `PRODUCT_BUNDLE_IDENTIFIER` to a unique reverse-DNS string (e.g. `com.<you>.<project>.MoproApp`) for all three targets (`MoproApp`, `MoproAppTests`, `MoproAppUITests`).
- **`DEVELOPMENT_TEAM` must be set for all three targets, not just the main app.** Selecting a team in Xcode's Signing & Capabilities UI only sets it for the target you were viewing (`MoproApp`); `MoproAppTests` and `MoproAppUITests` need the same `DEVELOPMENT_TEAM` value in `project.pbxproj` or `xcodebuild test` fails with the same "requires a development team" error even though the app itself builds fine.
- **A fresh Xcode install may be missing the iOS platform matching the device's exact OS version**, failing with `iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components.` even though the Xcode version itself supports newer iOS. Fetch it from the command line instead of the GUI:
  ```sh
  xcodebuild -downloadPlatform iOS
  ```
- **`xcrun devicectl list devices` and `xcodebuild -destination` use different device identifier namespaces.** `devicectl` reports a CoreDevice UUID; `xcodebuild`/`xctrace` want the classic UDID-style identifier. Get the right one with:
  ```sh
  xcrun xctrace list devices   # use this ID for `xcodebuild -destination "id=..."`
  ```
- **First launch of a personal-team-signed app requires manually trusting the developer certificate on the device itself** — Settings → General → VPN & Device Management → select the developer profile → Trust. No command-line bypass; this is a one-time step per device per Apple ID.
- **Running `xcodebuild test -only-testing:...` is a reliable way to verify on-device proving without manual interaction** — it launches the app, drives the UI (tap buttons, wait for expected text), and reports pass/fail, which is more verifiable than asking someone to eyeball the phone screen.
