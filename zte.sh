#!/usr/bin/env bash

# ZTE router/modem CLI
#
# This is the single maintained entry point for the toolkit.  It intentionally
# keeps credentials out of the file: set ZTE_HASH, set ZTE_HASH_FILE, or enter
# the router's already-hashed password at the prompt.
#
# The command set is based on the live MU300 web UI discovered at runtime:
# read-only status, radio, Wi-Fi, client, SMS, system and UI views; guarded
# configuration forms; network reconnects; and reboot/shutdown/reset actions.

set -o pipefail

PROGRAM=${0##*/}
VERSION="2.0.0"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SAVED_LOGIN="$SCRIPT_DIR/.zte-hash"
RELOGIN=0

IP=${ZTE_IP:-192.168.5.1}
SCHEME=${ZTE_SCHEME:-http}
CONNECT_TIMEOUT=${ZTE_CONNECT_TIMEOUT:-3}
MAX_TIME=${ZTE_MAX_TIME:-10}
DEFAULT_SPEED_INTERVAL=1
DEFAULT_WATCH_INTERVAL=5

JSON_OUTPUT=0
REDACT=0
DRY_RUN=0
ASSUME_YES=0
UNSAFE=0
FACTORY_ACK=0
NO_COLOR=0
HASH_FILE=${ZTE_HASH_FILE:-}
HASH_FILE_EXPLICIT=0
[[ -n ${ZTE_HASH_FILE:-} ]] && HASH_FILE_EXPLICIT=1
PASSWORD=${ZTE_PASSWORD:-}
PASSWORD_FILE=${ZTE_PASSWORD_FILE:-}

HASH=${ZTE_HASH:-}
JAR=
BASE_URL=
LOGIN_URL=
GET_URL=
SET_URL=

BOLD=
DIM=
RESET=
GREEN=
CYAN=
YELLOW=
MAGENTA=

FULL_CMD="wa_inner_version,cr_version,wa_version,hardware_version,web_version,imei,imsi,iccid,msisdn,sim_msisdn,mac_address,battery_value,battery_status,battery_charging,network_type,network_provider,signalbar,rssi,lte_rsrp,lte_rsrq,lte_snr,lte_pci,lte_ca_pcell_band,lte_ca_scell_band,lte_ca_pcell_bandwidth,lte_ca_scell_bandwidth,lte_ca_pcell_arfcn,lte_ca_scell_arfcn,lte_multi_ca_scell_info,fiveg_rsrp,fiveg_rsrq,fiveg_sinr,fiveg_pci,nr5g_rsrp,nr5g_rsrq,nr5g_sinr,nr5g_pci,nr5g_band,nr5g_cell_id,wan_lte_ca,wan_active_band,wan_active_channel,cell_id,lac_code,ppp_status,wan_ipaddr,wan_ipv6addr,ipv6_wan_ipaddr,monthly_rx_bytes,monthly_tx_bytes,realtime_rx_bytes,realtime_tx_bytes,realtime_time,monthly_time,m_ssid,m_hide_ssid,wifi_enable,wifi_onoff_state,wifi_dev_num,guest_switch,dns_mode,prefer_dns,standby_dns,sms_unread_num,sms_dev_unread_num,sms_sim_unread_num"
STATUS_CMD="signalbar,network_type,network_provider,lte_rsrp,lte_snr,ppp_status,wan_ipaddr"
RADIO_CMD="network_type,network_provider,signalbar,rssi,lte_rsrp,lte_rsrq,lte_snr,lte_pci,lte_ca_pcell_band,lte_ca_scell_band,lte_ca_pcell_bandwidth,lte_ca_scell_bandwidth,lte_ca_pcell_arfcn,lte_ca_scell_arfcn,lte_multi_ca_scell_info,fiveg_rsrp,fiveg_rsrq,fiveg_sinr,fiveg_pci,nr5g_rsrp,nr5g_rsrq,nr5g_sinr,nr5g_pci,nr5g_band,nr5g_cell_id,wan_lte_ca,wan_active_band,wan_active_channel,cell_id,lac_code,ppp_status"
WIFI_CMD="wifi_onoff_state,guest_switch,wifi_lbd_enable,wifi_chip1_ssid1_ssid,wifi_chip2_ssid1_ssid,wifi_chip1_ssid2_ssid,wifi_chip2_ssid2_ssid,wifi_chip1_ssid1_switch_onoff,wifi_chip2_ssid1_switch_onoff,wifi_chip1_ssid2_switch_onoff,wifi_chip2_ssid2_switch_onoff,wifi_chip1_ssid1_auth_mode,wifi_chip2_ssid1_auth_mode,wifi_chip1_ssid1_max_access_num,wifi_chip2_ssid1_max_access_num,lan_ipaddr,mac_address"
SYSTEM_CMD="wa_inner_version,cr_version,wa_version,web_version,hardware_version,ppp_status,modem_main_state,opms_wan_mode,lan_ipaddr,mac_address,battery_value,battery_status,battery_charging,wifi_chip_temp,therm_pa_level,therm_pa_frl_level,therm_tj_level,pm_sensor_pa1,pm_sensor_mdm,pm_modem_5g,mgmt_quicken_power_on,need_hard_reboot"
SMS_CMD="sms_unread_num,sms_dev_unread_num,sms_sim_unread_num,sms_nv_rev_total,sms_nv_send_total,sms_nv_draftbox_total,sms_sim_rev_total,sms_sim_send_total,sms_sim_draftbox_total"
NETWORK_CMD="opms_wan_mode,opms_wan_auto_mode,ConnectionMode,ppp_status,network_type,network_provider,wan_ipaddr,ipv6_wan_ipaddr,lan_ipaddr,prefer_dns,standby_dns"

# These are menu entries from the router's current UI configuration.  They are
# informational: the CLI does not pretend that every firmware exposes every
# page or field.
UI_ROUTES=(
  "home|Home dashboard|read"
  "setting|Settings|menu"
  "network/dial_setting|Dial settings|read/write"
  "network/net_select|Network selection|read/write"
  "network/apn_setting|APN settings|read/write"
  "network/internet_setting|Internet settings|read/write"
  "wifi/wifi_main_24G|Wi-Fi settings|read/write"
  "wifi/station_info|Connected stations|read"
  "adm/password|Password management|write"
  "adm/pin|SIM PIN management|write"
  "adm/lan|LAN/DHCP|read/write"
  "adm/restore|Restore/reset|write"
  "adm/others|Other device settings|read/write"
  "adm/network_info|Network information|read"
  "adm/diagnosis|Diagnostics|read/write"
  "adm/performance_mode|Performance mode|read/write"
  "adm/access_license|Access license|read/write"
  "adm/usb_internet_protocol|USB internet protocol|read/write"
  "adm/network_debug|Network debug|read/write"
  "adm/indicator_light|Indicator light|read/write"
  "adm/sim_switch|SIM slot|read/write"
  "adm/usb_port|USB port|read/write"
  "adm/samba|Samba|read/write"
  "adm/online_auth|Online authentication|read/write"
  "status/traffic_alert|Traffic alert|read/write"
  "update/ota_update|OTA update|write"
  "sms/smslist|SMS messages|read/write"
  "sms/sms_setting|SMS settings|read/write"
  "change_password|Change password|write"
)

# Known UI write endpoints.  `form` only accepts these unless --unsafe is
# explicitly supplied.  This prevents a typo from becoming an arbitrary CGI
# request while retaining an escape hatch for firmware-specific additions.
KNOWN_FORMS=" SET_BEARER_PREFERENCE switchWiFiChip SET_WIFI_INFO SET_WIFI_AP_MODE SET_WIFI_SSID1_SETTINGS SET_WIFI_SSID2_SETTINGS SET_WIFI_SSID1_SSID2_SETTINGS SET_WIFI_SECURITY_INFO SET_CONNECTION_MODE CONNECT_NETWORK DISCONNECT_NETWORK OPERATION_MODE SET_NETWORK APN_PROC APN_PROC_EX WIFI_ADVANCE_SET WIFI_MAC_FILTER SET_WIFI_BAND DHCP_SETTING SET_DEVICE_MTU RESET_DATA_COUNTER SEND_SMS SAVE_SMS DELETE_SMS ALL_DELETE_SMS SET_MSG_READ SET_SIM_SLOT SET_DEVICE_LED INDICATOR_LIGHT_SETTING USB_PORT_SETTING SAMBA_SETTING REBOOT_DEVICE SHUTDOWN_DEVICE RESTORE_FACTORY_SETTINGS_EXTEND MGMT_CONTROL_POWER_ON_SPEED CELL_LOCK NR_BAND_LOCK NR5G_LOCK_CELL_SET UNLOCK_ALL_CELL WAN_PERFORM_NR5G_BAND_LOCK PS_NO_SERVICE_RESTART_SET SET_UPGRADE_NOTICE SET_NV"

usage_error() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_dependencies() {
  local missing=() command_name
  for command_name in curl jq sha256sum awk mktemp; do
    has_command "$command_name" || missing+=("$command_name")
  done
  if ((${#missing[@]})); then
    die "missing required command(s): ${missing[*]}"
  fi
}

validate_positive_number() {
  local label=$1 value=$2
  [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || usage_error "$label must be a positive number"
  awk -v value="$value" 'BEGIN { exit !(value > 0) }' ||
    usage_error "$label must be greater than zero"
}

validate_interval() {
  validate_positive_number "interval" "$1"
}

validate_host() {
  [[ $IP =~ ^[A-Za-z0-9_.:-]+$ ]] || usage_error "invalid router address: $IP"
  [[ $SCHEME == http || $SCHEME == https ]] ||
    usage_error "scheme must be http or https"
}

parse_options() {
  COMMAND=
  ARGS=()
  while (($#)); do
    case $1 in
      --ip)
        (($# >= 2)) || usage_error "--ip needs a value"
        IP=$2
        shift 2
        ;;
      --scheme)
        (($# >= 2)) || usage_error "--scheme needs http or https"
        SCHEME=$2
        shift 2
        ;;
      --timeout)
        (($# >= 2)) || usage_error "--timeout needs a value"
        CONNECT_TIMEOUT=$2
        MAX_TIME=$2
        shift 2
        ;;
      --connect-timeout)
        (($# >= 2)) || usage_error "--connect-timeout needs a value"
        CONNECT_TIMEOUT=$2
        shift 2
        ;;
      --max-time)
        (($# >= 2)) || usage_error "--max-time needs a value"
        MAX_TIME=$2
        shift 2
        ;;
      --hash-file)
        (($# >= 2)) || usage_error "--hash-file needs a path"
        HASH_FILE=$2
        HASH_FILE_EXPLICIT=1
        shift 2
        ;;
      --relogin)
        RELOGIN=1
        shift
        ;;
      --password-file)
        (($# >= 2)) || usage_error "--password-file needs a path"
        PASSWORD_FILE=$2
        shift 2
        ;;
      --json)
        JSON_OUTPUT=1
        shift
        ;;
      --redact)
        REDACT=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --unsafe)
        UNSAFE=1
        shift
        ;;
      --confirm-factory-reset)
        FACTORY_ACK=1
        shift
        ;;
      --no-color)
        NO_COLOR=1
        shift
        ;;
      --)
        shift
        while (($#)); do
          if [[ -z $COMMAND ]]; then COMMAND=$1; else ARGS+=("$1"); fi
          shift
        done
        ;;
      -h|--help)
        COMMAND=help
        shift
        ;;
      --version)
        COMMAND=version
        shift
        ;;
      -*)
        usage_error "unknown option: $1"
        ;;
      *)
        if [[ -z $COMMAND ]]; then COMMAND=$1; else ARGS+=("$1"); fi
        shift
        ;;
    esac
  done
  COMMAND=${COMMAND:-status}
}

init_colors() {
  if [[ $JSON_OUTPUT -eq 0 && $NO_COLOR -eq 0 && -t 1 && ${TERM:-dumb} != dumb ]] && has_command tput; then
    BOLD=$(tput bold 2>/dev/null || true)
    DIM=$(tput dim 2>/dev/null || true)
    RESET=$(tput sgr0 2>/dev/null || true)
    GREEN=$(tput setaf 2 2>/dev/null || true)
    CYAN=$(tput setaf 6 2>/dev/null || true)
    YELLOW=$(tput setaf 3 2>/dev/null || true)
    MAGENTA=$(tput setaf 5 2>/dev/null || true)
  fi
}

load_hash() {
  if [[ -n $HASH ]]; then
    return 0
  fi
  if [[ -z $HASH_FILE ]]; then
    local config_root=${XDG_CONFIG_HOME:-}
    [[ -n $config_root || -z ${HOME:-} ]] || config_root="$HOME/.config"
    if [[ -n $config_root && -f "$config_root/zte/hash" && -r "$config_root/zte/hash" ]]; then
      HASH_FILE="$config_root/zte/hash"
    fi
  fi
  if [[ -n $HASH_FILE ]]; then
    if [[ -f $HASH_FILE && -r $HASH_FILE ]]; then
      IFS= read -r HASH < "$HASH_FILE" || true
      HASH=${HASH%$'\r'}
    elif ((HASH_FILE_EXPLICIT)); then
      die "cannot read ZTE hash file: $HASH_FILE"
    fi
  fi
  if [[ -z $HASH && -t 0 && -t 1 ]]; then
    printf 'ZTE hashed password: ' >&2
    IFS= read -r -s HASH || true
    printf '\n' >&2
  elif [[ -z $HASH ]]; then
    die 'set ZTE_HASH, set ZTE_HASH_FILE, or run interactively to enter the hashed password'
  fi
  [[ $HASH != *[[:space:]]* ]] || die 'the hash file must contain one value with no spaces'
  [[ -n $HASH ]] || die 'the hashed password is empty'
}

load_password() {
  if [[ -n $PASSWORD ]]; then return 0; fi
  if [[ -n $PASSWORD_FILE ]]; then
    [[ -f $PASSWORD_FILE && -r $PASSWORD_FILE ]] || die "cannot read ZTE password file: $PASSWORD_FILE"
    IFS= read -r PASSWORD < "$PASSWORD_FILE" || true
    PASSWORD=${PASSWORD%$'\r'}
  elif [[ -t 0 && -t 1 ]]; then
    printf 'ZTE router password: ' >&2
    IFS= read -r -s PASSWORD || true
    printf '\n' >&2
  else
    die 'set ZTE_PASSWORD, set ZTE_PASSWORD_FILE, or use an interactive terminal'
  fi
  [[ -n $PASSWORD ]] || die 'the router password is empty'
}

save_generated_hash() {
  local config_root=${XDG_CONFIG_HOME:-}
  [[ -n $config_root || -z ${HOME:-} ]] || config_root="$HOME/.config"
  [[ -n $config_root ]] || return 0
  install -d -m 700 "$config_root/zte" || die 'could not create the private ZTE config directory'
  local cache="$config_root/zte/hash" tmp
  tmp=$(mktemp "$config_root/zte/.hash.XXXXXX") || die 'could not create the generated hash file'
  chmod 600 "$tmp"
  printf '%s\n' "$1" > "$tmp"
  mv -f -- "$tmp" "$cache" || die 'could not save the generated hash'
  chmod 600 "$cache"
}

cleanup() {
  if [[ -n $JAR && -e $JAR ]]; then
    rm -f -- "$JAR"
  fi
  HASH=
  PASSWORD=
}

on_signal() {
  exit 130
}

init_session() {
  umask 077
  JAR=$(mktemp "${TMPDIR:-/tmp}/zte-cli.XXXXXX") || die 'could not create a private cookie jar'
  chmod 600 "$JAR" || die 'could not protect the cookie jar'
  BASE_URL="${SCHEME}://${IP%/}"
  LOGIN_URL="$BASE_URL/goform/goform_set_cmd_process"
  GET_URL="$BASE_URL/goform/goform_get_cmd_process"
  SET_URL="$BASE_URL/goform/goform_set_cmd_process"
  trap cleanup EXIT
  trap on_signal INT TERM HUP
}

curl_args=(curl --noproxy '*' --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" --fail-with-body --silent --show-error)

json_is_valid() {
  jq -e 'type == "object" or type == "array"' >/dev/null 2>&1 <<<"$1"
}

fetch_login_salt() {
  local response
  response=$("${curl_args[@]}" -H "Referer: $BASE_URL/" --get \
    --data-urlencode 'isTest=false' --data-urlencode 'multi_data=1' \
    --data-urlencode 'cmd=LD' "$GET_URL") || die 'could not fetch the router login salt (LD)'
  jq -er '.LD // empty' <<<"$response" || die 'router returned no login salt (LD)'
}

login() {
  local response rc login_value ld generated=0 answer saved
  if ((RELOGIN)); then
    PASSWORD=
    PASSWORD_FILE=
    load_password
    ld=$(fetch_login_salt) || return 1
    login_value=$(sha256_upper "$(sha256_upper "$PASSWORD")${ld}")
    generated=1
  elif [[ -n $HASH || -n $HASH_FILE ]]; then
    load_hash
    login_value=$HASH
  elif [[ -z $PASSWORD && -z $PASSWORD_FILE && -f $SAVED_LOGIN ]]; then
    [[ -r $SAVED_LOGIN ]] || die 'saved login is unreadable; use --relogin'
    saved=$(jq -er --arg router "$BASE_URL" 'select(.router == $router) | .hash | select(type == "string" and length > 0)' "$SAVED_LOGIN" 2>/dev/null) || saved=
    if [[ -n $saved ]]; then
      login_value=$saved
    else
      load_password
      ld=$(fetch_login_salt) || return 1
      login_value=$(sha256_upper "$(sha256_upper "$PASSWORD")${ld}")
      generated=1
    fi
  else
    load_password
    ld=$(fetch_login_salt) || return 1
    login_value=$(sha256_upper "$(sha256_upper "$PASSWORD")${ld}")
    generated=1
  fi
  if response=$(
    {
      # Keep the credential in curl's config stream rather than its argv.
      printf 'data-urlencode = "isTest=false"\n'
      printf 'data-urlencode = "goformId=LOGIN"\n'
      printf 'data-urlencode = "password=%s"\n' "$login_value"
    } | "${curl_args[@]}" -c "$JAR" -H "Referer: $BASE_URL/" --config - "$LOGIN_URL"
  ); then
    rc=0
  else
    rc=$?
    die "login request failed (curl exit $rc)"
  fi
  if ! json_is_valid "$response" || ! jq -e 'type == "object" and ((.result? == "success") or (.result? == 0) or (.result? == "0") or (.result? == true) or (has("result") | not))' >/dev/null 2>&1 <<<"$response"; then
    die 'router rejected the login or returned an unexpected response; use --relogin to enter your web UI password again'
  fi
  if ((generated)) && [[ -t 0 ]]; then
    printf 'Save login for next time on this computer? [y/N] ' >&2
    IFS= read -r answer || answer=
    if [[ $answer == y || $answer == Y || $answer == yes ]]; then
      local tmp
      tmp=$(mktemp "$SCRIPT_DIR/.zte-hash.XXXXXX") || die 'could not create saved login file'
      if ! jq -n --arg router "$BASE_URL" --arg hash "$login_value" '{router:$router,hash:$hash}' > "$tmp"; then
        rm -f -- "$tmp"
        die 'could not write saved login'
      fi
      chmod 600 "$tmp" && mv -fT -- "$tmp" "$SAVED_LOGIN" || die 'could not save login'
      printf 'Saved login to %s (private, mode 600).\n' "$SAVED_LOGIN" >&2
    fi
  fi
}

validate_cmd() {
  local cmd=$1
  [[ -n $cmd && $cmd =~ ^[A-Za-z0-9_.,-]+$ ]] ||
    usage_error 'query names may contain only letters, digits, underscore, dot, comma and hyphen'
}

api_get() {
  local cmd=$1
  validate_cmd "$cmd"
  "${curl_args[@]}" -b "$JAR" -H "Referer: $BASE_URL/" --get \
    --data-urlencode 'isTest=false' \
    --data-urlencode 'multi_data=1' \
    --data-urlencode "cmd=$cmd" "$GET_URL"
}

get_json() {
  local cmd=$1 response
  response=$(api_get "$cmd") || die "GET request failed for: $cmd"
  json_is_valid "$response" || die "router returned invalid JSON for: $cmd"
  printf '%s\n' "$response"
}

escape_config_value() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/}
  printf '%s' "$value"
}

post_form_raw() {
  local goform=$1
  shift
  local config response rc pair key value
  config=$(mktemp "${TMPDIR:-/tmp}/zte-post.XXXXXX") || die 'could not create a private request config'
  chmod 600 "$config" || die 'could not protect the request config'
  {
    printf 'url = "%s"\n' "$(escape_config_value "$SET_URL")"
    printf 'cookie = "%s"\n' "$(escape_config_value "$JAR")"
    printf 'header = "Referer: %s/"\n' "$(escape_config_value "$BASE_URL")"
    printf 'data-urlencode = "isTest=false"\n'
    printf 'data-urlencode = "goformId=%s"\n' "$(escape_config_value "$goform")"
    for pair in "$@"; do
      key=${pair%%=*}
      value=${pair#*=}
      [[ $key != "$pair" && $key =~ ^[A-Za-z0-9_.-]+$ ]] || {
        rm -f -- "$config"
        usage_error "invalid form field: $pair"
      }
      printf 'data-urlencode = "%s"\n' "$(escape_config_value "$key=$value")"
    done
  } > "$config"
  if response=$("${curl_args[@]}" --config "$config"); then
    rc=0
  else
    rc=$?
  fi
  rm -f -- "$config"
  ((rc == 0)) || die "write request failed for $goform (curl exit $rc)"
  json_is_valid "$response" || die "router returned invalid JSON for $goform"
  printf '%s\n' "$response"
}

sha256_upper() {
  printf '%s' "$1" | sha256sum | awk '{print toupper($1)}'
}

get_ad() {
  local firmware rd0 rd1 rd inner
  firmware=$(get_json 'wa_inner_version,cr_version')
  rd0=$(jq -r '.wa_inner_version // empty' <<<"$firmware")
  rd1=$(jq -r '.cr_version // empty' <<<"$firmware")
  [[ -n $rd0 && -n $rd1 ]] || die 'router did not return the firmware values required for an authenticated write'
  rd=$(get_json 'RD' | jq -r '.RD // empty')
  [[ -n $rd ]] || die 'router did not return a write challenge'
  inner=$(sha256_upper "${rd0}${rd1}")
  sha256_upper "${inner}${rd}"
}

post_form() {
  local goform=$1 ad
  shift
  ad=$(get_ad)
  post_form_raw "$goform" "AD=$ad" "$@"
}

write_is_success() {
  jq -e 'type == "object" and ((.result? == "success") or (.result? == 0) or (.result? == "0") or (.result? == true))' >/dev/null 2>&1 <<<"$1"
}

redact_json() {
  jq 'del(.imei, .imsi, .iccid, .msisdn, .sim_msisdn, .mac_address, .wan_ipaddr, .wan_ipv6addr, .ipv6_wan_ipaddr) |
      if .station_list then .station_list |= map(del(.ip_addr, .mac_addr)) else . end |
      if .lan_station_list then .lan_station_list |= map(del(.ip_addr, .mac_addr)) else . end'
}

print_json() {
  local value=$1
  if ((REDACT)); then
    value=$(redact_json <<<"$value") || die 'could not redact JSON response'
  fi
  jq . <<<"$value"
}

print_json_line() {
  local value=$1
  if ((REDACT)); then value=$(redact_json <<<"$value") || die 'could not redact JSON response'; fi
  jq -c . <<<"$value"
}

write_guard() {
  local label=$1
  if ((DRY_RUN)); then
    if ((JSON_OUTPUT)); then
      jq -n --arg operation "$label" --argjson dry_run true \
        '{dry_run:$dry_run,operation:$operation,note:"no request was sent"}'
    else
      printf '%sDry run:%s %s (no request sent)\n' "$YELLOW" "$RESET" "$label"
    fi
    return 1
  fi
  if ((ASSUME_YES)); then return 0; fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "refusing write without confirmation; add --yes (or use --dry-run)"
  fi
  local answer
  printf '%s%s%s This can disconnect clients or change router state. Continue? [y/N] ' "$YELLOW" "$label" "$RESET" >&2
  IFS= read -r answer || true
  [[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]] || die 'operation cancelled'
}

emit_write_result() {
  local label=$1 response=$2 verification=${3:-}
  if ! write_is_success "$response"; then
    if ((JSON_OUTPUT)); then
      jq -n --arg operation "$label" --argjson response "${response:-null}" \
        '{operation:$operation,success:false,response:$response}'
    else
      printf '%s✗%s %s failed\n' "$YELLOW" "$RESET" "$label"
      print_json "$response"
    fi
    return 1
  fi
  if [[ -n $verification ]]; then
    if ((JSON_OUTPUT)); then
      jq -n --arg operation "$label" --argjson response "$response" --argjson verification "$verification" \
        '{operation:$operation,success:true,response:$response,verification:$verification}'
    else
      printf '%s✓%s %s succeeded\n' "$GREEN" "$RESET" "$label"
      printf '%sVerification:%s\n' "$DIM" "$RESET"
      print_json "$verification"
    fi
  elif ((JSON_OUTPUT)); then
    jq -n --arg operation "$label" --argjson response "$response" \
      '{operation:$operation,success:true,response:$response}'
  else
    printf '%s✓%s %s succeeded\n' "$GREEN" "$RESET" "$label"
    print_json "$response"
  fi
}

run_write() {
  local label=$1 goform=$2 verify_cmd=$3
  shift 3
  if ! write_guard "$label"; then
    ((DRY_RUN)) && return 0
    return 1
  fi
  {
    login
    local response verification=''
    response=$(post_form "$goform" "$@")
    if [[ -n $verify_cmd ]]; then
      sleep 1
      verification=$(api_get "$verify_cmd" 2>/dev/null || true)
      json_is_valid "$verification" || verification=''
    fi
    emit_write_result "$label" "$response" "$verification"
  }
}

read_once() {
  local cmd=$1
  login
  get_json "$cmd"
}

bytes_to_gb() {
  local bytes=${1:-}
  [[ $bytes =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf '0.00 GB'; return; }
  awk -v bytes="$bytes" 'BEGIN { printf "%.2f GB", bytes / 1024 / 1024 / 1024 }'
}

bps_to_human() {
  local bps=${1:-0}
  [[ $bps =~ ^[0-9]+([.][0-9]+)?$ ]] || bps=0
  awk -v bps="$bps" 'BEGIN {
    if (bps >= 1024 * 1024) printf "%.2f MB/s", bps / 1024 / 1024;
    else if (bps >= 1024) printf "%.2f KB/s", bps / 1024;
    else printf "%.0f B/s", bps;
  }'
}

secs_to_dhms() {
  local seconds=${1:-0}
  [[ $seconds =~ ^[0-9]+$ ]] || { printf 'n/a'; return; }
  printf '%dd %02dh %02dm' $((seconds / 86400)) $((seconds % 86400 / 3600)) $((seconds % 3600 / 60))
}

json_value() {
  local json=$1 key=$2
  jq -r --arg key "$key" '.[$key] // empty' <<<"$json"
}

status_command() {
  local json
  if ! json=$(read_once "$STATUS_CMD"); then return 1; fi
  print_json "$json"
}

full_command() {
  local json
  if ! json=$(read_once "$FULL_CMD"); then return 1; fi
  print_json "$json"
}

radio_command() {
  local json
  if ! json=$(read_once "$RADIO_CMD"); then return 1; fi
  print_json "$json"
}

wifi_info_command() {
  local json
  if ! json=$(read_once "$WIFI_CMD"); then return 1; fi
  print_json "$json"
}

network_info_command() {
  local json
  if ! json=$(read_once "$NETWORK_CMD"); then return 1; fi
  print_json "$json"
}

system_command() {
  local json
  if ! json=$(read_once "$SYSTEM_CMD"); then return 1; fi
  print_json "$json"
}

login_command() {
  login
  if ((JSON_OUTPUT)); then
    jq -n --arg router "$BASE_URL" '{login:true,router:$router,message:"login succeeded"}'
  else
    printf '%s✓%s Login succeeded for %s\n' "$GREEN" "$RESET" "$BASE_URL"
  fi
}

sms_command() {
  local json
  if ! json=$(read_once "$SMS_CMD"); then return 1; fi
  print_json "$json"
}

devices_command() {
  local wifi wired result
  login
  wifi=$(get_json 'station_list')
  wired=$(get_json 'lan_station_list')
  result=$(jq -n --argjson wifi "$wifi" --argjson wired "$wired" \
    '{wifi:($wifi.station_list // []),wired:($wired.lan_station_list // [])}')
  if ((JSON_OUTPUT)); then
    print_json "$result"
    return
  fi
  printf '%s%sConnected devices%s\n\n' "$BOLD" "$CYAN" "$RESET"
  printf '%sWi-Fi:%s\n' "$MAGENTA" "$RESET"
  jq -r '.wifi[]? | "  • " + (.hostname // "Unknown") + " (" + (.ip_addr // "?") + ", " + (.mac_addr // "?") + ")"' <<<"$result"
  printf '\n%sWired:%s\n' "$MAGENTA" "$RESET"
  jq -r '.wired[]? | "  • " + (.hostname // "Unknown") + " (" + (.ip_addr // "?") + ", " + (.mac_addr // "?") + ")"' <<<"$result"
}

report_command() {
  local data wifi wired result
  login
  data=$(get_json "$FULL_CMD")
  wifi=$(get_json 'station_list')
  wired=$(get_json 'lan_station_list')
  result=$(jq -n --argjson data "$data" --argjson wifi "$wifi" --argjson wired "$wired" \
    '$data + {station_list:($wifi.station_list // []),lan_station_list:($wired.lan_station_list // [])}')
  if ((JSON_OUTPUT)); then
    print_json "$result"
    return
  fi

  local carrier connection signal rsrp snr ppp wan model firmware mac sms
  carrier=$(json_value "$result" network_provider)
  connection=$(json_value "$result" network_type)
  signal=$(json_value "$result" signalbar)
  rsrp=$(json_value "$result" lte_rsrp)
  snr=$(json_value "$result" lte_snr)
  ppp=$(json_value "$result" ppp_status)
  wan=$(json_value "$result" wan_ipaddr)
  model=$(json_value "$result" hardware_version)
  firmware=$(json_value "$result" wa_inner_version)
  mac=$(json_value "$result" mac_address)
  sms=$(json_value "$result" sms_unread_num)

  printf '\n%s%s════════════════════════════════════════%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '%s%s          MODEM STATUS REPORT%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '%s%s════════════════════════════════════════%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '\n%s%s◆ Network%s\n' "$BOLD" "$YELLOW" "$RESET"
  printf '  %-18s %s\n' 'Carrier:' "${carrier:-n/a}"
  printf '  %-18s %s\n' 'Connection:' "${connection:-n/a}"
  printf '  %-18s %s / 5\n' 'Signal:' "${signal:-n/a}"
  printf '  %-18s %s dBm\n' 'RSRP:' "${rsrp:-n/a}"
  [[ -n $snr ]] && printf '  %-18s %s dB\n' 'SNR:' "$snr"
  printf '  %-18s %s\n' 'PPP status:' "${ppp:-n/a}"
  [[ -n $wan ]] && printf '  %-18s %s\n' 'WAN IP:' "$wan"

  printf '\n%s%s◆ Live speed%s\n' "$BOLD" "$YELLOW" "$RESET"
  printf '  %-18s %s%s%s\n' 'Download:' "$GREEN" "$(bps_to_human "$(json_value "$result" realtime_rx_thrpt)")" "$RESET"
  printf '  %-18s %s%s%s\n' 'Upload:' "$GREEN" "$(bps_to_human "$(json_value "$result" realtime_tx_thrpt)")" "$RESET"

  printf '\n%s%s◆ Device%s\n' "$BOLD" "$YELLOW" "$RESET"
  printf '  %-18s %s\n' 'Model:' "${model:-n/a}"
  printf '  %-18s %s\n' 'Firmware:' "${firmware:-n/a}"
  ((REDACT)) || printf '  %-18s %s\n' 'MAC address:' "${mac:-n/a}"

  printf '\n%s%s◆ SIM / identity%s\n' "$BOLD" "$YELLOW" "$RESET"
  if ((REDACT)); then
    printf '  identity fields redacted (use without --redact only on a trusted terminal)\n'
  else
    printf '  %-18s %s\n' 'Phone number:' "$(json_value "$result" msisdn)"
    printf '  %-18s %s\n' 'IMEI:' "$(json_value "$result" imei)"
    printf '  %-18s %s\n' 'IMSI:' "$(json_value "$result" imsi)"
    printf '  %-18s %s\n' 'ICCID:' "$(json_value "$result" iccid)"
  fi

  printf '\n%s%s◆ Data usage%s\n' "$BOLD" "$YELLOW" "$RESET"
  printf '  %-18s %s\n' 'Monthly ↓ RX:' "$(bytes_to_gb "$(json_value "$result" monthly_rx_bytes)")"
  printf '  %-18s %s\n' 'Monthly ↑ TX:' "$(bytes_to_gb "$(json_value "$result" monthly_tx_bytes)")"
  printf '  %-18s %s\n' 'Session ↓ RX:' "$(bytes_to_gb "$(json_value "$result" realtime_rx_bytes)")"
  printf '  %-18s %s\n' 'Session ↑ TX:' "$(bytes_to_gb "$(json_value "$result" realtime_tx_bytes)")"
  printf '  %-18s %s\n' 'Monthly uptime:' "$(secs_to_dhms "$(json_value "$result" monthly_time)")"
  printf '  %-18s %s\n' 'Session uptime:' "$(secs_to_dhms "$(json_value "$result" realtime_time)")"

  local wifi_count wired_count
  wifi_count=$(jq '.station_list | length' <<<"$result")
  wired_count=$(jq '.lan_station_list | length' <<<"$result")
  printf '\n%s%s◆ Connected devices%s\n' "$BOLD" "$YELLOW" "$RESET"
  printf '  %-18s %s device(s)\n' 'Wi-Fi:' "$wifi_count"
  printf '  %-18s %s device(s)\n' 'Wired:' "$wired_count"
  if ((wifi_count > 0)); then
    printf '\n  %sWi-Fi devices:%s\n' "$MAGENTA" "$RESET"
    jq -r '.station_list[] | "    • " + (.hostname // "Unknown") + " (" + (.ip_addr // "?") + ", " + (.mac_addr // "?") + ")"' <<<"$result"
  fi
  if ((wired_count > 0)); then
    printf '\n  %sWired devices:%s\n' "$MAGENTA" "$RESET"
    jq -r '.lan_station_list[] | "    • " + (.hostname // "Unknown") + " (" + (.ip_addr // "?") + ", " + (.mac_addr // "?") + ")"' <<<"$result"
  fi
  if [[ -n $sms && $sms != 0 ]]; then printf '\n%s%s◆ Messages%s\n  SMS: %s unread\n' "$BOLD" "$YELLOW" "$RESET" "$sms"; fi
  printf '\n%sGenerated: %s%s\n' "$DIM" "$(date '+%Y-%m-%d %H:%M:%S')" "$RESET"
  printf '%s%s════════════════════════════════════════%s\n\n' "$BOLD" "$CYAN" "$RESET"
}

ui_command() {
  if ((JSON_OUTPUT)); then
    local route title access
    printf '%s\n' "${UI_ROUTES[@]}" | while IFS='|' read -r route title access; do
      jq -n --arg route "$route" --arg title "$title" --arg access "$access" \
        '{route:$route,title:$title,access:$access}'
    done | jq -s .
    return
  fi
  printf '%s%sRouter UI map%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '%s%sLive menu paths discovered from the current firmware:%s\n\n' "$DIM" "$CYAN" "$RESET"
  local entry route title access
  for entry in "${UI_ROUTES[@]}"; do
    IFS='|' read -r route title access <<<"$entry"
    printf '  %-30s %-26s %s\n' "$route" "$title" "$access"
  done
}

capabilities_command() {
  local forms_json reads_json ui_json
  forms_json=$(tr ' ' '\n' <<<"$KNOWN_FORMS" | jq -Rsc 'split("\n") | map(select(length > 0))')
  reads_json=$(jq -n --arg full "$FULL_CMD" --arg status "$STATUS_CMD" --arg radio "$RADIO_CMD" --arg wifi "$WIFI_CMD" --arg system "$SYSTEM_CMD" --arg sms "$SMS_CMD" --arg network "$NETWORK_CMD" \
    '{full:$full,status:$status,radio:$radio,wifi:$wifi,system:$system,sms:$sms,network:$network}')
  ui_json=$(printf '%s\n' "${UI_ROUTES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0) | split("|") | {route:.[0],title:.[1],access:.[2]})')
  if ((JSON_OUTPUT)); then
    jq -n --arg version "$VERSION" --arg device "$IP" --argjson reads "$reads_json" --argjson forms "$forms_json" --argjson ui "$ui_json" \
      '{version:$version,target:$device,reads:$reads,known_write_forms:$forms,ui_routes:$ui}'
  else
    printf '%s%sCLI/API capability map%s\n\n' "$BOLD" "$CYAN" "$RESET"
    printf 'Target: %s\nRead groups: status, full, radio, wifi-info, network-info, system, sms, devices, report\nWrite groups: mode, wifi, connect, disconnect, reboot, shutdown, factory-reset, form\nUse "%s ui" for the complete router menu route list.\n' "$IP" "$PROGRAM"
  fi
}

speed_command() {
  local interval=${1:-$DEFAULT_SPEED_INTERVAL} json net rx tx
  validate_interval "$interval"
  login
  if ((JSON_OUTPUT == 0)); then
    printf '\n%s%sLive speed monitor — Ctrl+C to stop%s\n\n' "$BOLD" "$CYAN" "$RESET"
  fi
  while :; do
    json=$(api_get 'network_type,realtime_rx_thrpt,realtime_tx_thrpt' 2>/dev/null || true)
    if ! json_is_valid "$json" || [[ -z $(jq -r '.network_type // empty' <<<"$json" 2>/dev/null) ]]; then
      login
      json=$(api_get 'network_type,realtime_rx_thrpt,realtime_tx_thrpt' 2>/dev/null || true)
    fi
    if ! json_is_valid "$json"; then
      net='?'; rx=0; tx=0
    else
      net=$(jq -r '.network_type // "?"' <<<"$json")
      rx=$(jq -r '.realtime_rx_thrpt // 0' <<<"$json")
      tx=$(jq -r '.realtime_tx_thrpt // 0' <<<"$json")
    fi
    if ((JSON_OUTPUT)); then
      jq -cn --arg timestamp "$(date '+%Y-%m-%dT%H:%M:%S%z')" --arg network "$net" --arg rx "$(bps_to_human "$rx")" --arg tx "$(bps_to_human "$tx")" \
        '{timestamp:$timestamp,network_type:$network,download:$rx,upload:$tx}'
    else
      printf '\r[%s] %s  %s↓ %-12s%s  %s↑ %-12s%s   ' "$(date '+%H:%M:%S')" "$net" "$GREEN" "$(bps_to_human "$rx")" "$RESET" "$YELLOW" "$(bps_to_human "$tx")" "$RESET"
    fi
    sleep "$interval"
  done
}

watch_command() {
  local interval=${1:-$DEFAULT_WATCH_INTERVAL} json
  validate_interval "$interval"
  login
  if ((JSON_OUTPUT == 0)); then
    printf '\n%s%sZTE status monitor — Ctrl+C to stop%s\n\n' "$BOLD" "$CYAN" "$RESET"
  fi
  while :; do
    json=$(api_get "$STATUS_CMD" 2>/dev/null || true)
    if ! json_is_valid "$json"; then
      login
      json=$(api_get "$STATUS_CMD" 2>/dev/null || true)
    fi
    json_is_valid "$json" || json='{}'
    if ((JSON_OUTPUT)); then
      jq -c --arg timestamp "$(date '+%Y-%m-%dT%H:%M:%S%z')" '. + {timestamp:$timestamp}' <<<"$json"
    else
      if has_command clear; then clear; fi
      printf '%s%sZTE MODEM%s\nUpdated: %s\n\n' "$BOLD" "$CYAN" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
      print_json "$json"
    fi
    sleep "$interval"
  done
}

mode_command() {
  local mode=${1:-} value
  case $mode in
    auto|5g-4g-3g) value=WL_AND_5G ;;
    5g|5g-nsa) value=LTE_AND_5G ;;
    5g-sa) value=Only_5G ;;
    4g|4g-3g) value=WCDMA_AND_LTE ;;
    4g-only|lte) value=Only_LTE ;;
    3g|3g-only) value=Only_WCDMA ;;
    *) usage_error "mode must be auto, 5g, 5g-sa, 4g, 4g-only or 3g" ;;
  esac
  run_write "cellular mode -> $mode ($value)" SET_BEARER_PREFERENCE 'network_type,current_network_mode,ppp_status' "BearerPreference=$value"
}

