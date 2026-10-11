/* The program that the recipe compiles with the release clang, instrumented
   for coverage, and runs. llvm-profdata of a host merges the profile of
   that run, and llvm-cov report of the host counts the lines. The two
   functions span 14 lines. sum(10) is 45, so the run never reaches the two
   lines of the branch in main. coverage_lines and coverage_missed_lines of
   build-llvm.cmake hold both counts, and a change here changes them. */
#include <stdio.h>

static int sum(int n) {
    int total = 0;
    for (int i = 0; i < n; i++) {
        total += i;
    }
    return total;
}

int main(void) {
    puts("Hello, world!");
    if (sum(10) != 45) {
        return 1;
    }
    return 0;
}
