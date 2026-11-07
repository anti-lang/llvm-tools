# State of the releases

As of 2026-11-07.

- `23.1.1-anti.4` is published. Its tag names `449dca5`.
- `23.1.1-anti.5` is published. Its tag names `5563e5c`.
- `23.1.1-anti.6` is published. Its tag names `b9af7ef`. The report is
  `docs/reports/2026-10-05-llvm-tools-profile.md`.
- `23.1.1-anti.7` is published, on 2026-10-07. Its tag names `e9e1888`, and antic pins
  it. Every static musl binary asks for a thread stack of 8 MiB in `PT_GNU_STACK`. The
  report is `docs/reports/2026-10-07-llvm-tools-thread-stack.md`.
- `23.1.1-anti.8` is published, on 2026-10-11. Its tag names `b0ef666`, and antic pins
  it. It adds `llvm-cov` to the tools archives. The report is
  `docs/reports/2026-10-11-llvm-tools-cov.md`.
- `23.1.1-anti.9` is neither built in full nor published. Its recipe adds `llvm-objcopy`,
  `llvm-strip` and `dsymutil` to the tools archives, for antic's T211, and
  `pins/build-number` is 9. Eddie decides the release.
- `origin/main` stands at `b0ef666`. The recipe commits of anti.9 are local and not
  pushed. `./r` pushes the tag alone, so push `main` after each release as well.
- `build/dist-26b62fa` holds the archives of the first anti.4 build, unpublished.

## Open items

- Eddie decides `LIBUNWIND_ENABLE_ASSERTIONS` of the glibc libunwind. It is upstream's
  default, ON. Do not change it, and do not pin it with a test.
- After anti.7 is published, antic moves `tools/llvm-pin` and `tools/clang-pin` to its
  tag and twelve digests.
- antic fetches `llvm-cov` of anti.8 for its coverage measurement and keeps it out of
  the Anti package.
- Eddie decides the options of the profile runtime that the anti.6 report lists under
  Choices: `COMPILER_RT_PROFILE_BAREMETAL`, `COMPILER_RT_BUILD_PROFILE_ROCM` and the
  static CRT of the Windows runtime. All keep upstream's defaults. Do not pin them with
  a test.
- The ASan runtimes of x86_64 Linux and x86_64 Windows are unverified on real
  hardware. The README note comes off after the first run on real x86_64.
