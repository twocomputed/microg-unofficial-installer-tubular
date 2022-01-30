#!/sbin/sh
# shellcheck disable=SC3010

# SC3010: In POSIX sh, [[ ]] is undefined

# SPDX-FileCopyrightText: (c) 2016-2019, 2021 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

### INIT ENV ###
export TZ=UTC
export LANG=en_US

unset LANGUAGE
unset LC_ALL
unset UNZIP
unset UNZIP_OPTS
unset UNZIPOPT

### GLOBAL VARIABLES ###

export INSTALLER=1
TMP_PATH="$2"

CPU=false
CPU64=false
LEGACY_ARM=false
LEGACY_ANDROID=false
OLD_ANDROID=false
FAKE_SIGN=false
SYS_PATH=''
MARKET_FILENAME=''
INSTALLATION_SETTINGS_FILE='ug.prop'


### FUNCTIONS ###

# shellcheck source=SCRIPTDIR/inc/common.sh
. "${TMP_PATH}/inc/common.sh"


### CODE ###

if ! is_mounted '/system'; then
  mount '/system'
  if ! is_mounted '/system'; then ui_error '/system cannot be mounted'; fi
fi

if test -f '/system_root/system/build.prop'; then
  SYS_PATH='/system_root/system';
elif test -f '/system/system/build.prop'; then
  SYS_PATH='/system/system';
elif test -f '/system/build.prop'; then
  SYS_PATH='/system';
else
  ui_error 'The ROM cannot be found'
fi

cp -pf "${SYS_PATH}/build.prop" "${TMP_PATH}/build.prop"  # Cache the file for faster access

PRIVAPP_PATH="${SYS_PATH}/app"
if [[ -d "${SYS_PATH}/priv-app" ]]; then PRIVAPP_PATH="${SYS_PATH}/priv-app"; fi  # Detect the position of the privileged apps folder

API=$(build_getprop 'build\.version\.sdk')
if [[ "${API}" -ge 21 ]]; then
  :  ### New Android versions
elif [[ "${API}" -ge 19 ]]; then
  OLD_ANDROID=true
elif [[ "${API}" -ge 9 ]]; then
  LEGACY_ANDROID=true
  OLD_ANDROID=true
elif [[ "${API}" -ge 1 ]]; then
  ui_error 'Your Android version is too old'
else
  ui_error 'Invalid API level'
fi

ABI_LIST=','$(build_getprop 'product\.cpu\.abi')','$(build_getprop 'product\.cpu\.abi2')','$(build_getprop 'product\.cpu\.abilist')','
if is_substring ',x86,' "${ABI_LIST}"; then
  CPU='x86'
elif is_substring ',armeabi-v7a,' "${ABI_LIST}"; then
  CPU='armeabi-v7a'
elif is_substring ',armeabi,' "${ABI_LIST}"; then
  CPU='armeabi'
fi

if is_substring ',x86_64,' "${ABI_LIST}"; then
  CPU64='x86_64'
elif is_substring ',arm64-v8a,' "${ABI_LIST}"; then
  CPU64='arm64-v8a'
fi

if is_substring ',armeabi,' "${ABI_LIST}" && ! is_substring ',armeabi-v7a,' "${ABI_LIST}"; then LEGACY_ARM=true; fi

if [[ "${LIVE_SETUP}" -eq 1 ]]; then
  choose 'What market app do you want to install?' '+) Google Play Store' '-) FakeStore'
  if [[ "$?" -eq 3 ]]; then export MARKET='PlayStore'; else export MARKET='FakeStore'; fi
fi

if [[ "${MARKET}" == 'PlayStore' ]]; then
  if [[ "${PLAYSTORE_VERSION}" == 'auto' ]]; then
    if [[ "${OLD_ANDROID}" != true ]]; then
      MARKET_FILENAME="${MARKET}-recent.apk"
    else
      MARKET_FILENAME="${MARKET}-legacy.apk"
    fi
  else
    MARKET_FILENAME="${MARKET}-${PLAYSTORE_VERSION}.apk"
  fi
