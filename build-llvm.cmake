# Build the five LLVM tools of one host from the pinned LLVM source.
#
#   cmake -DHOST=<host> [-DRUNNER=<command>] [-DACCEPT_LICENSE=yes] \
#         -P build-llvm.cmake
#
# HOST names a table of hosts.toml. The compiler is clang of the LLVM
# release that pins/release.toml names for this machine. The recipe checks
# the digest and the Sigstore attestation of that archive and the digest of
# the source, builds lld, llvm-mc, llvm-ar, llvm-objdump and llvm-readobj
# into build/<host>/llvm/bin, and refuses a tool that names a shared library
# outside the system set of its host or reports another version. It then
# writes build/<host>/recipe, which scripts/pack.sh reads.
#
# RUNNER is a command that runs a tool of another operating system, as
# "docker;run;..." for Linux. ACCEPT_LICENSE=yes lets xwin download the
# Microsoft CRT and Windows SDK for a Windows host.
#
# STEP runs one part alone. The tests and the scripts use it.
#   hosts, tools            print the hosts or the tools of hosts.toml
#   host-info, get          print the fields of HOST, or KEY of HOST
#   paths                   print the paths of HOST that other files read
#   fetch-file              download URL to FILE and check SHA256
#   check-libraries         check the shared libraries of the tools in BIN
#   check-version           check the version the tools in BIN report
cmake_minimum_required(VERSION 3.25)

# DESIGN: every path of the build tree is defined here once. The scripts
# ask STEP=paths for the ones they read, so no second spelling exists.
set(root "${CMAKE_CURRENT_LIST_DIR}")
set(build_root "${root}/build")
set(downloads "${build_root}/downloads")
set(release_root "${build_root}/release")
set(source_root "${build_root}/source")
set(sysroot_root "${build_root}/sysroot")
set(dist "${build_root}/dist")
set(hosts_file "${root}/hosts.toml")
set(pins "${root}/pins")

if(NOT DEFINED STEP)
    set(STEP all)
endif()

# Print one line to standard output, which message() does not reach.
function(say line)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${line}")
endfunction()

