# This custom script runs desync of some udp packets on WireGuard protocol
# using ports specified in `$NFQWS_PORTS_UDP_WG` (defined in the zapret-config.sh).
# Initializes `$SET_NAME` with `$SUBNETS`.

# This script will not execute if the var is unset or commented out in the config.
[ -z "$NFQWS_PORTS_UDP_WG" ] && return

# Uncomment to enable the use of ipset/nfset.
#USE_SET=true

if [ -n "$USE_SET" ]; then
  # Add your WireGuard server IPs or subnets here, separated by spaces.
  SUBNETS=""
  SET_NAME=wireguard
fi

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local f
  local first_packets_only="$ipt_connbytes 1:3"
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

  f="-p udp -m multiport --dports $PORTS_IPT"

  if [ -n "$USE_SET" ]; then
    fw_nfqws_post "$1" "$f $first_packets_only $dest_set" "$f $first_packets_only $dest_set" 200
  else
    fw_nfqws_post "$1" "$f $first_packets_only" "$f $first_packets_only" 200
  fi

  [ "$1" = 1 ] || ipset destroy $SET_NAME 2>/dev/null
}

zapret_custom_firewall_nft() { # stop logic is not required
  local f
  local first_packets_only="$nft_connbytes 1-3"

  local DISABLE_IPV6=1

  if [ -n "$USE_SET" ]; then
    local dest_set="ip daddr @$SET_NAME"
    local subnets

    make_comma_list subnets "$SUBNETS"
    nft_create_set $SET_NAME "type ipv4_addr; size 4096; auto-merge; flags interval;"
    nft_flush_set $SET_NAME
    nft_add_set_element $SET_NAME "$subnets"
  fi

  f="udp dport {$NFQWS_PORTS_UDP_DISCORD}"
  if [ -n "$USE_SET" ]; then
    nft_fw_nfqws_post "$f $first_packets_only $dest_set" "$f $first_packets_only $dest_set" 200
  else
    nft_fw_nfqws_post "$f $first_packets_only" "$f $first_packets_only" 200
  fi
}

zapret_custom_firewall_nft_flush() {
  # this function is called after all nft fw rules are deleted
  # however sets are not deleted. it's desired to clear sets here.
  [ -n "$USE_SET" ] && nft_del_set $SET_NAME 2>/dev/
}