else
  MARKET_FILENAME="${MARKET}.apk"
fi

# Info
ui_msg ''
ui_msg '---------------------------'
ui_msg 'microG unofficial installer'
ui_msg 'v1.0.35-alpha'
ui_msg '(by ale5000)'
ui_msg '---------------------------'
ui_msg ''
ui_msg "API: ${API}"
ui_msg "Detected CPU arch: ${CPU}"
ui_msg "Detected 64-bit CPU arch: ${CPU64}"
ui_msg "System path: ${SYS_PATH}"
ui_msg "Privileged apps: ${PRIVAPP_PATH}"

zip_extract_file "${SYS_PATH}/framework/framework-res.apk" 'AndroidManifest.xml' "${TMP_PATH}/framework-res"
XML_MANIFEST="${TMP_PATH}/framework-res/AndroidManifest.xml"
# Detect the presence of the fake signature permission
# Note: It won't detect it if signature spoofing doesn't require a permission, but it is still fine for our case
if search_ascii_string_as_utf16_in_file 'android.permission.FAKE_PACKAGE_SIGNATURE' "${XML_MANIFEST}" || search_ascii_string_in_file 'android.permission.FAKE_PACKAGE_SIGNATURE' "${XML_MANIFEST}"; then
  FAKE_SIGN=true
fi
ui_msg "Fake signature: ${FAKE_SIGN}"

ui_msg ''

if [[ ${CPU} == false && ${CPU64} == false ]]; then
  ui_error "Unsupported CPU, ABI list: ${ABI_LIST}"
fi

# Check the existance of the libraries folders
if [[ ${OLD_ANDROID} == true ]]; then
  if [[ ${CPU} != false && ! -d "${SYS_PATH}/lib" ]]; then create_dir "${SYS_PATH}/lib"; fi
  if [[ ${CPU64} != false && ! -d "${SYS_PATH}/lib64" ]]; then create_dir "${SYS_PATH}/lib64"; fi
fi

# Extracting
ui_msg 'Extracting...'
custom_package_extract_dir 'files' "${TMP_PATH}"
custom_package_extract_dir 'addon.d' "${TMP_PATH}"

# Setting up permissions
ui_debug 'Setting up permissions...'
set_std_perm_recursive "${TMP_PATH}/files"
set_std_perm_recursive "${TMP_PATH}/addon.d"
set_perm 0 0 0755 "${TMP_PATH}/addon.d/00-1-microg.sh"

# Fallback to FakeStore if the selected market is missing
if ! test -f "${TMP_PATH}/files/variants/${MARKET_FILENAME}"; then MARKET_FILENAME='FakeStore.apk'; fi
ui_msg "Selected market app: ${MARKET_FILENAME}"

