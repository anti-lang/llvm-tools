#!/bin/sh
# The recipe and the scripts read hosts.toml with two readers, one in CMake
# and one in shell. Both must see the same hosts, fields and tools.
. "$(dirname "$0")/lib.sh"
. "$root/scripts/common.sh"

cmake_hosts=$(recipe "$root" -DSTEP=hosts)
shell_hosts=$(toml_sections "$root/hosts.toml")
[ "$cmake_hosts" = "$shell_hosts" ] ||
    fail "the readers disagree on the hosts: '$cmake_hosts' and '$shell_hosts'"
[ "$(printf '%s\n' "$shell_hosts" | wc -l | tr -d ' ')" = 6 ] ||
    fail "hosts.toml names $(printf '%s\n' "$shell_hosts" | wc -l) hosts, not 6"

cmake_tools=$(recipe "$root" -DSTEP=tools)
shell_tools=$(toml_get "$root/hosts.toml" "" tools)
[ "$cmake_tools" = "$shell_tools" ] ||
    fail "the readers disagree on the tools: '$cmake_tools' and '$shell_tools'"
[ "$shell_tools" = "$(printf 'lld\nllvm-mc\nllvm-ar\nllvm-objdump\nllvm-readobj')" ] ||
    fail "hosts.toml names the tools '$shell_tools'"

# The compiler goes into an archive of its own, and the recipe checks it
# as it checks the tools.
cmake_compiler=$(recipe "$root" -DSTEP=compiler)
shell_compiler=$(toml_get "$root/hosts.toml" "" compiler)
[ "$cmake_compiler" = "$shell_compiler" ] ||
    fail "the readers disagree on the compiler: '$cmake_compiler' and '$shell_compiler'"
[ "$shell_compiler" = clang ] || fail "hosts.toml names the compiler '$shell_compiler'"

# A macOS host names its deployment target once, and no flag spells it.
for host in macos-arm64 macos-x86_64; do
    [ "$(toml_get "$root/hosts.toml" "$host" deployment-target)" = 11.0 ] ||
        fail "$host has no deployment target of 11.0"
    if toml_get "$root/hosts.toml" "$host" flags | grep -q DEPLOYMENT_TARGET; then
        fail "the flags of $host spell the deployment target a second time"
    fi
done

for host in $shell_hosts; do
    info=$(recipe "$root" -DHOST="$host" -DSTEP=host-info)
    for key in triple built-on sysroot; do
        from_cmake=$(printf '%s\n' "$info" | sed -n "s/^$key=//p")
        from_shell=$(toml_get "$root/hosts.toml" "$host" "$key")
        [ -n "$from_shell" ] || fail "$host has no $key"
        [ "$from_cmake" = "$from_shell" ] ||
            fail "$host $key: '$from_cmake' in CMake, '$from_shell' in shell"
    done
    from_cmake=$(printf '%s\n' "$info" | sed -n 's/^flags=//p' | tr ';' '\n')
    from_shell=$(toml_get "$root/hosts.toml" "$host" flags)
    [ "$from_cmake" = "$from_shell" ] ||
        fail "$host flags: '$from_cmake' in CMake, '$from_shell' in shell"
done

# A missing key stops both readers rather than reading as empty.
expect_refusal "no nothing in [linux-x86_64]" \
    recipe "$root" -DHOST=linux-x86_64 -DSTEP=get -DKEY=nothing
if toml_get "$root/hosts.toml" linux-x86_64 nothing >/dev/null; then
    fail "the shell reader returned success for a missing key"
fi
finished=yes
