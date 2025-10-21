# Asuswrt-Merlin UDP fix for NFQWS (iptables)
#
# Problem
#   On Asuswrt, hardware acceleration can bypass Netfilter,
#   causing NFQWS to miss UDP packets in POSTROUTING.
#
# What this script does
#   Adds a PREROUTING rule that matches outgoing UDP traffic and sets MARK 0x1 with mask 0x7.
#   It prevents these packets from being processed by hw accel, so NFQWS can handle them correctly.
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
#   UDP fix is active only when NFQWS_FIX_MERLIN_UDP=1 is set in zapret-config.
#
[ "${NFQWS_FIX_MERLIN_UDP:-0}" = "1" ] || return
[ "$FWTYPE" = "iptables" ] || return
[ -n "$NFQWS_PORTS_UDP" ] || return

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local pkts="${NFQWS_UDP_PKT_OUT:-6}"
  local ports_ipt=$(replace_char - : "$NFQWS_PORTS_UDP")

  # Get LAN interfaces from config or autodetect
  local ifaces=${IFACE_LAN:-$(ip -o link show up | awk -F': ' '{print $2}' | grep -E '^(br0|wgs[0-9]+)$')}

  # Rule components
  local m="$(ipt_mark_filter) -m mark ! --mark $DESYNC_MARK/$DESYNC_MARK"
  local p="-p udp -m multiport --dports $ports_ipt $ipt_connbytes 1:$pkts"
  local mark_offload_off="-j MARK --set-mark 0x1/0x7"

  # Add/remove rules per interface
  for i in $ifaces; do
    [ "$DISABLE_IPV4" = "1" ] || {
      ipt_print_op "$1" "-i $i $p" "nfqws prerouting (fix) to bypass offload for UDP"
      ipta_add_del "$1" PREROUTING -t mangle -i "$i" $m $p $IPSET_EXCLUDE dst $mark_offload_off
    }

    [ "$DISABLE_IPV6" = "1" ] || {
      ipt_print_op "$1" "-i $i $p" "nfqws prerouting (fix) to bypass offload for UDP" 6
      ipt6a_add_del "$1" PREROUTING -t mangle -i "$i" $m $p $IPSET_EXCLUDE6 dst $mark_offload_off
    }
  done
}
