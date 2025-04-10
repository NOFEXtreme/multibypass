# This script creates iptables/nftables rules to send Discord voice-related UDP packets to nfqws
#
# - Discord IP Discovery (app-based voice connection)
#   https://discord.com/developers/docs/topics/voice-connections#ip-discovery
#   - UDP packet size = 82 bytes (8 bytes header + 74 bytes payload)
#   - Payload starts with: 00 01 00 46 (Type = 1, Length = 70)
#
# - Discord STUN messages (used in web client via WebRTC)
#   - Matches STUN "magic cookie" = 0x2112A442 (at fixed offset)
#
# Ports must be specified in `$NFQWS_PORTS_UDP_DISCORD` in zapret-config.sh.
# If the var is unset or commented out, this script will do nothing.
[ -z "$NFQWS_PORTS_UDP_DISCORD" ] && return

# size = 156 (8 udp header + 148 payload) && payload starts with 0x01000000
zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
  local f
  local PORTS_IPT=$(replace_char - : "$NFQWS_PORTS_UDP_DISCORD")

  local DISABLE_IPV6=1

  f="-p udp -m multiport --dports $PORTS_IPT -m u32 --u32"

  local dis_app_v4="0>>22&0x3C@4>>16=0x52&&0>>22&0x3C@8=0x00010046"
  local dis_app_v6="44>>16=0x52&&48=0x00010046"

  local dis_web_v4="0>>22&0x3C@12=0x2112A442"
  local dis_web_v6="56=0x2112A442"

  fw_nfqws_post "$1" "$f $dis_app_v4" "$f $dis_app_v6" 200 # IP Discovery (app-based voice)
  fw_nfqws_post "$1" "$f $dis_web_v4" "$f $dis_web_v6" 200 # STUN (web-based voice)
}

zapret_custom_firewall_nft() { # stop logic is not required
  local f

  local DISABLE_IPV6=1

  f="udp dport {$NFQWS_PORTS_UDP_DISCORD}"
  local dis_app="length 82 @th,64,32 0x00010046"
  local dis_web="@th,60,32 0x2112A442"
  nft_fw_nfqws_post "$f ($dis_app or $dis_web)" "$f ($dis_app or $dis_web)" 200
}
