#!/usr/bin/env sh
# @name Device list downloader
# @brief It download the device list and convert it in the proper format
# @author ale5000
# Get the latest version from here: https://github.com/micro5k/microg-unofficial-installer/tree/main/utils

# SPDX-FileCopyrightText: (c) 2023 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

# shellcheck disable=SC3043 # In POSIX sh, local is undefined

set -u
# shellcheck disable=SC3040,SC3041,SC2015
{
  # Unsupported set options may cause the shell to exit (even without set -e), so first try them in a subshell to avoid this issue
  (set -o posix 2> /dev/null) && set -o posix || true
  (set +H 2> /dev/null) && set +H || true
  (set -o pipefail) && set -o pipefail || true
}

show_error()
{
  printf 1>&2 '\033[1;31m%s\033[0m\n' "ERROR: ${*}"
}

show_info()
{
  printf '\033[1;32m%s\033[0m\n' "${*}"
}

pause_if_needed()
{
  # shellcheck disable=SC3028 # In POSIX sh, SHLVL is undefined
  if test "${CI:-false}" = 'false' && test "${SHLVL:-}" = '1' && test -t 1 && test -t 2; then
    printf 1>&2 '\n\033[1;32m' || true
    # shellcheck disable=SC3045
    IFS='' read 1>&2 -r -s -n 1 -p 'Press any key to continue...' _ || true
    printf 1>&2 '\033[0m\n' || true
  fi
}

readonly WGET_CMD='wget'
readonly DL_UA='Mozilla/5.0 (Linux x86_64; rv:102.0) Gecko/20100101 Firefox/102.0'
readonly DL_ACCEPT_HEADER='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
readonly DL_ACCEPT_LANG_HEADER='Accept-Language: en-US,en;q=0.5'

dl()
{
  "${WGET_CMD:?}" -q -O "${2:?}" -U "${DL_UA:?}" --header "${DL_ACCEPT_HEADER:?}" --header "${DL_ACCEPT_LANG_HEADER:?}" --no-cache -- "${1:?}" || return "${?}"
}

dl_and_convert_device_list()
{
  local _path _file _var

  # shellcheck disable=SC3028
  if test -n "${UTILS_DATA_DIR:-}"; then
    _path="${UTILS_DATA_DIR:?}"
  elif test -n "${BASH_SOURCE:-}" && _path="$(dirname "${BASH_SOURCE:?}")/data"; then # Expanding an array without an index gives the first element (it is intended)
    :
  elif test -n "${0:-}" && _path="$(dirname "${0:?}")/data"; then
    :
  else
    _path='./data'
  fi

  if mkdir -p "${_path:?}"; then
    _file="${_path:?}/device-list.csv"
  else
    return 1
  fi

  rm -f "${_file:?}-temp" || return "${?}"
  dl 'https://storage.googleapis.com/play_public/supported_devices.csv' "${_file:?}-temp" || return "${?}"

  iconv -o "${_file:?}-temp" -f 'UTF-16LE' -t 'UTF-8' -- "${_file:?}-temp" || return "${?}"
  _var="$(printf '\342\200\235')"
  sed -i "s/${_var:?}/\"/g" "${_file:?}-temp" || return "${?}"
  iconv -c -o "${_file:?}" -f 'UTF-8' -t 'WINDOWS-1252' -- "${_file:?}-temp" || return "${?}"
  rm -f "${_file:?}-temp" || return "${?}"
}

main()
{
  if dl_and_convert_device_list; then
    show_info 'File downloaded correctly :)'
  else
    show_error 'Failed!!!'
  fi

  pause_if_needed
}

main
