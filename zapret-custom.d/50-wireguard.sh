# This script creates iptables/nftables rules to send WireGuard handshake UDP packets to nfqws
#
# - WireGuard handshake
#   - UDP packet size = 156 bytes (8 bytes header + 148 bytes payload)
#   - Payload starts with: 0x01000000 (message type marker)
#
# Ports must be specified in `$NFQWS_PORTS_UDP_WG` in zapret-config.sh.
# If unset or empty, no rules will be added and this script will do nothing.
[ -z "$NFQWS_PORTS_UDP_WG" ] && return

# Optionally limit by destination set `$SET_NAME` filled from `$SUBNETS`.
#USE_SET=true

if [ -n "$USE_SET" ]; then
  SUBNETS="" # Add your WireGuard server IPs or subnets here, separated by spaces.
  SET_NAME=wireguard
fi

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local PORTS_IPT=$(replace_char - : "$NFQWS_PORTS_UDP_WG")

  local DISABLE_IPV6=1

  if [ -n "$USE_SET" ]; then
    local dest_set="-m set --match-set $SET_NAME dst"
    local subnet

    [ "$1" = 1 ] && {
      ipset create $SET_NAME hash:net hashsize 2048 maxelem 4096 2>/dev/null
      ipset flush $SET_NAME
      for subnet in $SUBNETS; do
        echo add $SET_NAME "$subnet"
      done | ipset -! restore
    }
  fi

  local f="-p udp -m multiport --dports $PORTS_IPT -m u32 --u32"

  if [ -n "$USE_SET" ]; then
    fw_nfqws_post "$1" "$f 0>>22&0x3C@4>>16=0x9c&&0>>22&0x3C@8=0x01000000 $dest_set" "$f 44>>16=0x9c&&48=0x01000000 $dest_set" 200
  else
    fw_nfqws_post "$1" "$f 0>>22&0x3C@4>>16=0x9c&&0>>22&0x3C@8=0x01000000" "$f 44>>16=0x9c&&48=0x01000000" 200
  fi

  [ "$1" = 1 ] || ipset destroy $SET_NAME 2>/dev/null
}

zapret_custom_firewall_nft() { # stop logic is not required
  local DISABLE_IPV6=1

  if [ -n "$USE_SET" ]; then
    local dest_set="ip daddr @$SET_NAME"
    local subnets

    make_comma_list subnets "$SUBNETS"
    nft_create_set $SET_NAME "type ipv4_addr; size 4096; auto-merge; flags interval;"
    nft_flush_set $SET_NAME
    nft_add_set_element $SET_NAME "$subnets"
  fi

  local f="udp dport {$NFQWS_PORTS_UDP_WG} length == 156 @ih,0,32 0x01000000"
  if [ -n "$USE_SET" ]; then
    nft_fw_nfqws_post "$f $dest_set" "$f $dest_set" 200
  else
    nft_fw_nfqws_post "$f" "$f" 200
  fi
}

zapret_custom_firewall_nft_flush() {
  # this function is called after all nft fw rules are deleted
  # however sets are not deleted. it's desired to clear sets here.
  [ -n "$USE_SET" ] && nft_del_set $SET_NAME 2>/dev/null
}