wifi_band_command() {
  local band=${1:-} chip
  case $band in
    2.4|2.4ghz) chip=chip1; band=2.4 ;;
    5|5ghz) chip=chip2; band=5 ;;
    *) usage_error 'Wi-Fi band must be 2.4 or 5' ;;
  esac
  run_write "Wi-Fi band -> ${band}GHz (guest Wi-Fi is disabled by the router API)" switchWiFiChip 'wifi_onoff_state,wifi_chip1_ssid1_switch_onoff,wifi_chip2_ssid1_switch_onoff' "ChipEnum=$chip" 'GuestEnable=0'
}

wifi_toggle_command() {
  local state=${1:-} value
  case $state in
    on|enable|enabled) value=1 ;;
    off|disable|disabled) value=0 ;;
    *) usage_error 'Wi-Fi state must be on or off' ;;
  esac
  run_write "Wi-Fi -> $state" SET_WIFI_INFO 'wifi_onoff_state' "wifiEnabled=$value"
}

wifi_ssid_command() {
  local band=${1:-} ssid=${2:-} password=${3:-} form encoded auth
  [[ -n $ssid ]] || usage_error 'usage: wifi-ssid <2.4|5> <ssid> [password]'
  [[ $ssid != *$'\n'* ]] || usage_error 'SSID cannot contain a newline'
  if [[ -n $password ]]; then
    has_command base64 || die 'wifi-ssid needs the base64 command'
    encoded=$(printf '%s' "$password" | base64 | tr -d '\n')
    auth=WPAPSKWPA2PSK
  else
    encoded=
    auth=NONE
  fi
  case $band in
    2.4|2.4ghz)
      form=SET_WIFI_SSID1_SETTINGS
      run_write "2.4GHz SSID -> $ssid" "$form" 'wifi_chip1_ssid1_ssid' \
        "ssid=$ssid" 'broadcastSsidEnabled=1' 'MAX_Access_num=10' "security_mode=$auth" 'cipher=AES' 'NoForwarding=0' "security_shared_mode=$auth" "passphrase=$encoded"
      ;;
    5|5ghz)
      form=SET_WIFI_SSID2_SETTINGS
      run_write "5GHz SSID -> $ssid" "$form" 'wifi_chip2_ssid1_ssid' \
        "m_SSID=$ssid" 'm_HideSSID=0' 'm_MAX_Access_num=10' "m_AuthMode=$auth" 'm_EncrypType=AES' 'm_NoForwarding=0' "m_WPAPSK1=$encoded"
      ;;
    *) usage_error 'Wi-Fi band must be 2.4 or 5' ;;
  esac
}

