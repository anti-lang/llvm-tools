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
