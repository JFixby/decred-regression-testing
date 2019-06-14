#!/usr/bin/env bash

# usage:
# ./run_tests.sh                         # local, go 1.12
# GOVERSION=1.11 ./run_tests.sh          # local, go 1.11
# ./run_tests.sh docker                  # docker, go 1.12
# GOVERSION=1.11 ./run_tests.sh docker   # docker, go 1.11
# ./run_tests.sh podman                  # podman, go 1.12
# GOVERSION=1.11 ./run_tests.sh podman   # podman, go 1.11

set -ex

# The script does automatic checking on a Go package and its sub-packages,
# including:
# 1. gofmt         (https://golang.org/cmd/gofmt/)
# 2. gosimple      (https://github.com/dominikh/go-simple)
# 3. unconvert     (https://github.com/mdempsky/unconvert)
# 4. ineffassign   (https://github.com/gordonklaus/ineffassign)
# 5. go vet        (https://golang.org/cmd/vet)
# 6. misspell      (https://github.com/client9/misspell)
# 7. race detector (https://blog.golang.org/race-detector)

# golangci-lint (github.com/golangci/golangci-lint) is used to run each each
# static checker.

# To run on docker on windows, symlink /mnt/c to /c and then execute the script
# from the repo path under /c.  See:
# https://github.com/Microsoft/BashOnWindows/issues/1854
# for more details.

# Default GOVERSION
[[ ! "$GOVERSION" ]] && GOVERSION=1.12
REPO=dcrregtest

testrepo () {
  GO=go

  $GO version

  # binary needed for RPC tests
  env CC=gcc $GO build
  # cp "$REPO" "$GOPATH/bin/"
  $GO find ./...
  dir ../
  dir ../../
  dir ../../../

  # run tests on all modules
  ROOTPATH=$($GO list -m -f {{.Dir}} 2>/dev/null)
  ROOTPATHPATTERN=$(echo $ROOTPATH | sed 's/\\/\\\\/g' | sed 's/\//\\\//g')
  MODPATHS=$($GO list -m -f {{.Dir}} all 2>/dev/null | grep "^$ROOTPATHPATTERN"\
    | sed -e "s/^$ROOTPATHPATTERN//" -e 's/^\\//' -e 's/^\///')
  MODPATHS=". $MODPATHS"
  for module in $MODPATHS; do
    echo "==> ${module}"
    env GORACE='halt_on_error=1' CC=gcc $GO test -short -race \
      -tags rpctest ./${module}/...

    # check linters
    golangci-lint run --build-tags rpctest --disable-all --deadline=10m \
      --enable=gofmt \
      --enable=gosimple \
      --enable=unconvert \
      --enable=ineffassign \
      --enable=govet \
      --enable=misspell ./${module}/...
  done

  echo "------------------------------------------"
  echo "Tests completed successfully!"
}

DOCKER=
[[ "$1" == "docker" || "$1" == "podman" ]] && DOCKER=$1
if [ ! "$DOCKER" ]; then
    testrepo
    exit
fi

# use Travis cache with docker
DOCKER_IMAGE_TAG=jfixby-golang-builder-$GOVERSION
$DOCKER pull jfixby/$DOCKER_IMAGE_TAG

$DOCKER run --rm -it -v $(pwd):/src:Z jfixby/$DOCKER_IMAGE_TAG /bin/bash -c "\
  rsync -ra --filter=':- .gitignore'  \
  /src/ /go/src/github.com/jfixby/$REPO/ && \
  pushd /go/src/github.com/jfixby/ && \
  dir /go/src/github.com/ && \
  dir /go/src/ && \
  dir /go/ && \
  dir ~ && \
  dir $GO && \
  env GOVERSION=$GOVERSION GO111MODULE=on bash run_tests.sh"
