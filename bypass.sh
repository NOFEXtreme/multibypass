#!/bin/sh
# __help__
#
# Script to selectively manage VPN routing (WireGuard/OpenVPN) by domain
# and bypass DPI restrictions on ASUS routers (Merlin firmware):
# - AsusWrt Merlin: https://github.com/RMerl/asuswrt-merlin.ng
# - AsusWrt Merlin GNUton's Builds: https://github.com/gnuton/asuswrt-merlin.ng
#
# VERSION=1.3
# Author: NOFEXtream
#
# Dependents:
# - Zapret DPI Bypass tool: https://github.com/bol-van/zapret
# - x3mRouting ~ Selective Routing for Asuswrt-Merlin Firmware: https://github.com/Xentrk/x3mRouting
#   - Needs the modified version with WireGuard compatibility:
#     https://github.com/NOFEXtreme/x3mRouting/blob/master/x3mRouting.sh
#
####################################################################################
#
# Usage:
#   bypass.sh <option>
#
# Options:
#   General:
#     h  / help            - Show help
#     i  / install         - Install dependencies
#     u  / update [ver]    - Update multibypass (optionally specify version, e.g. 'update v2025.04.10-0415')
#     un / uninstall       - Uninstall multibypass
#     s  / status          - Show DNS, iptables, and ipset status
#     ns / nslookup        - Perform DNS lookups for x3mRouting domains files
#
#   Global Actions for WireGuard, OpenVPN, and zapret:
#     e  / enable          - Enable all
#     d  / disable         - Disable all
#     r  / restart         - Restart all
#   * For WireGuard and OpenVPN, actions are performed only if domains files exist.
#
#   Interface control:
#     WireGuard X interface routing:
#       wgXe / wgX-enable  - Enable wgX
#       wgXd / wgX-disable - Disable wgX
#       wgXr / wgX-restart - Restart wgX
#
#     OpenVPN X interface routing:
#       ovXe / ovX-enable  - Enable ovX
#       ovXd / ovX-disable - Disable ovX
#       ovXr / ovX-restart - Restart ovX
#
#   * Replace (X) with the interface number (e.g. wg1, ov2, etc.).
#
#   Zapret DPI routing:
#     ze / zapret-enable   - Enable zapret
#     zd / zapret-disable  - Disable zapret
#     zr / zapret-restart  - Restart zapret
#
# Examples:
#   bypass.sh wg1-enable      # Enable WireGuard wg1 interface
#   bypass.sh zapret-restart  # Restart zapret
#   bypass.sh disable         # Disable all
#
# Notes:
#   - Ensure the paths for zapret and x3mRouting scripts are correct.
#   - If domains files are missing, you will be prompted to create them when enabling WireGuard or OpenVPN routing.
#   - For better DPI bypass, edit the zapret-config.sh file.
#     Instructions can be found in the README: https://github.com/bol-van/zapret/blob/master/docs/readme.en.md
#
# __help__

SCR_NAME=$(basename "$0" | sed 's/.sh//')
SCR_DIR=$(dirname "$(readlink -f "$0")")
X3M="$SCR_DIR/core/x3mRouting.sh"
ZAPRET_DIR="$SCR_DIR/core/zapret"
ZAPRET="$ZAPRET_DIR/init.d/sysv/zapret"
NAT_START="/jffs/scripts/nat-start"
SERVICES_STOP="/jffs/scripts/services-stop"

# Prefer gawk locally if exist (GNU awk is faster)
GAWK_BIN="$(which gawk 2>/dev/null)"
if [ -n "$GAWK_BIN" ]; then
  awk() { "$GAWK_BIN" "$@"; }
fi

help() {
  awk '/^# __help__/{f=1; next} f && NF{print} f && !NF{exit}' "$0" | more
}

log_info() {
  printf "\033[1;34m%s\033[0m\n" "$1"
}

log_debug() {
  printf "\033[1;32m%s\033[0m\n" "$1"
}

log_warn() {
  printf "\033[1;33mWarning:\033[0m %s\n" "$1"
}

log_error() {
  printf "\033[0;31mError:\033[0m %s\n" "$1" && exit 1
}

check_file() {
  [ ! -e "$1" ] && log_error "File $1 not found."
  [ ! -x "$1" ] && easy_install
}

