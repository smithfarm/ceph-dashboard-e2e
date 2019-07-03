#!/bin/bash
#
# dashboard_e2e_tests.sh
#
# Run the Ceph Dashboard E2E tests against a real Ceph cluster
#
# CAVEAT: do *not* run this script as root, but *do* run it as a user with
# passwordless sudo privilege.
#
# TODO: in its current form, this script assumes the Ceph cluster is
# "pristine". More work is needed to achieve idempotence.

if [ "$EUID" = "0" ] ; then
    echo "$0: detected attempt to run script as root - bailing out!"
    exit 1
fi

set -ex

# get URL of the running Dashboard
URL=$(sudo ceph mgr services 2>/dev/null | jq -r .dashboard)

# setup RGW for E2E
sudo radosgw-admin user create --uid=dev --display-name=Developer --system
sudo ceph dashboard set-rgw-api-user-id dev
sudo ceph dashboard set-rgw-api-access-key \
    $(sudo radosgw-admin user info --uid=dev | jq .keys[0].access_key | sed -e 's/^"//' -e 's/"$//')
sudo ceph dashboard set-rgw-api-secret-key \
    $(sudo radosgw-admin user info --uid=dev | jq .keys[0].secret_key | sed -e 's/^"//' -e 's/"$//')
sudo ceph dashboard set-rgw-api-ssl-verify False

# install Google Chrome (needed for E2E)
if ! rpm -q google-chrome-stable >/dev/null ; then
    sudo zypper --non-interactive addrepo --refresh --no-gpgcheck \
        http://dl.google.com/linux/chrome/rpm/stable/x86_64 Google-Chrome
    sudo zypper --non-interactive --no-gpg-checks install --force --no-recommends \
        google-chrome-stable
fi

# point Protractor at the running Dashboard
sed -i
sed -i -e "s#http://localhost:4200/#$URL#" protractor.conf.js

# install nodeenv to get "npm" command
if ! type npm >/dev/null 2>&1 ; then
    virtualenv venv
    source venv/bin/activate
    pip install nodeenv
    nodeenv -p --node=10.13.0
fi

# install all Dashboard dependencies
# FIXME: reduce to just the Protractor dependencies (?)
timeout -v 3h npm ci

# run E2E
# FIXME: run Protractor directly instead of via npm (?)
timeout -v 3h npm run e2e
