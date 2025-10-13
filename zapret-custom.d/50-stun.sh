# This script creates iptables/nftables rules to send STUN (WebRTC) UDP packets to nfqws
# NOTE: @ih requires nft 1.0.1+ and updated kernel version.
#
# - STUN messages (used by WebRTC voice apps: Discord, Telegram, WhatsApp, etc.)
#   - Match STUN magic cookie: 0x2112A442 (RFC 5389)
#   - Conditions: UDP length >= 28, type bits = 0, length % 4 = 0
#
# Enabled only if `NFQWS_CUSTOM_STUN=1` is set in zapret-config.sh.
# Otherwise, this script does nothing.
#
[ "${NFQWS_CUSTOM_STUN:-0}" = "1" ] || return 0

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local f="-p udp -m u32 --u32"

  local stun_v4="0>>22&0x3C@4>>16=28:65535&&0>>22&0x3C@12=0x2112A442&&0>>22&0x3C@8&0xC0000003=0"
  local stun_v6="44>>16=28:65535&&52=0x2112A442&&48&0xC0000003=0"

  fw_nfqws_post "$1" "$f $stun_v4" "$f $stun_v6" 200
}

zapret_custom_firewall_nft() { # stop logic is not required
  local f="udp length >= 28 @ih,32,32 0x2112A442 @ih,0,2 0 @ih,30,2 0"
  nft_fw_nfqws_post "$f" "$f" 200
}