add_entry_to_file() {
  file="$1"
  entry="$2"

  if [ ! -f "$file" ]; then
    echo '#!/bin/sh' >"$file" && chmod 755 "$file"
  fi

  if ! grep -Fq "$entry" "$file"; then
    echo "$entry # $SCR_NAME" >>"$file"
    log_debug "$SCR_NAME entry added to $file"
  fi
}

delete_if_empty() {
  file="$1"

  if [ -f "$file" ]; then # If file exists, count non-empty lines, excluding the shebang.
    shebang_line=$(grep -c '^#!/bin/sh$' "$file")
    non_empty_lines=$(grep -cvE '^\s*$' "$file")
    non_empty_lines=$((non_empty_lines - shebang_line))
  fi

  if [ "$non_empty_lines" -eq 0 ]; then
    rm "$file" && log_debug "Empty file '$file' deleted."
  fi
}

delete_entry_from_file() {
  file="$1"
  pattern="$2"

  if [ -f "$file" ]; then
    if grep -qw "$pattern" "$file"; then
      sed -i "\|\b$pattern\b|d" "$file" && log_debug "Entry matching '$pattern' deleted from $file"
    fi
    delete_if_empty "$file"
  fi
}

create_link() {
  src="$1"
  dest="$2"

  [ ! -e "$src" ] && log_warn "File '$src' not found." && return 1
  [ "$(readlink "$dest" 2>/dev/null)" = "$src" ] && return 1
  ln -fs "$src" "$dest"
  log_debug "Linked '$src' => '$dest'"
  return 0
}

process_file() {
  source="$1"
  new="$2"
  link="$3"

  if [ -n "$source" ] && [ -f "$source" ]; then
    [ ! -f "$new" ] && cp "$source" "$new"
    rm -f "$source"
  else
    [ ! -f "$new" ] && echo "nonexistent.domain" >>"$new"
  fi

  [ -n "$link" ] && create_link "$new" "$link"
}

easy_install() {
  log_info "Installing necessary components."

  # Install required packages for zapret
  # If something does not work, you may also need:
  # curl iptables ip6tables ipset libnetfilter-queue ip-full ca-bundle ca-certificates gzip grep
  for package in coreutils-id coreutils-sort bind-dig ncat procps-ng-sysctl dos2unix gawk; do
    if ! opkg list-installed | grep -q "^$package"; then
      opkg update && opkg install "$package"
      log_debug "Installed package: $package"
    fi
  done

  /opt/bin/find "$SCR_DIR" -type d -exec chmod 755 {} + && log_debug "All directories set to 755."
  /opt/bin/find "$SCR_DIR" -type f -exec chmod 644 {} + && log_debug "All files set to 644."

  /opt/bin/find "$SCR_DIR" \
    \( -name tpws \
    -o -name nfqws \
    -o -name ip2net \
    -o -name mdig \
    -o -name blockcheck.sh \
    -o -name get_exclude.sh \
    -o -name clear_lists.sh \
    -o -name create_ipset.sh \
    -o -name get_refilter_domains.sh \
    -o -name get_refilter_ipsum.sh \
    -o -name get_antifilter_ipresolve.sh \
    -o -name get_reestr_resolvable_domains.sh \
    -o -name get_config.sh \
    -o -name get_reestr_preresolved.sh \
    -o -name get_user.sh \
    -o -name get_antifilter_allyouneed.sh \
    -o -name get_reestr_resolve.sh \
    -o -name get_reestr_hostlist.sh \
    -o -name get_ipban.sh \
    -o -name get_antifilter_ipsum.sh \
    -o -name get_antifilter_ipsmart.sh \
    -o -name get_antizapret_domains.sh \
    -o -name get_reestr_preresolved_smart.sh \
    -o -name get_antifilter_ip.sh \
    -o -name zapret \
    -o -name "$SCR_NAME.sh" \
    -o -name "$(basename "$X3M")" \
    \) -exec chmod 755 {} + && log_debug "Set 755 on relevant binaries and scripts in '$SCR_DIR'"

  log_info "Checking for compatible binaries."
  for arch in linux-arm64 linux-armv7hf linux-arm; do
    arch_dir="$ZAPRET_DIR/binaries/$arch"
    [ ! -d "$arch_dir" ] && {
      log_warn "Directory '$arch' missing. Try to run 'update' if no compatible binaries found."
      continue
    }

    if [ -f "$arch_dir/ip2net" ] && echo 0.0.0.0 | "$arch_dir"/ip2net >/dev/null 2>&1; then
      log_debug "Using architecture: $arch" && bin_found=1
      /opt/bin/find "$ZAPRET_DIR/binaries" -mindepth 1 -maxdepth 1 ! -name "$arch" -type d -exec rm -rf {} +

      for dir in ip2net mdig nfq tpws; do
        bin="$dir" && [ "$dir" = "nfq" ] && bin="nfqws"
        mkdir -p "$ZAPRET_DIR/$dir"
        create_link "$ZAPRET_DIR/binaries/$arch/$bin" "$ZAPRET_DIR/$dir/$bin" && links_created=1
      done && log_debug "Binaries for '$arch' installed successfully."
      break
    fi
  done
  [ -n "$bin_found" ] && [ -z "$links_created" ] && log_debug "Binaries already linked."
  [ -z "$bin_found" ] && log_error "No compatible binaries found for $(uname -m)"

  create_link "$SCR_DIR/zapret-custom.d" "$ZAPRET_DIR/init.d/sysv/custom.d"
  process_file "$SCR_DIR/zapret-config.default" "$SCR_DIR/zapret-config.sh" "$ZAPRET_DIR/config"
  for file in zapret-hosts-user.txt zapret-hosts-auto.txt zapret-hosts-user-exclude.txt; do
    process_file "" "$SCR_DIR/$file" "$ZAPRET_DIR/ipset/$file"
  done

  log_info "Executing: '$ZAPRET_DIR/ipset/get_exclude.sh'" && sh "$ZAPRET_DIR/ipset/get_exclude.sh"
}