# Verifying
ui_msg_sameline_start 'Verifying... '
if verify_sha1 "${TMP_PATH}/files/variants/priv-app/GmsCore-mapbox.apk" 'b57f0505700a1f6927cd2c839f74626bfac4ba22' &&
   verify_sha1 "${TMP_PATH}/files/variants/priv-app/GmsCore-vtm.apk" 'fb4e019006a061a7027c6e9a79db26965f153ce1' &&
   verify_sha1 "${TMP_PATH}/files/variants/priv-app/GmsCore-vtm-legacy.apk" 'da538490beadc760a7a8519ec5ed367f19ae8d7b' &&
   verify_sha1 "${TMP_PATH}/files/priv-app/GoogleServicesFramework.apk" 'f9907df2e2c8fd20cd2e928821641fa01fca09ce' &&
   verify_sha1 "${TMP_PATH}/files/priv-app/DroidGuard.apk" 'd1116dfdff529892d3e2dd793dd93a4d987c1c5f' &&
   verify_sha1 "${TMP_PATH}/files/variants/app/NewPipe.apk" '6eb07f807752db95602ab15fb9819e35e079d0e2' &&
   verify_sha1 "${TMP_PATH}/files/variants/app/NewPipeLegacy.apk" '95413ee2bf576e4c7b0bdc9e9e79fd2187d444a9' &&
   verify_sha1 "${TMP_PATH}/files/app/DejaVuBackend.apk" '3344e0fa38b57980125bc3049a0cb3dff86a22f2' &&
   verify_sha1 "${TMP_PATH}/files/app/IchnaeaNlpBackend.apk" 'ef9fad611ab2cf2e68cdc7d05af4496998e8d3b5' &&
   verify_sha1 "${TMP_PATH}/files/app/NominatimGeocoderBackend.apk" '40b0917e9805cdab5abc53925f8732bff9ba8d84' &&
   ###verify_sha1 "${TMP_PATH}/files/app/PlayGames.apk" 'c99c27053bf518dd3d08449e9478b43de0da50ed' &&
   verify_sha1 "${TMP_PATH}/files/framework/com.google.android.maps.jar" '14ce63b333e3c53c793e5eabfd7d554f5e7b56c7' &&
   verify_sha1 "${TMP_PATH}/files/app-legacy/LegacyNetworkLocation.apk" '8121295640985fad6c5b98890a156aafd18c2053' &&
   verify_sha1 "${TMP_PATH}/files/variants/PlayStore-recent.apk" '6c60fa863dd7befef49082c0dcf6278947a09333' &&
   verify_sha1 "${TMP_PATH}/files/variants/PlayStore-legacy.apk" 'd78b377db43a2bc0570f37b2dd0efa4ec0b95746' &&
   verify_sha1 "${TMP_PATH}/files/variants/FakeStore.apk" '1028f11133ec0a9a41fcd6615837124b61abd251'
then
  ui_msg_sameline_end 'OK'
else
  ui_msg_sameline_end 'ERROR'
  ui_error 'Verification failed'
fi

# Handle variants
if [[ "${API}" -ge 14 ]]; then
  if [[ "${GMSCORE_VERSION}" == 'auto' && "${CPU}" != 'armeabi' ]]; then
    move_rename_file "${TMP_PATH}/files/variants/priv-app/GmsCore-mapbox.apk" "${TMP_PATH}/files/priv-app/GmsCore.apk"
  else
    move_rename_file "${TMP_PATH}/files/variants/priv-app/GmsCore-vtm.apk" "${TMP_PATH}/files/priv-app/GmsCore.apk"
  fi
else
  move_rename_file "${TMP_PATH}/files/variants/priv-app/GmsCore-vtm-legacy.apk" "${TMP_PATH}/files/priv-app/GmsCore.apk"
fi

if [[ "${INSTALL_NEWPIPE}" -ne 0 ]]; then
  if [[ "${API}" -ge 19 ]]; then
    move_rename_file "${TMP_PATH}/files/variants/app/NewPipe.apk" "${TMP_PATH}/files/app/NewPipe.apk"
  elif [[ "${API}" -ge 16 ]]; then
    move_rename_file "${TMP_PATH}/files/variants/app/NewPipeLegacy.apk" "${TMP_PATH}/files/app/NewPipe.apk"
  fi
fi

# Extracting libs
ui_msg 'Extracting libs...'
create_dir "${TMP_PATH}/libs"
zip_extract_dir "${TMP_PATH}/files/priv-app/GmsCore.apk" 'lib' "${TMP_PATH}/libs"

# Setting up libs permissions
ui_debug 'Setting up libs permissions...'
set_std_perm_recursive "${TMP_PATH}/libs"

# MOUNT /data PARTITION
if ! is_mounted '/data'; then
  mount '/data'
  if ! is_mounted '/data'; then ui_error '/data cannot be mounted'; fi
fi

# Resetting Android runtime permissions
if test "${API}" -ge 23; then
  if [[ -e '/data/system/users/0/runtime-permissions.xml' ]]; then
    if ! grep -q 'com.google.android.gms' /data/system/users/*/runtime-permissions.xml; then
      # Purge the runtime permissions to prevent issues when the user flash this on a dirty install
      ui_msg "Resetting Android runtime permissions..."
      delete /data/system/users/*/runtime-permissions.xml
    fi
  fi