connection_command() {
  local mode=${1:-} value
  case $mode in
    auto|auto_dial) value=auto_dial ;;
    manual|manual_dial) value=manual_dial ;;
    *) usage_error 'connection mode must be auto or manual' ;;
  esac
  run_write "connection mode -> $value" SET_CONNECTION_MODE 'ConnectionMode,ppp_status' "ConnectionMode=$value" 'roam_setting_option=on'
}

connect_command() {
  run_write 'connect network' CONNECT_NETWORK 'ppp_status,wan_ipaddr'
}

disconnect_command() {
  run_write 'disconnect network' DISCONNECT_NETWORK 'ppp_status,wan_ipaddr'
}

reset_data_command() {
  run_write 'reset traffic counters' RESET_DATA_COUNTER 'monthly_rx_bytes,monthly_tx_bytes,realtime_rx_bytes,realtime_tx_bytes'
}

sim_slot_command() {
  local slot=${1:-}
  [[ $slot =~ ^[0-9]+$ ]] || usage_error 'usage: sim-slot <slot-number>'
  run_write "SIM slot -> $slot" SET_SIM_SLOT 'sim_slot,sim_iccid,iccid' "sim_slot=$slot"
}

cell_lock_command() {
  local pci=${1:-} earfcn=${2:-} rat=${3:-}
  [[ $pci =~ ^[0-9]+$ && $earfcn =~ ^[0-9]+$ && $rat =~ ^[0-9]+$ ]] ||
    usage_error 'usage: cell-lock <pci> <earfcn> <rat-number>'
  run_write "cell lock pci=$pci earfcn=$earfcn rat=$rat" CELL_LOCK 'locked_cell_info,network_type,ppp_status' "pci=$pci" "earfcn=$earfcn" "rat=$rat"
}

