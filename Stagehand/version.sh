# Sourced by build.sh and ios-build.sh, so the Mac and iPhone apps share their version.
# VERSION: from the environment (release.sh), else the latest v* git tag, else 0.0.0.
# BUILD_NUMBER: the commit count, which grows with every commit.
VERSION=${VERSION:-$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
