# Asuswrt-Merlin QUIC UDP fix for NFQWS (iptables)
#
# Problem
#   On Asuswrt, hardware acceleration can bypass Netfilter,
#   causing NFQWS to miss QUIC Initial packets in POSTROUTING.
#
# What this script does
#   Adds a PREROUTING rule that matches only QUIC Initial and sets MARK 0x1 with mask 0x7.
#   It prevents QUIC Initial packets from being processed by hw accel, so NFQWS can handle them correctly.
#
# Why bits 0x1 and 0x7
#   Asuswrt uses these bits to disable CTF for marked flows. Details explained by RMerlin:
#   https://www.snbforums.com/threads/selective-routing-with-asuswrt-merlin.9311/page-23
#
# Related zapret documentation
#   RU: https://github.com/bol-van/zapret/blob/master/docs/readme.md#flow-offloading
#   EN: https://github.com/bol-van/zapret/blob/master/docs/readme.en.md#flow-offloading
#
# Note
#   Hardware acceleration on Asuswrt may also be called
#   CTF (Cut Through Forwarding) or FA (Flow Accelerator),
#   and is known as flow offload on other routers.
#
# Activation
#   This fix is active by default. Disabled automatically if UDP fix is enabled.
#   Runs only if NFQWS_PORTS_UDP includes port 443 or NFQWS_PORTS_UDP_QUIC is set.
#   If NFQWS_PORTS_UDP_QUIC is used, its ports must also exist in NFQWS_PORTS_UDP.
#
[ "${NFQWS_FIX_MERLIN_UDP:-0}" = "0" ] || return
[ "$FWTYPE" = "iptables" ] || return

# Check if NFQWS_PORTS_UDP includes port 443 (exact or inside a range)
# Returns 0 if 443 is found, otherwise 1
ports_list_has_443() {
  local ports="${NFQWS_PORTS_UDP:-}"
  [ -n "$ports" ] || return 1

  local IFS=,
  for p in $ports; do
    case "$p" in
      443) return 0 ;;
      *-*)
        local start="${p%-*}"
        local end="${p#*-}"
        [ "$start" -le 443 ] && [ 443 -le "$end" ] && return 0
        ;;
    esac
  done
  return 1
}
[ -n "$NFQWS_PORTS_UDP_QUIC" ] || ports_list_has_443 || return

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local ports_ipt=$(replace_char - : "${NFQWS_PORTS_UDP_QUIC:-443}")

  # Get LAN interfaces from config or autodetect
  local ifaces=${IFACE_LAN:-$(ip -o link show up | awk -F': ' '{print $2}' | grep -E '^(br0|wgs[0-9]+)$')}

  # Rule components
  local m="$(ipt_mark_filter) -m mark ! --mark $DESYNC_MARK/$DESYNC_MARK"
  local p="-p udp -m multiport --dports $ports_ipt -m u32 --u32"
  local quic_v4="0>>22&0x3C@4>>16=264:65535&&0>>22&0x3C@8>>28=0xC&&0>>22&0x3C@9=0x00000001"
  local quic_v6="44>>16=264:65535&&48>>28=0xC&&49=0x00000001"
  local mark_offload_off="-j MARK --set-mark 0x1/0x7"

  # Add/remove rules per interface
  for i in $ifaces; do
    [ "$DISABLE_IPV4" = "1" ] || {
      ipt_print_op "$1" "$p $quic_v4" "nfqws prerouting (fix) disable offload for QUIC on $i"
      ipta_add_del "$1" PREROUTING -t mangle -i "$i" $m $p $quic_v4 $IPSET_EXCLUDE dst $mark_offload_off
    }

    [ "$DISABLE_IPV6" = "1" ] || {
      ipt_print_op "$1" "$p $quic_v6" "nfqws prerouting (fix) disable offload for QUIC on $i" 6
      ipt6a_add_del "$1" PREROUTING -t mangle -i "$i" $m $p $quic_v6 $IPSET_EXCLUDE6 dst $mark_offload_off
    }
  done
}