nr_band_lock_command() {
  local mask=${1:-}
  [[ -n $mask && $mask =~ ^[A-Za-z0-9_,:-]+$ ]] || usage_error 'usage: nr-band-lock <router-band-mask>'
  run_write "NR band lock -> $mask" NR_BAND_LOCK 'nr5g_band_lock,network_type' "nr_band_lock=$mask"
}

nr5g_band_lock_command() {
  local mask=${1:-}
  [[ -n $mask && $mask =~ ^[A-Za-z0-9_,:-]+$ ]] || usage_error 'usage: nr5g-band-lock <router-band-mask>'
  run_write "NR5G band lock -> $mask" WAN_PERFORM_NR5G_BAND_LOCK 'nr5g_band_lock,network_type' "nr5g_band_mask=$mask"
}

unlock_cells_command() {
  run_write 'unlock all cells' UNLOCK_ALL_CELL 'locked_cell_info,network_type'
}

factory_reset_command() {
  local delete_user_data=${1:-1}
  [[ $delete_user_data == 0 || $delete_user_data == 1 ]] || usage_error 'factory-reset argument must be 0 (keep user data) or 1 (delete it)'
  if ((DRY_RUN == 0 && FACTORY_ACK == 0)); then
    die 'factory reset requires --confirm-factory-reset as well as --yes'
  fi
  run_write "factory reset (delete_user_data=$delete_user_data)" RESTORE_FACTORY_SETTINGS_EXTEND '' "delete_user_data=$delete_user_data"
}

