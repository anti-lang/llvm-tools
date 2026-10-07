# State of the releases

As of 2026-10-07.

- `23.1.1-anti.4` is published. Its tag names `449dca5`.
- `23.1.1-anti.5` is published. Its tag names `5563e5c`.
- `23.1.1-anti.6` is published. Its tag names `b9af7ef`, and antic pins it. The report
  is `docs/reports/2026-10-05-llvm-tools-profile.md`.
- `23.1.1-anti.7` is built and packed, not published. Every static musl binary asks for
  a thread stack of 8 MiB in `PT_GNU_STACK`. The recipe is `e9e1888`, and the report is
  `docs/reports/2026-10-07-llvm-tools-thread-stack.md`. The twelve archives lie in
  `build/dist`. `./r` publishes them.
- `main` holds the commits of anti.4 to anti.7, none pushed to `origin/main`. `./r`
  pushes the tag alone.
- `build/dist-26b62fa` holds the archives of the first anti.4 build, unpublished.

## Open items

- Eddie decides `LIBUNWIND_ENABLE_ASSERTIONS` of the glibc libunwind. It is upstream's
  default, ON. Do not change it, and do not pin it with a test.
- After anti.7 is published, antic moves `tools/llvm-pin` and `tools/clang-pin` to its
  tag and twelve digests.
- Eddie decides the options of the profile runtime that the anti.6 report lists under
  Choices: `COMPILER_RT_PROFILE_BAREMETAL`, `COMPILER_RT_BUILD_PROFILE_ROCM` and the
  static CRT of the Windows runtime. All keep upstream's defaults. Do not pin them with
  a test.
- The ASan runtimes of x86_64 Linux and x86_64 Windows are unverified on real
  hardware. The README note comes off after the first run on real x86_64.
