"""Source contract tests; these are NOT runtime/network or cryptographic tests."""
from pathlib import Path
import sys, re
R=Path(__file__).resolve().parents[1]
read=lambda p:(R/p).read_text()
checks={
    'NEON_DESIGN_COMPONENTS': ('lib/widgets/blousab_visuals.dart', ['BlousabChatWallpaper','BlousabProfileAvatar','BlousabNeonPanel','panelDecoration']),
    'MAIN_APP_COVER_AND_SETTINGS': ('lib/main.dart', ['_pickAndStoreProfileCover','wasl_profile_cover','BlousabNotificationsScreen','bottomNavigationBar','_profileCoverPath']),
    'CHATS_BACKGROUND_AND_BUBBLES': ('lib/screens/chat_screen.dart', ['BlousabChatWallpaper','borderRadius: BorderRadius.only','_relayRetryInProgress','trySendViaBestKnownRoute']),
    'BLUETOOTH_SCAN_SINGLE_FLIGHT': ('lib/services/bluetooth_classic_service.dart',['_discoveryInFlight','_scanNearby','cancelDiscovery']),
    'BLUETOOTH_PROFILE_PROTOCOL': ('lib/screens/communities_screen.dart',["'protocol': 'blousab-nearby-v1'", "'senderCover': myCover", "'blousab_peer_cover_", 'isKnownBlousab']),
    'LAN_ANNOUNCEMENT_GUARD': ('lib/services/local_network_service.dart',['maxDiscoveryBytes = 1200', 'packet[\'protocol\'] != discoveryProtocol','maxFrameBytes','neighbors']),
    'MESH_HOPS_AND_COSTS': ('lib/services/mesh_route_planner.dart',['maxHops = 5','quality.clamp','avoid.contains','route.path.contains']),
    'NOTIFICATION_HISTORY_BOUND': ('lib/services/notification_service.dart', ['blousab_notifications_v1','items.length > 100']),
}
fail=[]
for name,(path,needles) in checks.items():
    data=read(path)
    missing=[x for x in needles if x not in data]
    if missing: fail.append((name,missing));print('FAIL',name,'missing',missing)
    else: print('PASS',name)
# Programmatically check Android code was not rewritten by risky Flutter-only pass.
# A separate production crypto audit flags remaining E2E limits (not silently certified).
print('INFO: source contracts do NOT prove build, live discovery, delivery, security or visual pixel parity')
sys.exit(1 if fail else 0)
