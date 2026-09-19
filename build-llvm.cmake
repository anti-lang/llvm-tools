# Build the five LLVM tools and clang of one host from the pinned LLVM
# source, or the compiler-rt builtins of all six targets.
#
#   cmake -DHOST=<host> [-DRUNNER=<command>] [-DACCEPT_LICENSE=yes] \
#         -P build-llvm.cmake
#   cmake -DSTEP=builtins [-DACCEPT_LICENSE=yes] -P build-llvm.cmake
#
# HOST names a table of hosts.toml. The compiler is clang of the LLVM
# release that pins/release.toml names for this machine. The recipe checks
# the digest and the Sigstore attestation of that archive and the digest of
# the source. It builds lld, llvm-mc, llvm-ar, llvm-objdump, llvm-readobj
# and clang into build/<host>/llvm/bin, with the built-in headers of clang
# beside them. It refuses a binary that names a shared library outside the
# system set of its host, and one that reports another version. It then
# writes build/<host>/recipe, which scripts/pack.sh reads.
#
# STEP=builtins builds the compiler-rt builtins of the six targets and the
# sanitizer runtimes into build/builtins, which every clang archive
# carries, and writes build/builtins/recipe.
#
# RUNNER is a command that runs a binary of another operating system.
# ACCEPT_LICENSE=yes lets xwin download the Microsoft CRT and Windows SDK
# for a Windows host.
#
# STEP runs one part alone. The tests and the scripts use it.
#   hosts, tools, compiler  print the hosts, the tools or the compiler
#   host-info, get          print the fields of HOST, or KEY of HOST
#   paths                   print the paths of HOST that other files read
#   fetch-file              download URL to FILE and check SHA256
#   check-libraries         check the shared libraries of the binaries in BIN
#   check-version           check the version the binaries in BIN report
#   check-builtins          check the compiler-rt runtimes in BUILTINS, the
#                           lib directory of a resource directory
#   glibc-sysroot           unpack the glibc sysroot of ARCH and print it
cmake_minimum_required(VERSION 3.25)

# DESIGN: every path of the build tree is defined here once. The scripts
# ask STEP=paths for the ones they read, so no second spelling exists.
set(root "${CMAKE_CURRENT_LIST_DIR}")
set(build_root "${root}/build")
set(downloads "${build_root}/downloads")
set(release_root "${build_root}/release")
set(source_root "${build_root}/source")
set(sysroot_root "${build_root}/sysroot")
set(builtins_root "${build_root}/builtins")
set(builtins_install "${builtins_root}/install")
set(builtins_stamp "${builtins_root}/recipe")
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
toml_get("${hosts_file}" "" compiler COMPILER)
set(BINARIES ${TOOLS} ${COMPILER})
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
elseif(STEP STREQUAL "compiler")
    foreach(tool IN LISTS COMPILER)
        say("${tool}")
    endforeach()
    return()
elseif(STEP STREQUAL "fetch-file")
    fetch("${URL}" "${FILE}" "${SHA256}")
    return()
endif()

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

# Set the facts of <host> in the scope of the caller: triple, built_on,
# sysroot_kind, host_flags, deployment, os, arch, exe and sysroot.
function(setup_host host)
    if(NOT host IN_LIST HOSTS)
        message(FATAL_ERROR "HOST is '${host}', and hosts.toml names ${HOSTS}")
    endif()
    toml_get("${hosts_file}" "${host}" triple triple)
    toml_get("${hosts_file}" "${host}" built-on built_on)
    toml_get("${hosts_file}" "${host}" sysroot sysroot_kind)
    toml_get("${hosts_file}" "${host}" flags host_flags)
    if(triple MATCHES "-linux-")
        set(os linux)
    elseif(triple MATCHES "-apple-")
        set(os macos)
    elseif(triple MATCHES "-windows-")
        set(os windows)
    else()
        message(FATAL_ERROR "${host}: the triple ${triple} names no known system")
    endif()
    set(deployment "")
    if(os STREQUAL "macos")
        toml_get("${hosts_file}" "${host}" deployment-target deployment)
    endif()
    string(REGEX MATCH "^[^-]+" arch "${triple}")
    set(exe "")
    if(os STREQUAL "windows")
        set(exe ".exe")
    endif()
    if(sysroot_kind STREQUAL "musl")
        set(sysroot "${sysroot_root}/${host}")
    elseif(sysroot_kind STREQUAL "macos-sdk")
        toml_get("${pins}/sysroot.toml" macos-sdk path sysroot)
    elseif(sysroot_kind STREQUAL "xwin")
        set(sysroot "${sysroot_root}/windows")
    else()
        message(FATAL_ERROR "${host}: no sysroot of kind ${sysroot_kind}")
    endif()
    foreach(name triple built_on sysroot_kind host_flags deployment os arch
            exe sysroot)
        set(${name} "${${name}}" PARENT_SCOPE)
    endforeach()