easy_update() {
  version="$1"
  base_url="https://github.com/NOFEXtreme/multibypass/releases"
  archive="/jffs/scripts/multibypass.tar.gz"
  temp_dir="/tmp/multibypass_update"

  if [ -n "$version" ]; then
    url="$base_url/download/$version/multibypass.tar.gz"
    log_info "Downloading version $version from GitHub."
  else
    url="$base_url/latest/download/multibypass.tar.gz"
    log_info "Downloading latest version from GitHub."
  fi
  log_debug "Version URL: $url"

  if curl --retry 3 --connect-timeout 3 -sSfL -o "$archive" "$url"; then
    log_debug "Disabling 'zapret' and 'x3mRouting'."
    zapret disable
    x3mRouting "" disable

    log_debug "Preparing temporary extraction directory."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    if tar -xzf "$archive" -C "$temp_dir"; then
      log_debug "Applying update."
      (cd "$temp_dir/multibypass" && cp -R . "$SCR_DIR/")
      which sync >/dev/null 2>&1 && sync
      rm -rf "$archive" "$temp_dir"

      chmod +x "$SCR_DIR/$SCR_NAME.sh"
      log_debug "Executing updated script (install)"
      exec "$SCR_DIR/$SCR_NAME.sh" install
    else
      log_error "Extraction failed, update stopped."
      rm -rf "$temp_dir"
    fi
  else
    log_error "Download failed, update stopped."
  fi
}

easy_uninstall() {
  log_warn "Are you sure you want to delete Multibypass? [y/N]"
  read -r option
  case "${option:-n}" in
    [yY][eE][sS] | [yY])
      log_debug "Disabling 'zapret' and 'x3mRouting'."
      zapret disable
      x3mRouting "" disable
      log_debug "Proceeding with uninstallation..."
      log_info "Do you want to save zapret-config.sh and domain files in /jffs/scripts/multibypass? [Y/n]"
      read -r option
      while true; do
        case "${option:-y}" in
          [yY][eE][sS] | [yY])
            log_debug "Configuration files will be kept."
            /opt/bin/find "$SCR_DIR" -mindepth 1 ! \
              \( -name "zapret-config.sh" \
              -o -name "x3m-domains-*" \
              -o -name "zapret-hosts-*" \
              \) -exec rm -rf {} +
            log_debug "Multibypass deleted, configuration files kept."
            break
            ;;
          [nN][oO] | [nN]) log_debug "Deleting multibypass." && rm -rf "$SCR_DIR" && break ;;
          *) echo "Invalid input. Please enter 'yes' or 'no'." ;;
        esac
      done

      for package in coreutils-id bind-dig ncat procps-ng-sysctl; do
        while true; do
          if opkg list-installed | grep -q "^$package"; then
            echo "Do you want to uninstall $package? [y/N]"
            read -r option
            case "${option:-n}" in
              [yY][eE][sS] | [yY]) opkg remove "$package" && log_debug "$package has been uninstalled." && break ;;
              [nN][oO] | [nN]) log_debug "$package has not been uninstalled." && break ;;
              *) echo "Invalid input. Please enter 'yes' or 'no'." ;;
            esac
          fi
        done
      done
      ;;
    [nN][oO] | [nN]) log_debug "Uninstallation cancelled." && return ;;
    *) echo "Invalid input. Exiting uninstaller." ;;
  esac
}

