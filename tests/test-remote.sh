#!/bin/sh
# scripts/run-remote.sh copies a tool to another machine and runs it there
# with the arguments given. ssh and scp are stand-ins that treat a directory
# under $work as the home directory of the remote user.
. "$(dirname "$0")/lib.sh"

home="$work/remote-home"
mkdir -p "$home" "$work/fake"
cat > "$work/fake/ssh" <<EOF
#!/bin/sh
while [ "\$#" -gt 2 ]; do shift; done
printf '%s\n' "\$1" >> "$work/ssh.log"
cd "$home" && exec sh -c "\$2"
EOF
cat > "$work/fake/scp" <<EOF
#!/bin/sh
while [ "\$#" -gt 2 ]; do shift; done
printf '%s\n' "\$1" >> "$work/scp.log"
cp "\$1" "$home/\${2#*:}"
EOF
chmod +x "$work/fake"/*

printf '#!/bin/sh\necho "ran with $*"\n' > "$work/tool"
chmod +x "$work/tool"
output=$(PATH="$work/fake:$PATH" REMOTE_SSH_OPTIONS="-o BatchMode=yes" \
    "$root/scripts/run-remote.sh" someone@machine "$work/tool" -flavor gnu --version)
[ "$output" = "ran with -flavor gnu --version" ] ||
    fail "the remote run printed: $output"
digest=$(shasum -a 256 "$work/tool" | cut -c1-16)
[ -f "$home/llvm-tools-check/$digest/tool" ] || fail "the tool was not copied"
[ "$(sort -u "$work/ssh.log")" = someone@machine ] ||
    fail "ssh reached: $(cat "$work/ssh.log")"

# A second run of the same tool reuses the copy. Windows may still hold the
# first one open, so a copy over it can fail.
PATH="$work/fake:$PATH" "$root/scripts/run-remote.sh" someone@machine \
    "$work/tool" --version >/dev/null
[ "$(wc -l < "$work/scp.log" | tr -d ' ')" = 1 ] ||
    fail "the same tool was copied $(wc -l < "$work/scp.log") times"

# The exit status of the tool comes back.
printf '#!/bin/sh\nexit 3\n' > "$work/tool"
if PATH="$work/fake:$PATH" "$root/scripts/run-remote.sh" someone@machine \
        "$work/tool"; then
    fail "a tool that failed on the remote machine passed"
fi
finished=yes
