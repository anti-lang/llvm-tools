# Shared by the scripts under scripts/, which source it.
#
# The TOML files of this repository hold flat tables of strings and arrays
# of strings on one line, and the readers below cover that subset. The
# paths of the build tree come from build-llvm.cmake, which defines them.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

die() {
    printf '%s: %s\n' "$(basename "$0")" "$*" >&2
    exit 1
}

# Print the value of <key> in table <section> of <file>. An empty section
# names the keys above the first table, and an array prints one item a
# line. A missing key prints nothing and fails.
toml_get() {
    awk -v want="$2" -v key="$3" '
        /^\[.*\]$/ { section = substr($0, 2, length($0) - 2); next }
        section == want && $1 == key && $2 == "=" {
            sub(/^[^=]*=[ \t]*/, "")
            if ($0 ~ /^\[/) {
                gsub(/[\[\]"]/, "")
                n = split($0, items, / *, */)
                for (i = 1; i <= n; i++) if (items[i] != "") print items[i]
            } else {
                gsub(/"/, "")
                print
            }
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }' "$1"
}

# Print the table names of <file>, one a line.
toml_sections() {
    sed -n 's/^\[\(.*\)\]$/\1/p' "$1"
}

# Print the value of <key> from the paths step of the recipe for <host>.
recipe_path() {
    cmake -DHOST="$1" -DSTEP=paths -P "$root/build-llvm.cmake" |
        sed -n "s/^$2=//p"
}

version=$(cat "$root/pins/llvm-version")
build_number=$(cat "$root/pins/build-number")
# DESIGN: the tag names the LLVM version, whose build it is, and a counter
# of the rebuilds of that version, as in 23.1.1-anti.1.
tag="$version-anti.$build_number"

# The kinds of archive that each host has: the five tools, and clang.
archive_kinds="llvm-tools clang"

# The file name of the archive of <kind> for <host>.
archive_name() {
    printf '%s-%s-%s.tar.xz\n' "$1" "$tag" "$2"
}

# Fail unless <host> is a table of hosts.toml.
require_host() {
    toml_sections "$root/hosts.toml" | grep -qx -- "$1" ||
        die "$1 is not a host of hosts.toml"
}