status() {
  chains="PREROUTING INPUT FORWARD OUTPUT POSTROUTING"
  tables="mangle nat"

  printf "\n========== IPTABLES \n"

  for table in $tables; do
    printf "\n===== Table: %s\n" "$table"
    for chain in $chains; do
      if iptables -t "$table" -nL "$chain" >/dev/null 2>&1; then
        entries=$(iptables -t "$table" -nL "$chain" | grep -c -v '^Chain\|^num\|^$')
        if [ "$entries" -gt 0 ]; then
          printf "\n == Chain: %s\n" "$chain"
          iptables -nvL "$chain" -t "$table" --line | sed 's/^/    /'
        fi
      fi
    done
  done

  printf "\n========== IP RULES \n\n"
  ip rule | sed 's/^/  /'

  printf "\n========== IPSETS \n\n"
  ipset list -t | sed 's/^/  /'
  printf "\n Use this command to view specific set:\n\n ipset list <ipset-name>\n"

  printf "\n========== /jffs/configs/dnsmasq.conf.add (ipset only)\n\n"
  if [ -s /jffs/configs/dnsmasq.conf.add ]; then
    grep -E '^[[:space:]]*[^#]*ipset' /jffs/configs/dnsmasq.conf.add
  else
    printf "  (file is empty or missing)\n"
  fi

  printf "\n"
}

ns_lookup() {
  grep -E "^ipset=" /etc/dnsmasq.conf |
    sed 's~/~ ~g; s/ipset=//' |
    awk '{for (i=1; i<=NF; i++) print $i}' |
    while IFS= read -r DOMAIN; do
      printf "\n\t\tDomain=%s\n" "$DOMAIN"
      nslookup "$DOMAIN"
    done
}

x3mRouting() {
  ifaces="${1:-"wg1 wg2 wg3 wg4 wg5 ov1 ov2 ov3 ov4 ov5"}"
  action="$2"
  check_file "$X3M"

  for iface in $ifaces; do
    iface_number=$(echo "$iface" | grep -o '[0-9]*')
    [ "${iface%"$iface_number"}" = "ov" ] && iface_number=$((10 + iface_number))
    for type in domains ips; do
      ipset="x3m-$iface-$type"
      file_path="$SCR_DIR/$ipset.txt"

      if [ -n "$1" ] && [ ! -f "$file_path" ]; then
        if [ "$action" = "disable" ]; then
          log_info "Starting 'x3mRouting' script execution for disabling."
          log_debug "Disabling '$iface $type' routing."
          sh "$X3M" ipset_name="$ipset" del=force
          log_info "End 'x3mRouting' script execution for '$ipset'."
        else
          x3m_handle_file_creation "$ipset" "$file_path"
        fi
      elif [ -n "$1" ] && [ ! -s "$file_path" ] && [ "$action" = "enable" ]; then
        log_debug "File $file_path is empty. Add $type to it, if you want to use it." && return
      elif [ -s "$file_path" ]; then
        tr -d '\n' <"$file_path" | grep -q "$(printf '\r')" && dos2unix "$file_path"
        x3m_handle_ipset_routing "$ipset" "$file_path" "$iface" "$type"
      fi
    done
  done
}

x3m_handle_file_creation() {
  ipset="$1"
  file_path="$2"

  while true; do
    echo "Do you want to create the file $file_path? [Y/n]:"
    read -r option
    case "${option:-y}" in
      [yY][eE][sS] | [yY])
        touch "$file_path" && chmod 644 "$file_path"
        log_debug "File $file_path created. Add $type to it, if you want to use it." && return
        ;;
      [nN][oO] | [nN]) log_debug "File not created. Exiting." && return ;;
      *) echo "Invalid option." && return ;;
    esac
  done
}

