#!/bin/bash
source .env
VERSION=`swift run alternator --version`
swift build --configuration release --arch arm64 --arch x86_64
codesign --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp .build/apple/Products/Release/alternator
mkdir .build/pkgroot
cp .build/apple/Products/Release/alternator .build/pkgroot/
pkgbuild --root .build/pkgroot --identifier sh.alternator.cli --version $VERSION --install-location /usr/local/bin/ alternator.pkg
productbuild --package alternator.pkg --identifier sh.alternator.cli --version $VERSION --sign "$DEVELOPER_ID_INSTALLER" alternator-$VERSION.pkg
rm alternator.pkg