endfunction()

if(NOT STEP MATCHES "^((check-)?builtins|glibc-sysroot)$")
    # Every other step works on one host.
    if(NOT HOST IN_LIST HOSTS)
        message(FATAL_ERROR "HOST is '${HOST}', and hosts.toml names ${HOSTS}")
    endif()
    if(STEP STREQUAL "get")
        toml_get("${hosts_file}" "${HOST}" "${KEY}" value)
        say("${value}")
        return()
    endif()
    setup_host("${HOST}")
    if(STEP STREQUAL "host-info")
        say("triple=${triple}")
        say("built-on=${built_on}")
        say("sysroot=${sysroot_kind}")
        say("flags=${host_flags}")
        return()
    endif()
    set(work "${build_root}/${HOST}")
    set(tools_bin "${work}/llvm/bin")
    set(stamp "${work}/recipe")
    if(STEP STREQUAL "paths")
        say("bin=${tools_bin}")
        say("resource=${work}/llvm/lib/clang/${major}")
        say("builtins=${builtins_install}/lib/clang/${major}/lib")
        say("builtins-stamp=${builtins_stamp}")
        say("stamp=${stamp}")
        say("dist=${dist}")
        say("exe=${exe}")
        say("release=${release_bin}")
        say("sysroot=${sysroot}")
        return()
    endif()
endif()

if(release STREQUAL "")
    message(FATAL_ERROR "pins/release.toml names no release for ${machine}, "
                        "the machine this runs on")
endif()

# DESIGN: a binary we publish runs on a machine that holds nothing but its
# system. Linux has no system set, because the binaries link musl
# statically. macOS keeps libSystem and libc++, since it has no static
# libSystem. Windows keeps the DLLs that every Windows 10 and 11 holds, and
# the CRT is linked in with /MT. The seven are the ones that the tools and
# clang of 23.1.1 import. clang reads the version of Visual Studio with
# version.dll.
set(macos_libraries /usr/lib/libSystem.B.dylib /usr/lib/libc++.1.dylib)
set(windows_libraries advapi32.dll crypt32.dll kernel32.dll ntdll.dll
    oleaut32.dll version.dll winhttp.dll)
set(linux_formats_x86_64 elf64-x86-64)
set(linux_formats_aarch64 elf64-littleaarch64)
set(macos_formats_x86_64 "mach-o 64-bit x86-64")
set(macos_formats_arm64 mach-o-arm64 "mach-o arm64")
set(windows_formats_x86_64 coff-x86-64)
set(windows_formats_aarch64 coff-arm64)

