# iOS AirPlay Receiver Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline. The user explicitly requested starting code after approving the spec; proceed without another approval handoff.

**Goal:** Build the iOS receiver and unsigned IPA pipeline, preserving the full AirPlay 2 goal and reporting real device gates separately.

**Architecture:** Embed the UxPlay C core behind an Objective-C++ adapter and use native iOS media output. Add portable packet/clock primitives and a real PTP socket diagnostic before integrating the AirPlay 2 audio backend. Do not advertise unimplemented AirPlay 2 features.

**Tech Stack:** SwiftUI, Objective-C++, C++17, C, VideoToolbox/AVFoundation/AudioToolbox, CMake, Python 3, XcodeGen, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-ios-airplay-receiver-design.md`

## Global Constraints

- iOS/iPadOS 16+, iphoneos arm64; no App Store distribution.
- Private APIs are allowed but do not imply available entitlements or jailbreak.
- Pin upstream sources; retain copyright and license notices.
- Build unsigned IPA without signing credentials; device installation requires re-signing.
- All receiver features remain targets; incomplete functions must not be advertised as implemented.

## Review Focus

- Stop/restart during callbacks: release resources after producers stop; reject queued stale frames.
- Corrupt video input: reject malformed NAL units without allocation based on untrusted lengths.
- Permission denial / port conflict: fail with actionable status and close partially opened sockets.
- Slow UI or media output: enforce queue bounds rather than accumulate latency and memory.
- Packaging wrong-platform code: reject simulator/non-arm64 output before upload.

## Files and interfaces

- `Core/MediaPacket.hpp`, `Core/Clock.hpp`, `Core/PTPProbe.*`: portable parsing and timing/diagnostic logic.
- `Tests/core_tests.cpp`, `Tests/test_package.py`: malformed packet, clock, socket cleanup and IPA tests.
- `Receiver/Bridge/ReceiverEngine.*`: start/stop and owned callback data, `ReceiverEngineDelegate` events.
- `Receiver/Media/VideoRenderer.*`, `Receiver/Media/AudioRenderer.*`: native media output.
- `Receiver/App/*.swift`, `Receiver/Info.plist`: UI, receiver identity, lifecycle and permissions.
- `CMakeLists.txt`, `project.yml`, `scripts/*.py`, `scripts/*.sh`: reproducible sources, build, package.
- `.github/workflows/build.yml`: Linux checks and macOS iOS build.
- `docs/compatibility.md`, `docs/development.md`: measured status and reproducible device tests.

## Task 1: Source lock and portable safety primitives

- [ ] Pin UxPlay and its build dependencies in `dependencies.lock.json`; record the inspected Shairport/NQPTP revisions separately.
- [ ] Write tests first: Annex B SPS/PPS/frame splitting, invalid/truncated input, bounded size, timestamp conversion, PTP occupied second port cleanup.
- [ ] Run `cmake -S . -B build/tests && cmake --build build/tests && ctest --test-dir build/tests --output-on-failure`; observe missing implementations, then implement and rerun.
- [ ] Keep lifecycle probe independent of PTP synchronization: successful bind is not synchronized playback.

## Task 2: Native receiver and application

- [ ] Wire UxPlay `raop_callbacks_t` through an Objective-C++ engine; preserve stable identity/key storage, use callback-owned data copies, serialize start/stop.
- [ ] Implement Annex B to sample-buffer video with parameter set changes; implement ALAC/AAC/AAC-ELD audio decoding and bounded scheduled playback.
- [ ] Surface port probe errors and receiver failures in SwiftUI; add controls, full-screen video, PIN, persistent name, and background/foreground handling.
- [ ] Add device/simulator XCTest coverage for native parsing/format setup and run from macOS CI. Linux cannot claim iOS framework compilation.

## Task 3: Reproducible iOS build and unsigned IPA

- [ ] Add pinned dependency fetch with hash verification, static iOS dependency builds and an XcodeGen project.
- [ ] Write Python packaging tests using real temporary app bundles; verify rejection of missing executable, wrong platform/architecture, existing signing material, and unsafe symlinks.
- [ ] Implement packaging with a `Payload` layout and round-trip validation; run `python3 -m unittest discover -s Tests -p 'test_*.py'`.
- [ ] Add macOS Actions build, simulator tests, artifact validation/upload and dependency manifest/licenses.

## Task 4: AirPlay 2 feasibility and integration boundary

- [ ] Record concrete upstream dependencies, same-IP service conflicts and iOS PTP requirements in `docs/compatibility.md`.
- [ ] Run the embedded port probe on an actual signed iOS device before asserting transport feasibility. If no device is available, leave this gate explicitly pending rather than claim an audio backend is finished.
- [ ] Integrate Shairport lifecycle, pair setup, realtime/buffered transport, NQPTP timing and native output once the device gate is established; never substitute a dummy backend or set feature bits to imply this exists.
- [ ] Measure external-receiver output synchronization, pairing persistence and group join/leave against the spec's device matrix.

## Task 5: Review and handoff

- [ ] Run the complete available portable tests, packaging tests, shell syntax checks and `git diff --check`.
- [ ] Request an independent whole-change review per executing-plans; fix important findings and rerun relevant checks.
- [ ] Document actual build/test evidence and pending device work in the README and compatibility matrix.

## Execution ledger

- Initial repository contained only a README and approved specification; there was no baseline test suite.
- User explicitly directed code creation; plan review handoff is superseded by that instruction.
- Work occurs in the existing workspace on `feat/ios-airplay-receiver`; no secondary worktree required for this otherwise empty project.
- Tasks 1–3 share portable media types and the dependency lock; Task 4 must not advertise capabilities before the runtime integration is implemented.