x3m_handle_ipset_routing() {
  ipset="$1"
  file_path="$2"
  iface="$3"
  type="$4"

  log_info "Starting 'x3mRouting' script execution."
  log_debug "Disabling '$ipset $type' routing if exist."
  sh "$X3M" ipset_name="$ipset" del=force

  if [ "$action" = "enable" ]; then
    log_debug "Enabling '$iface' routing for $ipset."
    param_type="$([ "$type" = "domains" ] && echo "dnsmasq_file" || echo "ip_file")"
    sh "$X3M" 0 "$iface_number" "$ipset" "$param_type"="$file_path" proto="tcp:80,443 udp:443"
    sh "$X3M" server=3 ipset_name="$ipset" proto="tcp:80,443 udp:443"
  fi
  log_info "End 'x3mRouting' script execution."
}

zapret() {
  action="$1"

  check_file "$ZAPRET"
  log_info "Starting 'zapret' script execution."

  if [ "$action" = "disable" ]; then
    log_debug "Disabling 'zapret' daemons."
    sh "$ZAPRET" stop
    for table in zapret ipban nozapret; do
      if ipset list | grep -q "^Name: $table"; then
        ipset destroy "$table"
        log_debug "Deleting '$table' ipset table."
      fi
    done
    for file in "$NAT_START" "$SERVICES_STOP"; do
      delete_entry_from_file "$file" "$SCR_NAME"
    done
  fi

  if [ "$action" = "enable" ]; then
    log_debug "Disabling 'zapret' daemons." && sh "$ZAPRET" stop
    log_debug "Enabling 'zapret' daemons." && sh "$ZAPRET" start
    add_entry_to_file "$NAT_START" "$ZAPRET stop && $ZAPRET start"
    add_entry_to_file "$SERVICES_STOP" "$ZAPRET stop"
  fi

  log_info "End of 'zapret' script execution."
}

case "$(echo "$1" | awk '{print tolower($0)}')" in
  h | help) help ;;
  i | install) easy_install ;;
  u | update) easy_update "$2" ;;
  un | uninstall) easy_uninstall ;;
  s | status) status ;;
  ns | nslookup) ns_lookup ;;
  1 | e | enable | r | restart)
    x3mRouting "" enable
    zapret enable
    ;;
  0 | d | disable)
    x3mRouting "" disable
    zapret disable
    ;;
  wg[1-5] | wg[1-5]e | wg[1-5]-enable | wg[1-5]r | wg[1-5]-restart | \
    ov[1-5] | ov[1-5]e | ov[1-5]-enable | ov[1-5]r | ov[1-5]-restart)
    iface="$1"
    echo "$iface" | grep -qE '[^0-9]$' && iface="${iface%?}"
    iface="${iface%-*}"
    x3mRouting "$iface" enable
    ;;
  wg[1-5]d | ov[1-5]d | wg[1-5]-disable | ov[1-5]-disable)
    iface="${1%?}"
    iface="${iface%-*}"
    x3mRouting "$iface" disable
    ;;
  z1 | ze | z-enable | zapret-enable | zr | z-restart | zapret-restart) zapret enable ;;
  z0 | zd | z-disable | zapret-disable) zapret disable ;;
  *)
    log_debug "
    Invalid option selected. Use one of the following:

    ------------------------------------
    General:
      'h'  or 'help'                 - Show full help
      'i'  or 'install'              - Install all dependencies
      'u'  or 'update [version]'     - Update multibypass (optionally specify version, e.g. 'update v2025.04.10-0415')
      'un' or 'uninstall'            - Uninstall multibypass
      's'  or 'status'               - Show current status
      'ns' or 'nslookup'             - Perform DNS lookups for x3m files

    ------------------------------------
    Global actions:
      'e' or 'enable'                - Enable all (wgX, ovX and zapret)
      'd' or 'disable'               - Disable all (wgX, ovX and zapret)

     * For WireGuard and OpenVPN, actions are performed only if domains files exist.

    ------------------------------------
    x3mRouting control:
      WireGuard Interfaces:
        'wg(X)e' or 'wg(X)-enable'   - Enable
        'wg(X)d' or 'wg(X)-disable'  - Disable
        'wg(X)r' or 'wg(X)-restart'  - Restart

      OpenVPN Interfaces:
        'ov(X)e' or 'ov(X)-enable'   - Enable
        'ov(X)d' or 'ov(X)-disable'  - Disable
        'ov(X)r' or 'ov(X)-restart'  - Restart

      * Replace (X) with the interface number (e.g. wg1, ov2, etc.).

    ------------------------------------
    Zapret control:
      'ze' or 'zapret-enable'        - Enable zapret
      'zd' or 'zapret-disable'       - Disable zapret
      'zr' or 'zapret-restart'       - Restart zapret
    "
    exit 1
    ;;
esac