# Refuse a binary in bin that is missing, of another format, or names a
# shared library outside the system set. The Mac cannot run ldd on an ELF
# file, so llvm-objdump reads the dynamic section of Linux binaries. A
# macOS binary must name the deployment target of its host as minos.
function(check_libraries bin)
    set(objdump "${release_bin}/llvm-objdump")
    find_program(OTOOL otool)
    foreach(tool IN LISTS BINARIES)
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
        set(minos "")
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
                execute_process(COMMAND "${OTOOL}" -l "${file}"
                                OUTPUT_VARIABLE commands)
            else()
                execute_process(COMMAND "${objdump}" --macho --dylibs-used
                                        "${file}" OUTPUT_VARIABLE libraries)
                execute_process(COMMAND "${objdump}" --macho --private-headers
                                        "${file}" OUTPUT_VARIABLE commands)
            endif()
            string(REGEX MATCHALL "\n\t[^ \n]+" lines "${libraries}")
            foreach(line IN LISTS lines)
                string(STRIP "${line}" line)
                if(NOT line IN_LIST macos_libraries)
                    list(APPEND needed "${line}")
                endif()
            endforeach()
            string(REGEX MATCH "LC_BUILD_VERSION[^\n]*\n[^\n]*\n[^\n]*\n *minos ([0-9.]+)"
                   found "${commands}")
            set(minos "${CMAKE_MATCH_1}")
            if(NOT minos STREQUAL deployment)
                message(FATAL_ERROR "${tool} of ${HOST} records minos ${minos}, "
                                    "and the deployment target is ${deployment}")
            endif()
            set(minos ", minos ${minos}")
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
        message(STATUS "${tool}${exe}: ${format}${minos}, no library outside the system set")
    endforeach()
endfunction()

# Refuse a binary in bin that fails to run or reports another version. lld
# answers under ld.lld, ld64.lld and lld-link, which antic calls, so each
# flavor runs.
function(check_version bin)
    set(prefix "")
    if(NOT HOST STREQUAL machine)
        if(HOST STREQUAL "macos-x86_64" AND machine STREQUAL "macos-arm64")
            # Rosetta runs the x86_64 binaries on this machine.
            set(prefix arch -x86_64)
        elseif(DEFINED RUNNER)
            set(prefix ${RUNNER})
        else()
            message(FATAL_ERROR "the tools of ${HOST} do not run on ${machine}. "
                                "Pass -DRUNNER=<command> that runs them.")
        endif()
    endif()
    set(runs "")
    foreach(tool IN LISTS BINARIES)
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
elseif(NOT STEP MATCHES "^(all|builtins|check-builtins|glibc-sysroot)$")
    message(FATAL_ERROR "STEP is '${STEP}', which the recipe does not know")
endif()

# Write <file> with the commit of the recipe, and whether the files that
# decide the build differ from it.
function(write_stamp file)
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
    file(WRITE "${file}" "llvm=${version}\ncommit=${commit}\nclean=${clean}\n")
endfunction()

# Step 1. The release of this machine, checked against its digest and its
# Sigstore attestation, which binds it to the release workflow of LLVM at
# the tag of the pin.
function(prepare_release)
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
endfunction()

# Step 2. The source.
set(source "${source_root}/llvm-project-${version}.src")
function(prepare_source)
    file(READ "${pins}/source.sha256" source_sha256)
    string(STRIP "${source_sha256}" source_sha256)
    set(source_asset "llvm-project-${version}.src.tar.xz")
    fetch("https://github.com/llvm/llvm-project/releases/download/llvmorg-${version}/${source_asset}"
          "${downloads}/${source_asset}" "${source_sha256}")
    unpack("${downloads}/${source_asset}" "${source}" "${source_sha256}" TOP)
endfunction()

