# ASUS-Merlin QUIC/NFQWS fix
#
# Problem:
#   Hardware acceleration (Flow Cache) can bypass Netfilter,
#   so NFQWS may miss initial QUIC (UDP/443) packets in POSTROUTING.
#
# Script solution (recommended):
#   Mirror NFQUEUE for UDP/443 in PREROUTING (mangle) so NFQWS sees the first packets
#   before offload kicks in. Also remove the POSTROUTING mirror to avoid duplicates.
#
# Alternatives (use INSTEAD of this script):
#   1) NFQWS without internal conntrack:
#        Add in zapret-config → NFQWS_OPT="--ctrack-disable=1 ..."
#
#   2) Disable hardware acceleration for full Netfilter visibility: (console)
#        `fc status`
#        `fc config --hw-accel 0`   # Flow Cache: Disabled → NFQWS fully sees UDP/443, but WAN speed drops
#        `fc config --hw-accel 1`   # Flow Cache: Enabled (default, high speed)
#      Note: `fc disable` often has no real effect (Archer/Runner may remain enabled).
#
# Place this file under /jffs/scripts/multibypass/zapret-custom.d
#
[ "${NFQWS_FIX_MERLIN_QUIC:-0}" = "1" ] || return 0

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  [ "$FWTYPE" = "iptables" ] || return 0
  [ "$DISABLE_IPV4" = "1" ] && return 0

  local DISABLE_IPV6=1
  local qnum="${QNUM:-200}"
  local pkts="${NFQWS_UDP_PKT_OUT:-6}"
  local ports_ipt=$(replace_char - : "${NFQWS_PORTS_UDP:-443}")

  # get LAN interfaces from config or autodetect
  local ifaces=${IFACE_LAN:-$(ip -o link show up | awk -F': ' '{print $2}' | grep -E '^(br0|wgs[0-9]+)$')}

  # match first N UDP packets on given ports
  local f="-p udp -m multiport --dports $ports_ipt $ipt_connbytes 1:$pkts"

  # PREROUTING per-interface: catch initial packets before offload/NAT
  local rule="$(ipt_mark_filter) -m mark ! --mark $DESYNC_MARK/$DESYNC_MARK $f $IPSET_EXCLUDE dst -j NFQUEUE --queue-num $qnum --queue-bypass"

  # add/remove rules for each interface
  for i in $ifaces; do
    ipt_print_op "$1" "$f -i $i" "nfqws prerouting (qnum $qnum)"
    ipta_add_del "$1" PREROUTING -t mangle -i $i $rule
  done

  # remove stock POSTROUTING mirror to avoid duplicates
  [ "$1" = "1" ] && fw_nfqws_post 0 "$f" "" "$qnum"
}