form_command() {
  local goform=${1:-} pair known form_known=0
  shift || true
  [[ -n $goform ]] || usage_error 'usage: form <GOFORM_ID> key=value...'
  for known in $KNOWN_FORMS; do
    [[ $known == "$goform" ]] && form_known=1
  done
  if ((form_known == 0 && UNSAFE == 0)); then
    usage_error "form $goform is not in the known UI endpoint list; add --unsafe to use it"
  fi
  (($# > 0)) || [[ $goform == REBOOT_DEVICE || $goform == SHUTDOWN_DEVICE || $goform == CONNECT_NETWORK || $goform == DISCONNECT_NETWORK || $goform == RESET_DATA_COUNTER || $goform == UNLOCK_ALL_CELL ]] ||
    usage_error 'form needs at least one key=value argument'
  for pair in "$@"; do
    [[ $pair == *=* ]] || usage_error "form argument must be key=value: $pair"
    [[ ${pair%%=*} != AD ]] || usage_error 'AD is generated automatically for authenticated writes'
  done
  run_write "raw UI form -> $goform" "$goform" '' "$@"
}

query_command() {
  local cmd=${1:-} json
  [[ -n $cmd ]] || usage_error 'usage: query <comma-separated-router-command-list>'
  if ! json=$(read_once "$cmd"); then return 1; fi
  print_json "$json"
}

debug_command() {
  local info
  login
  info=$(get_json 'hardware_version,wa_inner_version,cr_version,web_version,network_type,ppp_status')
  if ((JSON_OUTPUT)); then
    jq -n --arg router "$BASE_URL" --argjson info "$info" \
      '{router:$router,login:true,session_cookie:"private-temporary",info:$info}'
  else
    printf '%s%sLogin succeeded%s\n' "$GREEN" "$BOLD" "$RESET"
    printf 'Cookie: private temporary jar (contents deliberately not printed)\n'
    printf 'Router: %s\n\n' "$BASE_URL"
    print_json "$info"
  fi
}

version_command() {
  printf '%s %s\n' "$PROGRAM" "$VERSION"
}

help_command() {
  cat <<EOF
${BOLD}${CYAN}ZTE router/modem CLI ${VERSION}${RESET}

Usage:
  $PROGRAM [global-options] <command> [arguments]

Connection and output options:
  --ip HOST                 Router address (default: ${IP})
  --scheme http|https       Transport scheme (default: ${SCHEME})
  --timeout SECONDS         Set connect and total request timeout
  --connect-timeout SEC     Set only the connect timeout
  --max-time SEC            Set only the total request timeout
  --json                    Emit machine-readable JSON where supported
  --redact                  Remove SIM, WAN, MAC and client identity fields
  --no-color                Disable terminal colors
  --hash-file FILE          Read the already-hashed router password from FILE
                            (auto-detects ~/.config/zte/hash when present)
  --password-file FILE      Read plaintext and calculate the dynamic login value
  --relogin                Ignore saved credentials and ask for the web UI password
  --dry-run                 Show a write plan without contacting the router
  --yes                     Skip the confirmation prompt for a write
  --unsafe                  Permit a form not in the known UI endpoint list
  --confirm-factory-reset   Required for a real factory reset

Read-only commands:
  status                    Basic signal, network and WAN status
  full                      Broad raw router information
  report                    Formatted report plus connected clients
  radio                     LTE/5G radio, cell and carrier-aggregation data
  wifi-info                 Wi-Fi state, SSID and LAN information
  network-info              Dial, WAN, DNS and IP information
  system                    Firmware, thermal and power/restart settings
  login                     Test login and exit without changing state
  devices                   Wi-Fi and wired clients
  sms                       SMS counters and storage totals
  query CMD                 Read an explicit comma-separated router command list
  speed [SECONDS]           Live throughput monitor; re-logins on expiry
  watch [SECONDS]           Live status monitor; re-logins on expiry
  ui                        Map the router's discovered web UI routes
  capabilities              Show CLI read groups and known write endpoints
  debug                     Login diagnostics without printing cookies
  version                   Print the CLI version

Guarded write commands (prompt unless --yes is supplied):
  mode auto|5g|5g-sa|4g|4g-only|3g
  wifi 2.4|5                Switch active Wi-Fi chip (also disables guest Wi-Fi)
  wifi-on|wifi-off          Enable or disable Wi-Fi
  wifi-ssid BAND SSID [PW]  Change a primary SSID (password is base64 encoded)
  connection auto|manual    Set automatic/manual connection mode
  connect | disconnect      Connect/disconnect the mobile data session
  reset-data                Reset monthly/session traffic counters
  sim-slot SLOT             Select a SIM slot
  cell-lock PCI EARFCN RAT  Lock a cell using the router's numeric RAT value
  nr-band-lock MASK         Set the router's NR band mask
  nr5g-band-lock MASK       Set the modem's NR5G performance band mask
  unlock-cells              Remove all cell locks
  reboot (restart)          Reboot the router
  shutdown                  Power down the router
  factory-reset [0|1]       Restore defaults; 1 deletes user data
  form ID key=value...       Send a known UI form (use --unsafe for new IDs)

Credential setup:
  export ZTE_IP=192.168.5.1
  export ZTE_HASH='<already-hashed-password>'
  install -d -m 700 ~/.config/zte
  # Save the browser request's password value as ~/.config/zte/hash (see README.md)
  $PROGRAM status --redact

The script never stores a credential in the repository and never prints the
temporary session cookie.  HTTP is the device's default; use --scheme https
only when the router is configured for HTTPS.
EOF
}

main() {
  parse_options "$@"
  validate_host
  validate_positive_number 'connect timeout' "$CONNECT_TIMEOUT"
  validate_positive_number 'maximum request time' "$MAX_TIME"
  init_colors

  case $COMMAND in
    help) help_command; return 0 ;;
    version) version_command; return 0 ;;
    ui) ((JSON_OUTPUT)) && require_dependencies; ui_command; return 0 ;;
    capabilities) require_dependencies; capabilities_command; return 0 ;;
  esac

  require_dependencies
  init_session

  case $COMMAND in
    status|'') status_command ;;
    full) full_command ;;
    report) report_command ;;
    radio) radio_command ;;
    wifi-info) wifi_info_command ;;
    network-info|network) network_info_command ;;
    system) system_command ;;
    login) login_command ;;
    devices) devices_command ;;
    sms) sms_command ;;
    query) query_command "${ARGS[0]:-}" ;;
    speed) speed_command "${ARGS[0]:-$DEFAULT_SPEED_INTERVAL}" ;;
    watch) watch_command "${ARGS[0]:-$DEFAULT_WATCH_INTERVAL}" ;;
    debug) debug_command ;;
    mode) mode_command "${ARGS[0]:-}" ;;
    wifi|wifi-band) wifi_band_command "${ARGS[0]:-}" ;;
    wifi-on) wifi_toggle_command on ;;
    wifi-off) wifi_toggle_command off ;;
    wifi-ssid) wifi_ssid_command "${ARGS[0]:-}" "${ARGS[1]:-}" "${ARGS[2]:-}" ;;
    connection) connection_command "${ARGS[0]:-}" ;;
    connect) connect_command ;;
    disconnect) disconnect_command ;;
    reset-data|clear-traffic) reset_data_command ;;
    sim-slot) sim_slot_command "${ARGS[0]:-}" ;;
    cell-lock) cell_lock_command "${ARGS[0]:-}" "${ARGS[1]:-}" "${ARGS[2]:-}" ;;
    nr-band-lock) nr_band_lock_command "${ARGS[0]:-}" ;;
    nr5g-band-lock) nr5g_band_lock_command "${ARGS[0]:-}" ;;
    unlock-cells) unlock_cells_command ;;
    reboot|restart) run_write 'router reboot' REBOOT_DEVICE '' ;;
    shutdown) run_write 'router shutdown' SHUTDOWN_DEVICE '' ;;
    factory-reset) factory_reset_command "${ARGS[0]:-1}" ;;
    form) form_command "${ARGS[@]}" ;;
    *)
      printf 'Unknown command: %s\n\n' "$COMMAND" >&2
      help_command >&2
      return 2
      ;;
  esac
}

main "$@"