# Unpack the glibc sysroot of <arch>, x86_64 or aarch64, and set <out> to
# its directory. Three packages of Ubuntu 22.04 make it: libc6-dev,
# libc6 and linux-libc-dev. A package is an ar archive whose data.tar.zst
# holds the files.
function(prepare_glibc arch out)
    set(dir "${sysroot_root}/glibc-${arch}")
    set(digests "")
    set(debs "")
    foreach(package libc-dev libc headers)
        toml_get("${pins}/sysroot.toml" "glibc-${arch}" "${package}-url" url)
        toml_get("${pins}/sysroot.toml" "glibc-${arch}" "${package}-sha256" digest)
        get_filename_component(asset "${url}" NAME)
        fetch("${url}" "${downloads}/${arch}/${asset}" "${digest}")
        list(APPEND debs "${downloads}/${arch}/${asset}")
        string(APPEND digests "${digest} ")
    endforeach()
    # The three packages unpack into one tree, so the stamp names all three.
    set(done "")
    if(EXISTS "${dir}/.unpacked")
        file(READ "${dir}/.unpacked" done)
    endif()
    if(NOT done STREQUAL "${digests}\n")
        message(STATUS "unpack the sysroot ${dir}")
        file(REMOVE_RECURSE "${dir}" "${dir}.deb")
        foreach(deb IN LISTS debs)
            file(REMOVE_RECURSE "${dir}.deb")
            file(ARCHIVE_EXTRACT INPUT "${deb}" DESTINATION "${dir}.deb")
            file(GLOB data "${dir}.deb/data.tar.*")
            list(LENGTH data count)
            if(NOT count EQUAL 1)
                message(FATAL_ERROR "${deb} holds ${count} data archives, not one")
            endif()
            file(ARCHIVE_EXTRACT INPUT "${data}" DESTINATION "${dir}")
        endforeach()
        file(REMOVE_RECURSE "${dir}.deb")
        file(WRITE "${dir}/.unpacked" "${digests}\n")
    endif()
    set(${out} "${dir}" PARENT_SCOPE)
endfunction()

# The sysroot of the host that setup_host named last.
function(prepare_sysroot)
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
            message(STATUS "unpack the sysroot ${sysroot}")
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
endfunction()

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
# machine into every binary. The map turns the build tree into a dot, and
# a check below refuses a binary that still holds it.
set(prefix_map "-ffile-prefix-map=${build_root}=.")

