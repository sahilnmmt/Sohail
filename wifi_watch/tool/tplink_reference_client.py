"""Logs in to a (fake) TP-Link router with the tplinkrouterc6u library and
prints the host names it lists, one per line. Used by
test/tplink_interop_test.dart to check the test router speaks the same
protocol as the library that is known to work with real routers.

Usage: python tplink_reference_client.py <url> <variant> <user> <password>
"""
import sys

from tplinkrouterc6u.client.ex import TPLinkEXClient, TPLinkEXClientGCM
from tplinkrouterc6u.client.mr import TPLinkMRClient
from tplinkrouterc6u.client.vr import TPLinkVRClient

url, variant, user, password = sys.argv[1:5]
cls = {
    'ex-gcm': TPLinkEXClientGCM,
    'ex-cbc': TPLinkEXClient,
    'vr-cbc': TPLinkVRClient,
    'mr-cbc': TPLinkMRClient,
}[variant]
client = cls(url, password, username=user)
client.authorize()
if variant.startswith('ex'):
    _, values = client.req_act([client.ActItem(client.ActItem.GL, 'DEV2_HOST_ENTRY')])
    hosts = client._to_list(values[0])
else:
    _, values = client.req_act([client.ActItem(client.ActItem.GL, 'LAN_HOST_ENTRY')])
    hosts = client._to_list(values)
for h in hosts:
    print(h['hostName'])
client.logout()