# Set <out> to the value of <key> in table <section> of a TOML file of this
# repository. An empty section names the keys above the first table. A
# string gives a string, an array of strings gives a list, and a missing
# key stops the run. The files hold that subset of TOML and nothing else.
function(toml_get file section key out)
    file(STRINGS "${file}" lines)
    set(current "")
    foreach(line IN LISTS lines)
        if(line MATCHES "^\\[(.*)\\]$")
            set(current "${CMAKE_MATCH_1}")
        elseif(current STREQUAL section AND line MATCHES "^${key} = (.*)$")
            set(value "${CMAKE_MATCH_1}")
            if(value MATCHES "^\\[(.*)\\]$")
                string(REGEX REPLACE "\" *, *\"" ";" value "${CMAKE_MATCH_1}")
                string(REPLACE "\"" "" value "${value}")
            else()
                string(REGEX REPLACE "^\"(.*)\"$" "\\1" value "${value}")
            endif()
            set(${out} "${value}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    message(FATAL_ERROR "${file} has no ${key} in [${section}]")
endfunction()

function(toml_sections file out)
    file(STRINGS "${file}" lines REGEX "^\\[.*\\]$")
    list(TRANSFORM lines REPLACE "^\\[(.*)\\]$" "\\1")
    set(${out} "${lines}" PARENT_SCOPE)
endfunction()

# The name of this machine in the spelling of hosts.toml.
function(this_machine out)
    cmake_host_system_information(RESULT os QUERY OS_NAME)
    cmake_host_system_information(RESULT cpu QUERY OS_PLATFORM)
    string(TOLOWER "${os}" os)
    string(TOLOWER "${cpu}" cpu)
    if(cpu MATCHES "^(arm64|aarch64)$")
        set(cpu arm64)
    elseif(cpu MATCHES "^(x86_64|amd64|x64)$")
        set(cpu x86_64)
    endif()
    set(${out} "${os}-${cpu}" PARENT_SCOPE)
endfunction()

# Download url to file unless it is there, and stop unless its SHA-256
# digest is sha256. A file already in place is checked and never
# downloaded again, so a changed file stops the run instead of vanishing.
function(fetch url file sha256)
    if(NOT EXISTS "${file}")
        get_filename_component(dir "${file}" DIRECTORY)
        file(MAKE_DIRECTORY "${dir}")
        message(STATUS "download ${url}")
        file(DOWNLOAD "${url}" "${file}.part" STATUS status)
        list(GET status 0 code)
        list(GET status 1 text)
        if(NOT code EQUAL 0)
            file(REMOVE "${file}.part")
            message(FATAL_ERROR "${url}: ${text}")
        endif()
        file(SHA256 "${file}.part" actual)
        if(NOT actual STREQUAL sha256)
            file(REMOVE "${file}.part")
            message(FATAL_ERROR "${url}: SHA-256 ${actual}, the pin is ${sha256}")
        endif()
        file(RENAME "${file}.part" "${file}")
    endif()
    file(SHA256 "${file}" actual)
    if(NOT actual STREQUAL sha256)
        message(FATAL_ERROR "${file}: SHA-256 ${actual}, the pin is ${sha256}. "
                            "Delete the file to download it again.")
    endif()
endfunction()

# Unpack archive into dest, whose .unpacked file names the digest of the
# archive it came from. With TOP the archive holds one directory, which
# becomes dest.
function(unpack archive dest digest)
    cmake_parse_arguments(PARSE_ARGV 3 arg "TOP" "" "")
    if(EXISTS "${dest}/.unpacked")
        file(READ "${dest}/.unpacked" done)
        if(done STREQUAL "${digest}\n")
            return()
        endif()
    endif()
    message(STATUS "unpack ${archive}")
    file(REMOVE_RECURSE "${dest}" "${dest}.part")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${dest}.part")
    if(arg_TOP)
        file(GLOB top LIST_DIRECTORIES true "${dest}.part/*")
        list(LENGTH top count)
        if(NOT count EQUAL 1)
            message(FATAL_ERROR "${archive} holds ${count} entries at its root, not one")
        endif()
        file(RENAME "${top}" "${dest}")
        file(REMOVE_RECURSE "${dest}.part")
    else()
        file(RENAME "${dest}.part" "${dest}")
    endif()
    file(WRITE "${dest}/.unpacked" "${digest}\n")
endfunction()

file(READ "${pins}/llvm-version" version)
string(STRIP "${version}" version)
string(REGEX MATCH "^[0-9]+" major "${version}")
toml_get("${hosts_file}" "" tools TOOLS)
toml_sections("${hosts_file}" HOSTS)
this_machine(machine)

if(STEP STREQUAL "hosts")
    foreach(host IN LISTS HOSTS)
        say("${host}")
    endforeach()
    return()
elseif(STEP STREQUAL "tools")
    foreach(tool IN LISTS TOOLS)
        say("${tool}")
    endforeach()
    return()
elseif(STEP STREQUAL "fetch-file")
    fetch("${URL}" "${FILE}" "${SHA256}")
    return()
endif()

# Every other step works on one host.
if(NOT HOST IN_LIST HOSTS)
    message(FATAL_ERROR "HOST is '${HOST}', and hosts.toml names ${HOSTS}")
endif()
if(STEP STREQUAL "get")
    toml_get("${hosts_file}" "${HOST}" "${KEY}" value)
    say("${value}")
    return()
endif()
toml_get("${hosts_file}" "${HOST}" triple triple)
toml_get("${hosts_file}" "${HOST}" built-on built_on)
toml_get("${hosts_file}" "${HOST}" sysroot sysroot_kind)
toml_get("${hosts_file}" "${HOST}" flags host_flags)
if(STEP STREQUAL "host-info")
    say("triple=${triple}")
    say("built-on=${built_on}")
    say("sysroot=${sysroot_kind}")
    say("flags=${host_flags}")
    return()
endif()

if(triple MATCHES "-linux-")
    set(os linux)
elseif(triple MATCHES "-apple-")
    set(os macos)
elseif(triple MATCHES "-windows-")
    set(os windows)
else()
    message(FATAL_ERROR "${HOST}: the triple ${triple} names no known system")
endif()
string(REGEX MATCH "^[^-]+" arch "${triple}")
set(exe "")
if(os STREQUAL "windows")
    set(exe ".exe")
endif()

set(work "${build_root}/${HOST}")
set(tools_bin "${work}/llvm/bin")
set(stamp "${work}/recipe")

# The release of this machine: its archive, and the directory it unpacks to.
set(release "")
set(release_bin "")
set(machine_exe "")
if(machine MATCHES "^windows-")
    set(machine_exe ".exe")
endif()
file(STRINGS "${pins}/release.toml" release_tables REGEX "^\\[${machine}\\]$")
if(release_tables)
    toml_get("${pins}/release.toml" "${machine}" url release_url)
    string(REPLACE "@VERSION@" "${version}" release_url "${release_url}")
    get_filename_component(release_asset "${release_url}" NAME)
    string(REGEX REPLACE "\\.tar\\.xz$" "" release_name "${release_asset}")
    set(release "${release_root}/${release_name}")
    set(release_bin "${release}/bin")
endif()

if(sysroot_kind STREQUAL "musl")
    set(sysroot "${sysroot_root}/${HOST}")
elseif(sysroot_kind STREQUAL "macos-sdk")
    toml_get("${pins}/sysroot.toml" macos-sdk path sysroot)
elseif(sysroot_kind STREQUAL "xwin")
    set(sysroot "${sysroot_root}/windows")
else()
    message(FATAL_ERROR "${HOST}: no sysroot of kind ${sysroot_kind}")
endif()

if(STEP STREQUAL "paths")
    say("bin=${tools_bin}")
    say("stamp=${stamp}")
    say("dist=${dist}")
    say("exe=${exe}")
    say("release=${release_bin}")
    say("sysroot=${sysroot}")
    return()
endif()

if(release STREQUAL "")
    message(FATAL_ERROR "pins/release.toml names no release for ${machine}, "
                        "the machine this runs on")
endif()

# DESIGN: a tool we publish runs on a machine that holds nothing but its
# system. Linux has no system set, because the tools link musl statically.
# macOS keeps libSystem and libc++, since it has no static libSystem.
# Windows keeps the DLLs that every Windows 10 and 11 holds, and the CRT is
# linked in with /MT. The six are the ones the tools of 23.1.1 import.
set(macos_libraries /usr/lib/libSystem.B.dylib /usr/lib/libc++.1.dylib)
set(windows_libraries advapi32.dll crypt32.dll kernel32.dll ntdll.dll
    oleaut32.dll winhttp.dll)
set(linux_formats_x86_64 elf64-x86-64)
set(linux_formats_aarch64 elf64-littleaarch64)
set(macos_formats_x86_64 "mach-o 64-bit x86-64")
set(macos_formats_arm64 mach-o-arm64 "mach-o arm64")
set(windows_formats_x86_64 coff-x86-64)
set(windows_formats_aarch64 coff-arm64)

# Refuse a tool in bin that is missing, of another format, or names a
# shared library outside the system set. The Mac cannot run ldd on an ELF
# file, so llvm-objdump reads the dynamic section of Linux tools.
function(check_libraries bin)
    set(objdump "${release_bin}/llvm-objdump")
    find_program(OTOOL otool)
    foreach(tool IN LISTS TOOLS)
        set(file "${bin}/${tool}${exe}")
        if(NOT EXISTS "${file}")
            message(FATAL_ERROR "${file} is missing")
        endif()
        execute_process(COMMAND "${objdump}" --private-headers "${file}"
                        OUTPUT_VARIABLE headers RESULT_VARIABLE status)
        if(NOT status EQUAL 0)
            message(FATAL_ERROR "llvm-objdump cannot read ${file}")
        endif()
        string(REGEX MATCH "file format ([^\n]+)" found "${headers}")
        set(format "${CMAKE_MATCH_1}")
        if(NOT format IN_LIST ${os}_formats_${arch})
            message(FATAL_ERROR "${tool}${exe} is ${format}, and ${HOST} "
                                "takes ${${os}_formats_${arch}}")
        endif()
        set(needed "")
        if(os STREQUAL "linux")
            string(REGEX MATCHALL "NEEDED +[^\n]+" lines "${headers}")
            foreach(line IN LISTS lines)
                string(REGEX REPLACE "^NEEDED +" "" line "${line}")
                list(APPEND needed "${line}")
            endforeach()
            if(headers MATCHES "\n *INTERP ")
                list(APPEND needed "a dynamic loader")
            endif()
        elseif(os STREQUAL "macos")
            if(OTOOL)
                execute_process(COMMAND "${OTOOL}" -L "${file}"
                                OUTPUT_VARIABLE libraries)
            else()
                execute_process(COMMAND "${objdump}" --macho --dylibs-used
                                        "${file}" OUTPUT_VARIABLE libraries)
            endif()
            string(REGEX MATCHALL "\n\t[^ \n]+" lines "${libraries}")
            foreach(line IN LISTS lines)
                string(STRIP "${line}" line)
                if(NOT line IN_LIST macos_libraries)
                    list(APPEND needed "${line}")
                endif()
            endforeach()
        else()
            string(REGEX MATCHALL "DLL Name: [^\n]+" lines "${headers}")
            foreach(line IN LISTS lines)
                string(REGEX REPLACE "^DLL Name: " "" line "${line}")
                string(STRIP "${line}" line)
                string(TOLOWER "${line}" lower)
                if(NOT lower IN_LIST windows_libraries)
                    list(APPEND needed "${line}")
                endif()
            endforeach()
        endif()
        if(needed)
            message(FATAL_ERROR "${tool}${exe} of ${HOST} needs ${needed}, "
                                "which is outside the system set of ${HOST}")
        endif()
        message(STATUS "${tool}${exe}: ${format}, no library outside the system set")
    endforeach()
endfunction()

# Refuse a tool in bin that fails to run or reports another version. lld
# answers under ld.lld, ld64.lld and lld-link, which antic calls, so each
# flavor runs.
function(check_version bin)
    set(prefix "")
    if(NOT HOST STREQUAL machine)
        if(HOST STREQUAL "macos-x86_64" AND machine STREQUAL "macos-arm64")
            # Rosetta runs the x86_64 tools on this machine.
            set(prefix arch -x86_64)
        elseif(DEFINED RUNNER)
            set(prefix ${RUNNER})
        else()
            message(FATAL_ERROR "the tools of ${HOST} do not run on ${machine}. "
                                "Pass -DRUNNER=<command> that runs them.")
        endif()
    endif()
    set(runs "")
    foreach(tool IN LISTS TOOLS)
        if(tool STREQUAL "lld")
            foreach(flavor gnu darwin link)
                list(APPEND runs "lld -flavor ${flavor}")
            endforeach()
        else()
            list(APPEND runs "${tool}")
        endif()
    endforeach()
    foreach(run IN LISTS runs)
        separate_arguments(command UNIX_COMMAND "${run}")
        list(POP_FRONT command tool)
        execute_process(COMMAND ${prefix} "${bin}/${tool}${exe}" ${command}
                                --version
                        OUTPUT_VARIABLE out ERROR_VARIABLE err
                        RESULT_VARIABLE status)
        if(NOT status EQUAL 0)
            message(FATAL_ERROR "${run} --version failed on ${HOST}: ${status} ${err}")
        endif()
        string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" found "${out}${err}")
        if(NOT found STREQUAL version)
            message(FATAL_ERROR "${run} reports ${found}, and the pin is ${version}")
        endif()
        string(REGEX MATCH "[^\n]*${found}[^\n]*" line "${out}${err}")
        string(STRIP "${line}" line)
        message(STATUS "${run}: ${line}")
    endforeach()
endfunction()

if(STEP STREQUAL "check-libraries")
    check_libraries("${BIN}")
    return()
elseif(STEP STREQUAL "check-version")
    check_version("${BIN}")
    return()
elseif(NOT STEP STREQUAL "all")
    message(FATAL_ERROR "STEP is '${STEP}', which the recipe does not know")
endif()

if(NOT built_on STREQUAL machine)
    message(FATAL_ERROR "hosts.toml builds ${HOST} on ${built_on}, and this is ${machine}")
endif()
file(REMOVE "${stamp}")

# Step 1. The release of this machine, checked against its digest and its
# Sigstore attestation, which binds it to the release workflow of LLVM at
# the tag of the pin.
toml_get("${pins}/release.toml" "${machine}" sha256 release_sha256)
toml_get("${pins}/release.toml" "${machine}" attestation attestation_url)
string(REPLACE "@VERSION@" "${version}" attestation_url "${attestation_url}")
fetch("${release_url}" "${downloads}/${release_asset}" "${release_sha256}")
set(bundle "${downloads}/${release_asset}.jsonl")
if(NOT EXISTS "${bundle}")
    file(DOWNLOAD "${attestation_url}" "${bundle}.part" STATUS status)
    list(GET status 0 code)
    if(NOT code EQUAL 0)
        file(REMOVE "${bundle}.part")
        message(FATAL_ERROR "${attestation_url}: ${status}")
    endif()
    file(RENAME "${bundle}.part" "${bundle}")
endif()
find_program(GH gh)
if(NOT GH)
    message(FATAL_ERROR "gh is not on the PATH. It verifies the attestation.")
endif()
execute_process(COMMAND "${GH}" attestation verify
                        "${downloads}/${release_asset}" --bundle "${bundle}"
                        --repo llvm/llvm-project
                        --source-ref "refs/tags/llvmorg-${version}"
                        --signer-workflow
                        "llvm/llvm-project/.github/workflows/release-binaries.yml"
                RESULT_VARIABLE verified)
if(NOT verified EQUAL 0)
    message(FATAL_ERROR "${release_asset} fails its Sigstore attestation")
endif()
unpack("${downloads}/${release_asset}" "${release}" "${release_sha256}" TOP)

# Step 2. The source.
file(READ "${pins}/source.sha256" source_sha256)
string(STRIP "${source_sha256}" source_sha256)
set(source_asset "llvm-project-${version}.src.tar.xz")
fetch("https://github.com/llvm/llvm-project/releases/download/llvmorg-${version}/${source_asset}"
      "${downloads}/${source_asset}" "${source_sha256}")
set(source "${source_root}/llvm-project-${version}.src")
unpack("${downloads}/${source_asset}" "${source}" "${source_sha256}" TOP)

# The sysroot of the host.
if(sysroot_kind STREQUAL "musl")
    toml_get("${pins}/sysroot.toml" "musl-${arch}" url musl_url)
    toml_get("${pins}/sysroot.toml" "musl-${arch}" sha256 musl_sha256)
    toml_get("${pins}/sysroot.toml" "musl-${arch}" headers-url headers_url)
    toml_get("${pins}/sysroot.toml" "musl-${arch}" headers-sha256 headers_sha256)
    get_filename_component(musl_asset "${musl_url}" NAME)
    get_filename_component(headers_asset "${headers_url}" NAME)
    fetch("${musl_url}" "${downloads}/${arch}/${musl_asset}" "${musl_sha256}")
    fetch("${headers_url}" "${downloads}/${arch}/${headers_asset}"
          "${headers_sha256}")
    # Both packages unpack into one tree, so the stamp names both digests.
    set(sysroot_digest "${musl_sha256} ${headers_sha256}")
    set(done "")
    if(EXISTS "${sysroot}/.unpacked")
        file(READ "${sysroot}/.unpacked" done)
    endif()
    if(NOT done STREQUAL "${sysroot_digest}\n")
        message(STATUS "unpack the sysroot of ${HOST}")
        file(REMOVE_RECURSE "${sysroot}")
        foreach(asset "${musl_asset}" "${headers_asset}")
            file(ARCHIVE_EXTRACT INPUT "${downloads}/${arch}/${asset}"
                 DESTINATION "${sysroot}")
        endforeach()
        file(WRITE "${sysroot}/.unpacked" "${sysroot_digest}\n")
    endif()
elseif(sysroot_kind STREQUAL "macos-sdk")
    if(NOT EXISTS "${sysroot}/SDKSettings.json")
        message(FATAL_ERROR "${sysroot} is missing. Install the Command Line "
                            "Tools that carry it.")
    endif()
elseif(sysroot_kind STREQUAL "xwin")
    toml_get("${pins}/sysroot.toml" xwin version xwin_version)
    toml_get("${pins}/sysroot.toml" xwin crt xwin_crt)
    toml_get("${pins}/sysroot.toml" xwin sdk xwin_sdk)
    toml_get("${pins}/sysroot.toml" xwin tree xwin_tree)
    if(NOT EXISTS "${sysroot}/.unpacked")
        if(NOT ACCEPT_LICENSE STREQUAL "yes")
            message(FATAL_ERROR "xwin downloads the Microsoft CRT and Windows "
                                "SDK, which Microsoft licenses to you. Pass "
                                "-DACCEPT_LICENSE=yes to accept their terms.")
        endif()
        find_program(XWIN xwin)
        if(NOT XWIN)
            message(FATAL_ERROR "xwin is not on the PATH. Run cargo install "
                                "xwin --locked --version ${xwin_version}")
        endif()
        execute_process(COMMAND "${XWIN}" --version OUTPUT_VARIABLE found)
        if(NOT found MATCHES "^xwin ${xwin_version}\n?$")
            message(FATAL_ERROR "${XWIN} is ${found}, the pin is ${xwin_version}")
        endif()
        file(REMOVE_RECURSE "${sysroot}")
        # DESIGN: the winsysroot layout is the one of LLVM's WinMsvc.cmake.
        # xwin adds no casing links, because WinMsvc.cmake adds its own on
        # a file system that needs them.
        execute_process(COMMAND "${XWIN}" --accept-license
                                --cache-dir "${downloads}/xwin"
                                --arch x86_64,aarch64
                                --crt-version "${xwin_crt}"
                                --sdk-version "${xwin_sdk}"
                                splat --output "${sysroot}"
                                --use-winsysroot-style
                                --preserve-ms-arch-notation
                                --disable-symlinks --copy
                        RESULT_VARIABLE splat)
        if(NOT splat EQUAL 0)
            message(FATAL_ERROR "xwin failed to write ${sysroot}")
        endif()
        # The digest hashes the sorted SHA-256 lines of the regular files.
        file(GLOB_RECURSE files LIST_DIRECTORIES false RELATIVE "${sysroot}"
             "${sysroot}/*")
        list(SORT files)
        set(lines "")
        foreach(name IN LISTS files)
            file(SHA256 "${sysroot}/${name}" digest)
            string(APPEND lines "${digest}  ${name}\n")
        endforeach()
        string(SHA256 tree "${lines}")
        if(NOT tree STREQUAL xwin_tree)
            message(FATAL_ERROR "${sysroot} has the digest ${tree}, and "
                                "pins/sysroot.toml holds '${xwin_tree}'")
        endif()
        file(WRITE "${sysroot}/.unpacked" "${tree}\n")
    endif()
endif()

# Configure <dir> from <source dir> with the toolchain file and the options
# given, and build the targets named after TARGETS.
function(cmake_build dir source_dir)
    cmake_parse_arguments(PARSE_ARGV 2 arg "" "" "OPTIONS;TARGETS")
    # --fresh drops the cache, so each run configures from the options of
    # this recipe alone. Ninja still rebuilds only what changed.
    execute_process(COMMAND "${CMAKE_COMMAND}" --fresh -G Ninja
                            -S "${source_dir}" -B "${dir}" ${arg_OPTIONS}
                    RESULT_VARIABLE configured)
    if(NOT configured EQUAL 0)
        message(FATAL_ERROR "cmake failed to configure ${dir}")
    endif()
    set(targets "")
    if(arg_TARGETS)
        set(targets --target ${arg_TARGETS})
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${dir}" ${targets}
                    RESULT_VARIABLE built)
    if(NOT built EQUAL 0)
        message(FATAL_ERROR "the build of ${dir} failed")
    endif()