# Write the toolchain file of the host that setup_host named last to
# <file>. RUNTIMES writes the one that builds the runtimes of a target,
# whose try-compiles cannot link against them yet.
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
            # DESIGN: the binaries link libc++, libc++abi, libunwind and the
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
        # system that the binaries load. The headers beside the release
        # clang would name symbols an older macOS lacks.
        string(APPEND text
"set(CMAKE_C_COMPILER \"${rel}/clang\")
set(CMAKE_CXX_COMPILER \"${rel}/clang++\")
set(CMAKE_ASM_COMPILER \"${rel}/clang\")
set(CMAKE_OSX_SYSROOT \"${sysroot}\" CACHE PATH \"\")
set(CMAKE_AR \"${rel}/llvm-ar\" CACHE FILEPATH \"\")
set(CMAKE_RANLIB \"${rel}/llvm-ranlib\" CACHE FILEPATH \"\")
set(CMAKE_LIBTOOL \"${rel}/llvm-libtool-darwin\" CACHE FILEPATH \"\")
set(CMAKE_LIPO \"${rel}/llvm-lipo\" CACHE FILEPATH \"\")
set(CMAKE_C_FLAGS_INIT \"${prefix_map}\")
set(CMAKE_CXX_FLAGS_INIT \"${prefix_map} -nostdinc++ -isystem ${sysroot}/usr/include/c++/v1\")
set(CMAKE_EXE_LINKER_FLAGS_INIT \"-fuse-ld=lld -Wl,-S\")
set(CMAKE_SHARED_LINKER_FLAGS_INIT \"-fuse-ld=lld\")
set(CMAKE_MODULE_LINKER_FLAGS_INIT \"-fuse-ld=lld\")
")
    else()
        # DESIGN: WinMsvc.cmake of the LLVM source is the cross toolchain
        # that LLVM keeps for clang-cl on another system. /MT links the CRT
        # in, so the binaries need no Visual C++ runtime on the machine.
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

# The sanitizer runtimes that the clang archives carry beside the
# builtins. Linux has the static ones, each with the symbol list that clang
# hands the linker. Windows on x86_64 has ASan as a DLL and UBSan, and
# Windows on arm64 has UBSan alone, since compiler-rt 23.1.1 builds ASan
# for Windows on x86 alone. The macOS ones come with the Darwin builtins.
set(linux_sanitizers asan asan_cxx asan_static asan-preinit ubsan_standalone
    ubsan_standalone_cxx)
set(linux_sanitizer_symbols asan asan_cxx ubsan_standalone ubsan_standalone_cxx)
set(windows_x86_64_sanitizers clang_rt.asan_dynamic.dll
    clang_rt.asan_dynamic.lib clang_rt.asan_dynamic_runtime_thunk.lib
    clang_rt.asan_static_runtime_thunk.lib clang_rt.ubsan_standalone.lib
    clang_rt.ubsan_standalone_cxx.lib)
set(windows_arm64_sanitizers clang_rt.ubsan_standalone.lib
    clang_rt.ubsan_standalone_cxx.lib)

# The options of compiler-rt that build the builtins and nothing else.
set(builtins_options
    -DCOMPILER_RT_BUILD_BUILTINS=ON
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF
    -DCOMPILER_RT_BUILD_XRAY=OFF
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
    -DCOMPILER_RT_BUILD_PROFILE=OFF
    -DCOMPILER_RT_BUILD_MEMPROF=OFF
    -DCOMPILER_RT_BUILD_ORC=OFF
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF
    -DCOMPILER_RT_BUILD_GWP_ASAN=OFF
    -DCOMPILER_RT_INCLUDE_TESTS=OFF)

# Build the builtins of <host> as a target into the install tree of the
# builtins. A Linux target also gets the start files of compiler-rt, which
# clang takes when it links for musl. The macOS builtins are one universal
# archive for both processors, which the arm64 host builds.
#
# DESIGN: macOS also gets the runtimes of AddressSanitizer and
# UndefinedBehaviorSanitizer. antic runs its sanitizer builds on the Mac
# with the pinned clang, and that clang links nothing it does not carry.
function(build_builtins host)
    setup_host("${host}")
    if(host STREQUAL "macos-x86_64")
        return()
    endif()
    prepare_sysroot()
    set(work "${builtins_root}/${host}")
    set(toolchain "${work}/toolchain.cmake")
    set(cache "${work}/cache.cmake")
    write_toolchain("${toolchain}" RUNTIMES)
    set(cache_text "set(LLVM_ENABLE_RUNTIMES \"compiler-rt\" CACHE STRING \"\" FORCE)\n")
    set(options -C "${cache}" "-DCMAKE_TOOLCHAIN_FILE=${toolchain}"
        -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=${builtins_install}"
        "-DCOMPILER_RT_INSTALL_PATH=${builtins_install}/lib/clang/${major}"
        -DLLVM_INCLUDE_TESTS=OFF ${builtins_options})
    if(os STREQUAL "macos")
        string(APPEND cache_text
            "set(DARWIN_osx_ARCHS \"arm64;x86_64\" CACHE STRING \"\" FORCE)\n"
            "set(DARWIN_osx_BUILTIN_ARCHS \"arm64;x86_64\" CACHE STRING \"\" FORCE)\n"
            # compiler-rt adds ubsan whenever it builds a sanitizer.
            "set(COMPILER_RT_SANITIZERS_TO_BUILD \"asan\" CACHE STRING \"\" FORCE)\n")
        list(APPEND options -DCOMPILER_RT_BUILD_SANITIZERS=ON
             -DCOMPILER_RT_ENABLE_IOS=OFF
             -DCOMPILER_RT_ENABLE_WATCHOS=OFF -DCOMPILER_RT_ENABLE_TVOS=OFF
             -DCOMPILER_RT_ENABLE_XROS=OFF
             "-DDARWIN_macosx_CACHED_SYSROOT=${sysroot}"
             "-DDARWIN_osx_SYSROOT=${sysroot}")
    else()
        list(APPEND options -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
             "-DLLVM_DEFAULT_TARGET_TRIPLE=${triple}"
             -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON)
        if(os STREQUAL "linux")
            list(APPEND options -DCOMPILER_RT_BUILD_CRT=ON)
        else()
            # compiler-rt reads the target of a default-target build from
            # CMake, which WinMsvc.cmake gives clang-cl as a flag alone.
            list(APPEND options ${host_flags}
                 "-DCMAKE_C_COMPILER_TARGET=${triple}"
                 "-DCMAKE_CXX_COMPILER_TARGET=${triple}"
                 "-DCMAKE_ASM_COMPILER_TARGET=${triple}")
        endif()
    endif()
    file(WRITE "${cache}" "${cache_text}")
    cmake_build("${work}/build" "${source}/runtimes" OPTIONS ${options}
                TARGETS install)
endfunction()

# The options of compiler-rt that build the sanitizer runtimes and no
# builtins. compiler-rt adds UBSan whenever it builds a sanitizer, and
# naming UBSan as well adds its directory twice. It skips ASan on a target
# that has none, which leaves UBSan alone on Windows on arm64.
set(sanitizer_options
    -DCOMPILER_RT_BUILD_BUILTINS=OFF
    -DCOMPILER_RT_BUILD_SANITIZERS=ON
    -DCOMPILER_RT_SANITIZERS_TO_BUILD=asan
    -DCOMPILER_RT_BUILD_XRAY=OFF
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
    -DCOMPILER_RT_BUILD_PROFILE=OFF
    -DCOMPILER_RT_BUILD_MEMPROF=OFF
    -DCOMPILER_RT_BUILD_ORC=OFF
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF
    -DCOMPILER_RT_BUILD_GWP_ASAN=OFF
    -DCOMPILER_RT_BUILD_CRT=OFF
    -DCOMPILER_RT_INCLUDE_TESTS=OFF)

# Build the sanitizer runtimes of <host> into the install tree of the
# builtins. The macOS ones come with the Darwin builtins.
#
# DESIGN: on Linux the pinned clang compiles for glibc by default, so the
# runtimes are those of <arch>-unknown-linux-gnu, built against glibc 2.35
# of Ubuntu 22.04. They are the static ones, which clang links by default.
# The per-target installs leave out the shared ones, which would link
# against GCC's runtime, and the symbol lists, which the recipe copies.
function(build_sanitizers host)
    setup_host("${host}")
    if(os STREQUAL "macos")
        return()
    endif()
    set(work "${builtins_root}/${host}-sanitizers")
    set(toolchain "${work}/toolchain.cmake")
    set(options "-DCMAKE_TOOLCHAIN_FILE=${toolchain}" -DCMAKE_BUILD_TYPE=Release
        -DLLVM_ENABLE_RUNTIMES=compiler-rt
        "-DCMAKE_INSTALL_PREFIX=${builtins_install}"
        "-DCOMPILER_RT_INSTALL_PATH=${builtins_install}/lib/clang/${major}"
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON ${sanitizer_options})
    if(os STREQUAL "linux")
        prepare_glibc("${arch}" sysroot)
        set(triple "${arch}-unknown-linux-gnu")
        write_toolchain("${toolchain}" RUNTIMES)
        list(APPEND options "-DLLVM_DEFAULT_TARGET_TRIPLE=${triple}")
        set(targets "")
        foreach(name IN LISTS linux_sanitizers)
            list(APPEND targets "install-clang_rt.${name}-${arch}")
        endforeach()
        foreach(name IN LISTS linux_sanitizer_symbols)
            list(APPEND targets "clang_rt.${name}-${arch}-symbols")
        endforeach()
        cmake_build("${work}/build" "${source}/runtimes" OPTIONS ${options}
                    TARGETS ${targets})
        foreach(name IN LISTS linux_sanitizer_symbols)
            set(syms "${triple}/libclang_rt.${name}.a.syms")
            file(COPY_FILE "${work}/build/compiler-rt/lib/${syms}"
                 "${builtins_install}/lib/clang/${major}/lib/${syms}")
        endforeach()
    else()
        write_toolchain("${toolchain}" RUNTIMES)
        # compiler-rt reads the target of a default-target build from
        # CMake, which WinMsvc.cmake gives clang-cl as a flag alone.
        list(APPEND options ${host_flags} "-DLLVM_DEFAULT_TARGET_TRIPLE=${triple}"
             "-DCMAKE_C_COMPILER_TARGET=${triple}"
             "-DCMAKE_CXX_COMPILER_TARGET=${triple}"
             "-DCMAKE_ASM_COMPILER_TARGET=${triple}")
        cmake_build("${work}/build" "${source}/runtimes" OPTIONS ${options}
                    TARGETS install)
    endif()
endfunction()

# Refuse the builtins unless each target has its files, of its format.
function(check_builtins lib)
    set(objdump "${release_bin}/llvm-objdump")
    set(expect
        "x86_64-unknown-linux-musl/libclang_rt.builtins.a=elf64-x86-64"
        "x86_64-unknown-linux-musl/clang_rt.crtbegin.o=elf64-x86-64"
        "x86_64-unknown-linux-musl/clang_rt.crtend.o=elf64-x86-64"
        "aarch64-unknown-linux-musl/libclang_rt.builtins.a=elf64-littleaarch64"
        "aarch64-unknown-linux-musl/clang_rt.crtbegin.o=elf64-littleaarch64"
        "aarch64-unknown-linux-musl/clang_rt.crtend.o=elf64-littleaarch64"
        "x86_64-pc-windows-msvc/clang_rt.builtins.lib=coff-x86-64"
        "aarch64-pc-windows-msvc/clang_rt.builtins.lib=coff-arm64")
    # DESIGN: the sanitizer runtimes of Linux are the static ones, which
    # clang links by default. The shared ones would need GCC's crtbeginS.o,
    # libgcc_s and libstdc++, which the glibc sysroot does not hold.
    foreach(arch_format x86_64=elf64-x86-64 aarch64=elf64-littleaarch64)
        string(REPLACE "=" ";" arch_format "${arch_format}")
        list(GET arch_format 0 arch)
        list(GET arch_format 1 format)
        foreach(name IN LISTS linux_sanitizers)
            list(APPEND expect
                 "${arch}-unknown-linux-gnu/libclang_rt.${name}.a=${format}")
        endforeach()
    endforeach()
    foreach(name IN LISTS windows_x86_64_sanitizers)
        list(APPEND expect "x86_64-pc-windows-msvc/${name}=coff-x86-64")
    endforeach()
    foreach(name IN LISTS windows_arm64_sanitizers)
        list(APPEND expect "aarch64-pc-windows-msvc/${name}=coff-arm64")
    endforeach()
    foreach(arch x86_64 aarch64)
        foreach(name IN LISTS linux_sanitizer_symbols)
            set(syms "${arch}-unknown-linux-gnu/libclang_rt.${name}.a.syms")
            if(NOT EXISTS "${lib}/${syms}")
                message(FATAL_ERROR "the runtimes lack ${syms}")
            endif()
        endforeach()
    endforeach()
    foreach(row IN LISTS expect)
        string(REPLACE "=" ";" row "${row}")
        list(GET row 0 name)
        list(GET row 1 format)
        if(NOT EXISTS "${lib}/${name}")
            message(FATAL_ERROR "the runtimes lack ${name}")
        endif()
        execute_process(COMMAND "${objdump}" -f "${lib}/${name}"
                        OUTPUT_VARIABLE headers RESULT_VARIABLE status)
        string(REGEX MATCHALL "file format [^\n]+" formats "${headers}")
        list(REMOVE_DUPLICATES formats)
        # The stubs of an import library name no machine. Its objects do.
        list(REMOVE_ITEM formats "file format COFF-import-file")
        if(NOT status EQUAL 0 OR NOT formats STREQUAL "file format ${format}")
            message(FATAL_ERROR "${name} holds ${formats}, not ${format}")
        endif()
        message(STATUS "${name}: ${format}")
    endforeach()
    foreach(name libclang_rt.osx.a libclang_rt.asan_osx_dynamic.dylib
            libclang_rt.ubsan_osx_dynamic.dylib)
        execute_process(COMMAND "${release_bin}/llvm-lipo" -archs
                                "${lib}/darwin/${name}"
                        OUTPUT_VARIABLE archs OUTPUT_STRIP_TRAILING_WHITESPACE
                        RESULT_VARIABLE status)
        string(REPLACE " " ";" archs "${archs}")
        list(SORT archs)
        if(NOT status EQUAL 0 OR NOT archs STREQUAL "arm64;x86_64")
            message(FATAL_ERROR "darwin/${name} holds '${archs}', not arm64 and x86_64")
        endif()
        message(STATUS "darwin/${name}: ${archs}")
    endforeach()
endfunction()

if(STEP STREQUAL "check-builtins")
    check_builtins("${BUILTINS}")
    return()
elseif(STEP STREQUAL "glibc-sysroot")
    prepare_glibc("${ARCH}" glibc)
    say("${glibc}")
    return()
endif()

if(STEP STREQUAL "builtins")
    file(REMOVE "${builtins_stamp}")
    prepare_release()
    prepare_source()
    file(REMOVE_RECURSE "${builtins_install}")
    foreach(host IN LISTS HOSTS)
        build_builtins("${host}")
        build_sanitizers("${host}")
    endforeach()
    check_builtins("${builtins_install}/lib/clang/${major}/lib")
    write_stamp("${builtins_stamp}")
    message(STATUS "${builtins_install} holds the builtins of the six targets")
    return()
endif()

if(NOT built_on STREQUAL machine)
    message(FATAL_ERROR "hosts.toml builds ${HOST} on ${built_on}, and this is ${machine}")
endif()
file(REMOVE "${stamp}")
prepare_release()
prepare_source()
prepare_sysroot()

# DESIGN: the deployment target of a macOS host reaches the compiler
# through CMake and through the environment, so a binary built by a step
# that reads only one of them still starts on that macOS.
if(os STREQUAL "macos")
    list(APPEND host_flags "-DCMAKE_OSX_DEPLOYMENT_TARGET=${deployment}")
    set(ENV{MACOSX_DEPLOYMENT_TARGET} "${deployment}")
endif()

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
        ${builtins_options}
        -DCOMPILER_RT_BUILD_CRT=ON
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

# Step 3. LLVM with lld and clang, the X86 and AArch64 back ends and zlib.
# Every option that pulls a library of the build machine into a binary is
# off. llvm-tblgen and clang-tblgen come from the release, which runs on
# this machine.
file(WRITE "${work}/llvm-cache.cmake"
     "set(LLVM_TARGETS_TO_BUILD \"X86;AArch64\" CACHE STRING \"\" FORCE)\n"
     "set(LLVM_ENABLE_PROJECTS \"lld;clang\" CACHE STRING \"\" FORCE)\n")
cmake_build("${work}/llvm" "${source}/llvm" OPTIONS
    -C "${work}/llvm-cache.cmake"
    "-DCMAKE_TOOLCHAIN_FILE=${toolchain}"
    -DCMAKE_BUILD_TYPE=Release
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
    # Step 4. The five tools, clang and its built-in headers, and nothing
    # else.
    TARGETS ${BINARIES} clang-resource-headers)

# Steps 5 and 6.
check_libraries("${tools_bin}")
string(REGEX REPLACE "([][+.*()^$?|\\\\])" "\\\\\\1" build_root_regex "${build_root}")
foreach(tool IN LISTS BINARIES)
    file(STRINGS "${tools_bin}/${tool}${exe}" leaked
         REGEX "${build_root_regex}" LIMIT_COUNT 1)
    if(leaked)
        message(FATAL_ERROR "${tool}${exe} holds the path ${build_root}")
    endif()
endforeach()
check_version("${tools_bin}")
write_stamp("${stamp}")
message(STATUS "${tools_bin} holds the tools and clang of LLVM ${version} for ${HOST}")
