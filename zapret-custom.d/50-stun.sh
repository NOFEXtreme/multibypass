# This script creates iptables/nftables rules to send STUN (WebRTC) UDP packets to nfqws
#
# - STUN messages (used for WebRTC voice, incl. Discord, Telegram, WhatsApp, etc.)
#   - Match on STUN magic cookie = 0x2112A442 (see RFC 5389)
#   - Validate: UDP length >= 28, type bits = 0, length % 4 = 0
#
# Ports must be specified in `$NFQWS_PORTS_UDP_STUN` in zapret-config.sh.
# If unset or empty, no rules will be added and this script will do nothing.
[ -z "$NFQWS_PORTS_UDP_STUN" ] && return

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local PORTS_IPT=$(replace_char - : "$NFQWS_PORTS_UDP_STUN")

  local DISABLE_IPV6=1

  local f="-p udp -m multiport --dports $PORTS_IPT -m u32 --u32"

  local stun_v4="0>>22&0x3C@4>>16=28:65535&&0>>22&0x3C@12=0x2112A442&&0>>22&0x3C@8&0xC0000003=0"
  local stun_v6="44>>16=28:65535&&52=0x2112A442&&48&0xC0000003=0"

  fw_nfqws_post "$1" "$f $stun_v4" "$f $stun_v6" 200 # STUN
}

zapret_custom_firewall_nft() { # stop logic is not required
  local DISABLE_IPV6=1

  local f="udp dport {$NFQWS_PORTS_UDP_STUN} length >= 28 @ih,32,32 0x2112A442 @ih,0,2 0 @ih,30,2 0"
  nft_fw_nfqws_post "$f" "$f" 200
}