endfunction()

find_program(NINJA ninja)
if(NOT NINJA)
    message(FATAL_ERROR "ninja is not on the PATH, and the build needs it")
endif()

# DESIGN: debug information and __FILE__ would carry the path of this
# machine into every tool. The map turns the build tree into a dot, and a
# check below refuses a tool that still holds it.
set(prefix_map "-ffile-prefix-map=${build_root}=.")

# Write the toolchain file of this host to <file>. RUNTIMES writes the one
# that builds the C++ runtimes of a musl host, which cannot link against
# them yet.
function(write_toolchain file)
    cmake_parse_arguments(PARSE_ARGV 1 arg "RUNTIMES" "" "")
    set(rel "${release_bin}")
    # CMake reads a toolchain file more than once, and WinMsvc.cmake adds its
    # flags on the first read alone. The guard keeps both reads equal.
    set(text "include_guard(GLOBAL)\n")
    if(os STREQUAL "linux")
        set(rt "${work}/runtimes-install")
        string(APPEND text
"set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR ${arch})
set(CMAKE_SYSROOT \"${sysroot}\")
set(CMAKE_C_COMPILER \"${rel}/clang\")
set(CMAKE_CXX_COMPILER \"${rel}/clang++\")
set(CMAKE_ASM_COMPILER \"${rel}/clang\")
set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_CXX_COMPILER_TARGET ${triple})
set(CMAKE_ASM_COMPILER_TARGET ${triple})
set(CMAKE_AR \"${rel}/llvm-ar\" CACHE FILEPATH \"\")
set(CMAKE_RANLIB \"${rel}/llvm-ranlib\" CACHE FILEPATH \"\")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
")
        if(arg_RUNTIMES)
            string(APPEND text
"set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_FLAGS_INIT \"${prefix_map}\")
set(CMAKE_CXX_FLAGS_INIT \"${prefix_map}\")
set(CMAKE_ASM_FLAGS_INIT \"${prefix_map}\")
")
        else()
            # DESIGN: the tools link libc++, libc++abi, libunwind and the
            # compiler-rt builtins built from the pinned source, and musl.
            # -static leaves no library to load, and -s drops the symbols.
            set(resource "${rt}/lib/clang/${major}")
            set(c_flags "-resource-dir=${resource} ${prefix_map}")
            string(APPEND text
"set(CMAKE_C_FLAGS_INIT \"${c_flags}\")
set(CMAKE_CXX_FLAGS_INIT \"${c_flags} -nostdinc++ -isystem ${rt}/include/${triple}/c++/v1 -isystem ${rt}/include/c++/v1\")
set(CMAKE_EXE_LINKER_FLAGS_INIT \"-fuse-ld=lld -static -s -rtlib=compiler-rt -unwindlib=libunwind -stdlib=libc++ -L${rt}/lib/${triple}\")
")
        endif()
    elseif(os STREQUAL "macos")
        # DESIGN: the libc++ headers of the SDK match the libc++ of the
        # system that the tools load. The headers beside the release clang
        # would name symbols an older macOS lacks.
        string(APPEND text
"set(CMAKE_C_COMPILER \"${rel}/clang\")
set(CMAKE_CXX_COMPILER \"${rel}/clang++\")
set(CMAKE_ASM_COMPILER \"${rel}/clang\")
set(CMAKE_OSX_SYSROOT \"${sysroot}\" CACHE PATH \"\")
set(CMAKE_AR \"${rel}/llvm-ar\" CACHE FILEPATH \"\")
set(CMAKE_RANLIB \"${rel}/llvm-ranlib\" CACHE FILEPATH \"\")
set(CMAKE_LIBTOOL \"${rel}/llvm-libtool-darwin\" CACHE FILEPATH \"\")
set(CMAKE_C_FLAGS_INIT \"${prefix_map}\")
set(CMAKE_CXX_FLAGS_INIT \"${prefix_map} -nostdinc++ -isystem ${sysroot}/usr/include/c++/v1\")
set(CMAKE_EXE_LINKER_FLAGS_INIT \"-fuse-ld=lld -Wl,-S\")
")
    else()
        # DESIGN: WinMsvc.cmake of the LLVM source is the cross toolchain
        # that LLVM keeps for clang-cl on another system. /MT links the CRT
        # in, so the tools need no Visual C++ runtime on the machine.
        string(APPEND text
"set(LLVM_NATIVE_TOOLCHAIN \"${release}\")
set(LLVM_WINSYSROOT \"${sysroot}\")
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)
set(CMAKE_C_FLAGS_INIT \"/clang:${prefix_map}\")
set(CMAKE_CXX_FLAGS_INIT \"/clang:${prefix_map}\")
set(CMAKE_RC_COMPILER \"${rel}/llvm-rc\" CACHE FILEPATH \"\")
set(CMAKE_MT \"${rel}/llvm-mt\" CACHE FILEPATH \"\")
include(\"${source}/llvm/cmake/platforms/WinMsvc.cmake\")
")
    endif()
    file(WRITE "${file}" "${text}")
endfunction()

# Step 3, first half. A musl host builds its C++ runtimes and the
# compiler-rt builtins from the pinned source, since musl-dev carries none.
if(os STREQUAL "linux")
    set(runtimes_toolchain "${work}/runtimes-toolchain.cmake")
    write_toolchain("${runtimes_toolchain}" RUNTIMES)
    # A list reaches CMake through a cache file, since a semicolon inside
    # one argument of execute_process splits it.
    file(WRITE "${work}/runtimes-cache.cmake"
         "set(LLVM_ENABLE_RUNTIMES \"compiler-rt;libunwind;libcxxabi;libcxx\" CACHE STRING \"\" FORCE)\n")
    cmake_build("${work}/runtimes" "${source}/runtimes" OPTIONS
        -C "${work}/runtimes-cache.cmake"
        "-DCMAKE_TOOLCHAIN_FILE=${runtimes_toolchain}"
        -DCMAKE_BUILD_TYPE=Release
        "-DCMAKE_INSTALL_PREFIX=${work}/runtimes-install"
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
        "-DLLVM_DEFAULT_TARGET_TRIPLE=${triple}"
        -DLLVM_INCLUDE_TESTS=OFF
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
        "-DCOMPILER_RT_INSTALL_PATH=${work}/runtimes-install/lib/clang/${major}"
        -DCOMPILER_RT_BUILD_BUILTINS=ON
        -DCOMPILER_RT_BUILD_CRT=ON
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF
        -DCOMPILER_RT_BUILD_XRAY=OFF
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
        -DCOMPILER_RT_BUILD_PROFILE=OFF
        -DCOMPILER_RT_BUILD_MEMPROF=OFF
        -DCOMPILER_RT_BUILD_ORC=OFF
        -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF
        -DCOMPILER_RT_BUILD_GWP_ASAN=OFF
        -DCOMPILER_RT_INCLUDE_TESTS=OFF
        -DLIBUNWIND_ENABLE_SHARED=OFF
        -DLIBUNWIND_USE_COMPILER_RT=ON
        -DLIBUNWIND_INCLUDE_TESTS=OFF
        -DLIBCXXABI_ENABLE_SHARED=OFF
        -DLIBCXXABI_USE_COMPILER_RT=ON
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON
        -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
        # The try-compiles of the runtimes link nothing, so every probe for a
        # function of the C library passes. musl has no such function.
        -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF
        -DLIBCXXABI_INCLUDE_TESTS=OFF
        -DLIBCXX_ENABLE_SHARED=OFF
        -DLIBCXX_HAS_MUSL_LIBC=ON
        -DLIBCXX_USE_COMPILER_RT=ON
        -DLIBCXX_CXX_ABI=libcxxabi
        -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
        -DLIBCXX_INCLUDE_TESTS=OFF
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF
        TARGETS install)
    # clang takes the builtin headers from the resource directory, which
    # the runtimes do not install. They come from the release clang.
    file(COPY "${release}/lib/clang/${major}/include"
         DESTINATION "${work}/runtimes-install/lib/clang/${major}")
endif()

set(toolchain "${work}/toolchain.cmake")
write_toolchain("${toolchain}")

# zlib, built with the same toolchain from the pinned source.
toml_get("${pins}/zlib.toml" zlib version zlib_version)
toml_get("${pins}/zlib.toml" zlib url zlib_url)
toml_get("${pins}/zlib.toml" zlib sha256 zlib_sha256)
string(REPLACE "@VERSION@" "${zlib_version}" zlib_url "${zlib_url}")
get_filename_component(zlib_asset "${zlib_url}" NAME)
fetch("${zlib_url}" "${downloads}/${zlib_asset}" "${zlib_sha256}")
set(zlib_source "${source_root}/zlib-${zlib_version}")
unpack("${downloads}/${zlib_asset}" "${zlib_source}" "${zlib_sha256}" TOP)
# DESIGN: the CMakeLists.txt of zlib renames zconf.h in its source tree and
# builds a shared library beside the static one. These lines compile the
# fifteen files of the library alone.
file(WRITE "${work}/zlib-project/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)
project(zlib C)
file(GLOB sources \"${zlib_source}/*.c\")
add_library(z STATIC \${sources})
if(NOT WIN32)
    target_compile_definitions(z PRIVATE HAVE_UNISTD_H)
endif()
set_target_properties(z PROPERTIES POSITION_INDEPENDENT_CODE ON)
")
cmake_build("${work}/zlib" "${work}/zlib-project" OPTIONS
    "-DCMAKE_TOOLCHAIN_FILE=${toolchain}" -DCMAKE_BUILD_TYPE=Release
    ${host_flags})
if(os STREQUAL "windows")
    set(zlib_library "${work}/zlib/z.lib")
else()
    set(zlib_library "${work}/zlib/libz.a")
endif()

# Step 3. LLVM with lld, the X86 and AArch64 back ends and zlib. Every
# option that pulls a library of the build machine into a tool is off.
# llvm-tblgen comes from the release, which runs on this machine.
file(WRITE "${work}/llvm-cache.cmake"
     "set(LLVM_TARGETS_TO_BUILD \"X86;AArch64\" CACHE STRING \"\" FORCE)\n")
cmake_build("${work}/llvm" "${source}/llvm" OPTIONS
    -C "${work}/llvm-cache.cmake"
    "-DCMAKE_TOOLCHAIN_FILE=${toolchain}"
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_ENABLE_PROJECTS=lld
    "-DLLVM_HOST_TRIPLE=${triple}"
    "-DLLVM_TABLEGEN=${release_bin}/llvm-tblgen${machine_exe}"
    "-DLLVM_NATIVE_TOOL_DIR=${release_bin}"
    -DLLVM_ENABLE_ZLIB=FORCE_ON
    "-DZLIB_INCLUDE_DIR=${zlib_source}"
    "-DZLIB_LIBRARY=${zlib_library}"
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_ICU=OFF
    -DLLVM_ENABLE_LIBPFM=OFF
    -DLLVM_ENABLE_Z3_SOLVER=OFF
    -DLLVM_ENABLE_CURL=OFF
    -DLLVM_ENABLE_HTTPLIB=OFF
    -DLLVM_ENABLE_ASSERTIONS=OFF
    -DLLVM_ENABLE_BINDINGS=OFF
    # The source is the release tarball, and git would find this repository.
    -DLLVM_APPEND_VC_REV=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    ${host_flags}
    # Step 4. The five tools and nothing else.
    TARGETS ${TOOLS})

# Steps 5 and 6.
check_libraries("${tools_bin}")
string(REGEX REPLACE "([][+.*()^$?|\\\\])" "\\\\\\1" build_root_regex "${build_root}")
foreach(tool IN LISTS TOOLS)
    file(STRINGS "${tools_bin}/${tool}${exe}" leaked
         REGEX "${build_root_regex}" LIMIT_COUNT 1)
    if(leaked)
        message(FATAL_ERROR "${tool}${exe} holds the path ${build_root}")
    endif()
endforeach()
check_version("${tools_bin}")

# The stamp names the commit of the recipe, and whether the files that
# decide the build differ from it.
execute_process(COMMAND git -C "${root}" rev-parse HEAD
                OUTPUT_VARIABLE commit OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE status ERROR_QUIET)
if(NOT status EQUAL 0)
    set(commit none)
endif()
execute_process(COMMAND git -C "${root}" status --porcelain --
                        build-llvm.cmake hosts.toml pins
                OUTPUT_VARIABLE changes RESULT_VARIABLE status)
set(clean no)
if(status EQUAL 0 AND changes STREQUAL "" AND NOT commit STREQUAL "none")
    set(clean yes)
endif()
file(WRITE "${stamp}" "llvm=${version}\ncommit=${commit}\nclean=${clean}\n")
message(STATUS "${tools_bin} holds the tools of LLVM ${version} for ${HOST}")
