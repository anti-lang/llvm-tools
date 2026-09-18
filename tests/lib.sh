# Helpers that every test under tests/ sources.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-test.XXXXXX")
# A test sets finished=yes on its last line. An exit before it is a failure
# even when the status is 0, which bash 3.2 reports after a failed "." command.
finished=no
trap 'status=$?; rm -rf "$work"; [ "$finished" = yes ] || status=1; exit $status' EXIT

fail() {
    printf 'FAIL %s: %s\n' "$(basename "$0")" "$*" >&2
    exit 1
}

# Run the recipe with the -D options given, from the checkout in $1.
recipe() {
    checkout=$1
    shift
    cmake "$@" -P "$checkout/build-llvm.cmake"
}

# Print the value of <key> from the paths step of the recipe for <host>.
recipe_path() {
    recipe "$1" -DHOST="$2" -DSTEP=paths | sed -n "s/^$3=//p"
}

# Expect the command to fail and its output to hold the text in $1.
expect_refusal() {
    text=$1
    shift
    if output=$("$@" 2>&1); then
        fail "expected a refusal holding '$text', and the command passed"
    fi
    case $output in
        *"$text"*) ;;
        *) fail "expected '$text' in the refusal, got: $output" ;;
    esac
}

# Copy the files of the repository into a fresh git checkout under $work,
# with one commit, and print its path.
checkout_copy() {
    copy="$work/checkout"
    mkdir -p "$copy"
    (cd "$root" && git ls-files -co --exclude-standard) | while read -r path; do
        mkdir -p "$copy/$(dirname "$path")"
        cp -p "$root/$path" "$copy/$path"
    done
    git -C "$copy" init -q -b main
    git -C "$copy" add -A
    git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
        commit -q -m "Test checkout"
    printf '%s\n' "$copy"
}

# The clang and the tools of the unpacked release of this machine.
release_bin() {
    bin=$(recipe_path "$root" macos-arm64 release)
    if [ ! -x "$bin/clang" ]; then
        fail "$bin/clang is missing. Run the recipe once to unpack the release."
    fi
    printf '%s\n' "$bin"
}
