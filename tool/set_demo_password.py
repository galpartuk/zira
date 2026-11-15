"""Sets the password of the Zira demo account (for Google Play review).

Run:  python tool/set_demo_password.py
Uses the Firebase CLI's saved login (run `firebase login` first if needed).
The password is read without echo and sent only to Google's Identity Toolkit.
"""
import getpass
import json
import os
import subprocess
import sys
import urllib.request

PROJECT = 'tcg-arena-app'
DEMO_UID = 'LfxvzH5vsZUyohCWR7w9E5Wz3TL2'  # zira.demo@example.com

# Any CLI call refreshes the saved access token.
subprocess.run('firebase projects:list', shell=True, capture_output=True)
store = os.path.join(os.path.expanduser('~'), '.config', 'configstore', 'firebase-tools.json')
token = json.load(open(store))['tokens']['access_token']

pw = sys.argv[1] if len(sys.argv) > 1 else getpass.getpass('Demo password (min 6 chars): ')
if len(pw) < 6:
    raise SystemExit('Firebase needs at least 6 characters.')

req = urllib.request.Request(
    f'https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:update',
    data=json.dumps({'localId': DEMO_UID, 'password': pw}).encode(),
    headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json',
             'X-Goog-User-Project': PROJECT},
    method='POST',
)
with urllib.request.urlopen(req) as r:
    print('Password set for', json.load(r).get('email'))