fi

# Clean some Google Apps, microG and previous installations
# shellcheck source=SCRIPTDIR/uninstall.sh
. "${TMP_PATH}/uninstall.sh"

# Configuring default Android permissions
if test "${API}" -ge 23; then
  ui_debug 'Configuring default Android permissions...'
  if [[ ! -e "${SYS_PATH}/etc/default-permissions" ]]; then
    ui_msg 'Creating the default permissions folder...'
    create_dir "${SYS_PATH}/etc/default-permissions"
  fi

  if test "${FAKE_SIGN}" == true; then
    echo '        <permission name="android.permission.FAKE_PACKAGE_SIGNATURE" fixed="true"/>' > "${TMP_PATH}/fake-sign-perm.dat"
    replace_line_in_file "${TMP_PATH}/files/etc/default-permissions/google-permissions.xml" '<!-- %FAKE_PACKAGE_SIGNATURE% -->' "${TMP_PATH}/fake-sign-perm.dat"
  fi
  copy_dir_content "${TMP_PATH}/files/etc/default-permissions" "${SYS_PATH}/etc/default-permissions"
else
  delete_recursive "${TMP_PATH}/files/etc/default-permissions"
fi

if test "${LIVE_SETUP}" -eq 1; then
  choose 'Do you want to reset GMS data of all apps?' '+) Yes' '-) No'
  if test "$?" -eq 3; then reset_gms_data_of_all_apps; fi
elif test "${RESET_GMS_DATA_OF_ALL_APPS}" -eq 1; then
  reset_gms_data_of_all_apps
fi

# UNMOUNT /data PARTITION
unmount '/data'

# Preparing
ui_msg 'Preparing...'

if [[ "${LEGACY_ANDROID}" == true ]]; then
  move_dir_content "${TMP_PATH}/files/app-legacy" "${TMP_PATH}/files/app"
fi
delete_recursive "${TMP_PATH}/files/app-legacy"

if test "${API}" -lt 21; then delete "${TMP_PATH}/files/etc/sysconfig/google.xml"; fi
if test "${API}" -lt 18; then delete "${TMP_PATH}/files/app/DejaVuBackend.apk"; fi

move_rename_file "${TMP_PATH}/files/variants/${MARKET_FILENAME}" "${TMP_PATH}/files/priv-app/Phonesky.apk"
delete_recursive "${TMP_PATH}/files/variants"

