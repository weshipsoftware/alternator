#!/bin/bash
source .env
VERSION=`swift run alternator --version`
xcrun notarytool submit alternator-$VERSION.pkg --keychain-profile $KEYCHAIN_PROFILE --wait
xcrun stapler staple alternator-$VERSION.pkg
mv alternator-$VERSION.pkg docs/!downloads