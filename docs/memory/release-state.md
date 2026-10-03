# State of the releases

As of 2026-10-03.

- `23.1.1-anti.4` is published. Its tag names `449dca5`.
- `23.1.1-anti.5` is built and packed, not published. The recipe is `5563e5c`, the
  report `3fab8bd`. The twelve archives lie in `build/dist`. `./r` publishes them.
- `main` holds the commits of anti.4 and anti.5, none pushed to `origin/main`. `./r`
  pushes the tag alone.
- `build/dist-26b62fa` holds the archives of the first anti.4 build, unpublished.

## Open items

- Eddie decides `LIBUNWIND_ENABLE_ASSERTIONS` of the glibc libunwind. It is upstream's
  default, ON. Do not change it, and do not pin it with a test.
- After anti.5 is published, antic pins it. That covers `tools/llvm-pin` with the tag
  and six digests, and `libunwind.a` in the runtime archive. It also covers the Linux
  link of `--memory-checks` and `fast_unwind_on_fatal=1` in `MEMCHECK_OPTIONS`. Eddie
  decided these on 2026-10-03, in antic's `docs/reports/2026-10-02-vm-check.md`.
- The ASan runtimes of x86_64 Linux and x86_64 Windows are unverified on real
  hardware. The README note comes off after the first run on real x86_64.
