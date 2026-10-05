# State of the releases

As of 2026-10-05.

- `23.1.1-anti.4` is published. Its tag names `449dca5`.
- `23.1.1-anti.5` is published. Its tag names `5563e5c`, and antic pins it. The report
  is `3fab8bd`.
- `23.1.1-anti.6` is built and packed, not published. It adds `llvm-profdata` and the
  profile runtimes of the seven targets. The recipe is `b9af7ef`, and the report is
  `docs/reports/2026-10-05-llvm-tools-profile.md`. The twelve archives lie in
  `build/dist`. `./r` publishes them.
- `main` holds the commits of anti.4, anti.5 and anti.6, none pushed to `origin/main`.
  `./r` pushes the tag alone.
- `build/dist-26b62fa` holds the archives of the first anti.4 build, unpublished.

## Open items

- Eddie decides `LIBUNWIND_ENABLE_ASSERTIONS` of the glibc libunwind. It is upstream's
  default, ON. Do not change it, and do not pin it with a test.
- After anti.6 is published, antic pins it for its step `pgo`. That covers
  `tools/llvm-pin` and `tools/clang-pin` with the tag and twelve digests,
  `llvm-profdata` in `tools/get-llvm.cmake`, `tools/check-llvm.cmake` and
  `pinned_tools`, and the profile runtimes in the runtime archive.
- Eddie decides the options of the profile runtime that the anti.6 report lists under
  Choices: `COMPILER_RT_PROFILE_BAREMETAL`, `COMPILER_RT_BUILD_PROFILE_ROCM` and the
  static CRT of the Windows runtime. All keep upstream's defaults. Do not pin them with
  a test.
- The ASan runtimes of x86_64 Linux and x86_64 Windows are unverified on real
  hardware. The README note comes off after the first run on real x86_64.
