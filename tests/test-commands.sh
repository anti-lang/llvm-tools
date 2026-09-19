#!/bin/sh
# ./c builds the builtins and every host of hosts.toml, with the machines of
# the version checks and the Microsoft licence terms accepted. ./r packs
# each host that is not packed from its build yet, then runs
# scripts/release.sh. Stand-ins for the scripts record each call.
. "$(dirname "$0")/lib.sh"

copy=$(checkout_copy)
hosts=$(sed -n 's/^\[\(.*\)\]$/\1/p' "$copy/hosts.toml")
calls="$work/calls"
# The stand-in of build.sh also records the settings of the recipe.
for script in build pack release; do
    record=""
    [ "$script" = build ] &&
        record='"${LINUX_REMOTE:-}" "${WINDOWS_REMOTE:-}" "${ACCEPT_LICENSE:-}"'
    cat > "$copy/scripts/$script.sh" <<STUB
#!/bin/sh
echo $script "\$@" $record >> "$calls"
[ -z "\${FAIL_ON:-}" ] || [ "\$*" != "\$FAIL_ON" ]
STUB
    chmod +x "$copy/scripts/$script.sh"
done

expect_refusal usage "$copy/c" macos-arm64
expect_refusal usage "$copy/r" now

# ./c builds the builtins first, then each host in the order of hosts.toml.
: > "$calls"
"$copy/c" >/dev/null
expected="build builtins eddie@192.168.60.131 eddie@192.168.60.132 yes"
for host in $hosts; do
    expected="$expected
build $host eddie@192.168.60.131 eddie@192.168.60.132 yes"
done
[ "$(cat "$calls")" = "$expected" ] || fail "./c called: $(cat "$calls")"

# LINUX_REMOTE and WINDOWS_REMOTE name other machines.
: > "$calls"
LINUX_REMOTE=a@linux WINDOWS_REMOTE=b@windows "$copy/c" >/dev/null
[ "$(sed -n 1p "$calls")" = "build builtins a@linux b@windows yes" ] ||
    fail "./c ignored LINUX_REMOTE and WINDOWS_REMOTE: $(cat "$calls")"

# A failed build stops ./c.
: > "$calls"
expect_refusal "" env FAIL_ON=linux-arm64 "$copy/c"
[ "$(tail -n 1 "$calls" | cut -d ' ' -f 2)" = linux-arm64 ] ||
    fail "./c went on after a failed build: $(cat "$calls")"

# Write a stamp of the build of <host> from commit $3. Unless $2 is empty,
# also write its archives into dist, each with a VERSION that names $2.
tag=$(common_value "$copy" tag)
dist=$(recipe_path "$copy" linux-x86_64 dist)
mkdir -p "$dist" "$work/stage"
built() {
    stamp=$(recipe_path "$copy" "$1" stamp)
    mkdir -p "$(dirname "$stamp")"
    printf 'llvm=%s\ncommit=%s\nclean=yes\n' "$(cat "$copy/pins/llvm-version")" \
        "$3" > "$stamp"
    [ -n "$2" ] || return 0
    printf 'recipe %s\n' "$2" > "$work/stage/VERSION"
    for kind in llvm-tools clang; do
        tar -cJf "$dist/$kind-$tag-$1.tar.xz" -C "$work/stage" VERSION
    done
}

# ./r leaves alone a host whose archives come from its build, and packs
# every other host before the release.
built macos-arm64 1111111 1111111
built linux-x86_64 2222222 3333333
built windows-arm64 "" 4444444
: > "$calls"
"$copy/r" >/dev/null || fail "./r failed: $(cat "$calls")"
expected=""
for host in $hosts; do
    [ "$host" = macos-arm64 ] || expected="$expected${expected:+
}pack $host"
done
expected="$expected
release"
[ "$(cat "$calls")" = "$expected" ] || fail "./r called: $(cat "$calls")"

# A host that fails to pack stops ./r before the release.
: > "$calls"
expect_refusal "" env FAIL_ON=linux-arm64 "$copy/r"
if grep -q '^release' "$calls"; then
    fail "./r released after a failed pack: $(cat "$calls")"
fi
finished=yes
