"""Conservative release gate: refuse to claim cryptographic E2E or secure LAN."""
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
native=(R/'android/app/src/main/kotlin/com/plosap/myapp/MainActivity.kt').read_text()
lan=(R/'lib/services/local_network_service.dart').read_text()
risks=[]
if 'ids.joinToString("|")' in native and 'wifiAwarePassphrase' in native:
    risks.append('Wi-Fi Aware PSK is derived from discoverable peer IDs, not an authenticated secret.')
if 'socket.write(' in lan and 'jsonEncode' in lan and 'end-to-end encryption' in lan:
    risks.append('LAN frames are not demonstrably end-to-end encrypted or authenticated.')
if 'listenUsingRfcommWithServiceRecord' in native and 'Cipher' not in native:
    risks.append('Bluetooth RFCOMM transports JSON without verified application-layer E2E.')
if risks:
    for r in risks:print('BLOCKER:',r)
    print('FAIL: PRODUCTION_SECURITY_GATE: do not assert 100% security or ship as E2E-secure')
    sys.exit(1)
print('PASS: no targeted known risks found (independent penetration test still required)')