if [[ "${OLD_ANDROID}" != true ]]; then
  # Move apps into subdirs
  for entry in "${TMP_PATH}/files/priv-app"/*; do
    path_without_ext=$(remove_ext "${entry}")

    create_dir "${path_without_ext}"
    mv -f "${entry}" "${path_without_ext}"/
  done
  for entry in "${TMP_PATH}/files/app"/*; do
    path_without_ext=$(remove_ext "${entry}")

    create_dir "${path_without_ext}"
    mv -f "${entry}" "${path_without_ext}"/
  done

  # The name of the following architectures remain unchanged: x86, x86_64, mips, mips64
  move_rename_dir "${TMP_PATH}/libs/lib/arm64-v8a" "${TMP_PATH}/libs/lib/arm64"
  if [[ "${LEGACY_ARM}" != true ]]; then
    move_rename_dir "${TMP_PATH}/libs/lib/armeabi-v7a" "${TMP_PATH}/libs/lib/arm"
    delete_recursive "${TMP_PATH}/libs/lib/armeabi"
  else
    move_rename_dir "${TMP_PATH}/libs/lib/armeabi" "${TMP_PATH}/libs/lib/arm"
    delete_recursive "${TMP_PATH}/libs/lib/armeabi-v7a"
  fi

  create_dir "${TMP_PATH}/files/priv-app/GmsCore/lib"
  move_dir_content "${TMP_PATH}/libs/lib" "${TMP_PATH}/files/priv-app/GmsCore/lib"
fi

# Installing
ui_msg 'Installing...'
copy_dir_content "${TMP_PATH}/files/priv-app" "${PRIVAPP_PATH}"
copy_dir_content "${TMP_PATH}/files/app" "${SYS_PATH}/app"
copy_dir_content "${TMP_PATH}/files/framework" "${SYS_PATH}/framework"
if test "${API}" -lt 26; then
  delete "${TMP_PATH}/files/etc/permissions/privapp-permissions-google.xml"
else
  if test "${FAKE_SIGN}" == true; then
    echo '        <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>' > "${TMP_PATH}/fake-sign-perm.dat"
    replace_line_in_file "${TMP_PATH}/files/etc/permissions/privapp-permissions-google.xml" '<!-- %FAKE_PACKAGE_SIGNATURE% -->' "${TMP_PATH}/fake-sign-perm.dat"
  fi
fi
copy_dir_content "${TMP_PATH}/files/etc/permissions" "${SYS_PATH}/etc/permissions"
if test "${API}" -ge 21; then
  copy_dir_content "${TMP_PATH}/files/etc/sysconfig" "${SYS_PATH}/etc/sysconfig"
fi
copy_dir_content "${TMP_PATH}/files/etc/org.fdroid.fdroid" "${SYS_PATH}/etc/org.fdroid.fdroid"

if [[ "${OLD_ANDROID}" == true ]]; then
  if [[ "${CPU}" != false ]]; then
    copy_dir_content "${TMP_PATH}/libs/lib/${CPU}" "${SYS_PATH}/lib"
  fi
  if [[ "${CPU64}" != false ]]; then
    copy_dir_content "${TMP_PATH}/libs/lib/${CPU64}" "${SYS_PATH}/lib64"
  fi

  if test -e "${SYS_PATH}/vendor/lib/libvtm-jni.so"; then
    delete "${SYS_PATH}/vendor/lib/libvtm-jni.so"
  fi
  if test -e "${SYS_PATH}/vendor/lib64/libvtm-jni.so"; then
    delete "${SYS_PATH}/vendor/lib64/libvtm-jni.so"
  fi
fi
delete_recursive "${TMP_PATH}/libs"

USED_SETTINGS_PATH="${TMP_PATH}/files/etc/zips"

create_dir "${USED_SETTINGS_PATH}"
echo 'type="GmsCore"' > "${USED_SETTINGS_PATH}/${INSTALLATION_SETTINGS_FILE}"
echo 'gmscore_build_type="official"' >> "${USED_SETTINGS_PATH}/${INSTALLATION_SETTINGS_FILE}"
set_perm 0 0 0644 "${USED_SETTINGS_PATH}/${INSTALLATION_SETTINGS_FILE}"
create_dir "${SYS_PATH}/etc/zips"
copy_dir_content "${USED_SETTINGS_PATH}" "${SYS_PATH}/etc/zips"

# Workaround for when the database of GSF is accessed directly
if test -d '/data/data/com.google.android.gsf'; then
  ln -sfv '/data/data/com.google.android.gms/databases' '/data/data/com.google.android.gsf/databases' || ui_error 'Symlink creation failed'
fi

# Install survival script
if [[ -d "${SYS_PATH}/addon.d" ]]; then
  if [[ "${LEGACY_ANDROID}" == true ]]; then
    :  ### Skip it
  elif [[ "${OLD_ANDROID}" == true ]]; then
    :  ### Not ready yet
  else
    ui_msg 'Installing survival script...'
    write_file_list "${TMP_PATH}/files" "${TMP_PATH}/files/" "${TMP_PATH}/backup-filelist.lst"
    replace_line_in_file "${TMP_PATH}/addon.d/00-1-microg.sh" '%PLACEHOLDER-1%' "${TMP_PATH}/backup-filelist.lst"
    copy_file "${TMP_PATH}/addon.d/00-1-microg.sh" "${SYS_PATH}/addon.d"
  fi
fi

unmount '/system'

touch "${TMP_PATH}/installed"
ui_msg 'Done.'
