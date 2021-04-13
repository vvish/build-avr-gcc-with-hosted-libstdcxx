#!/bin/bash

set -euo pipefail

function _print_usage {
  echo "build-avr-gcc.bash [OPTIONS]

  Script fetches sources and builds gcc and environment
  for the avr target.

  The steps are performed:
  1. Download and build binutils
  2. Download and build gcc for avr
  3. Download avr libc and build it with gcc for avr
  3. Rebuild gcc for avr with enabled hosted libstdc++

  OPTIONS are:
    -g, --gcc             gcc version to build
    -o, --output-dir      directory to place build artifacts (default: ./out)
    -p, --preserve        do not remove intermediate artifacts
    -l, --libstdcxx       no|freestanding|hosted|hosted+streams
                            no - do not build libstdc++
                            freestanding - build freestanding version
                            hosted - build hosted
                            hosted+streams - build hosted +
                              apply patch for streams via stdio
                              if not included

    -h, --help            display this help"
}

function _check_args {
  if [[ $# -eq 0 ]]; then
    _print_usage
    exit 0
  fi
}

function _build {
  local TARGET="$1"
  local CONFIGURE_PARAMS="$2"
  local TARGET_OBJ_DIR="${TARGET}/obj"
  local INSTALL_TARGET=install-strip

  echo "Will build ${TARGET}"

  [[ -d $TARGET_OBJ_DIR ]] || mkdir $TARGET_OBJ_DIR
  pushd $TARGET_OBJ_DIR
  ../configure ${CONFIGURE_PARAMS}
  make -j$(nproc)
  make ${INSTALL_TARGET}
  popd

  echo "Done ${TARGET} ${CONFIGURE_PARAMS}"
}

_check_args "$@"

# the stable versions that are not changing frequently
BINUTILS_VERSION=2.32
LIBC_VERSION=2.0.0
ROOT_DIR=$(pwd)
OUTPUT_DIR=${ROOT_DIR}/out
TMP_DIR=${ROOT_DIR}/tmp


GCC_VERSION=""
LIBSTDCXX="no"

while (($#)); do
  case "$1" in
    -g|--gcc)
      shift
      _check_args "$@"
      GCC_VERSION=$1
      shift
      ;;
    -l|--libstdcxx)
      shift
      _check_args "$@"
      LIBSTDCXX=$1
      shift
      ;;
    -o|--output-dir)
      shift
      _check_args "$@"
      OUTPUT_DIR=$(pwd)/$1
      shift
      ;;
    -p|--preserve)
      PRESERVE_ARTIFACTS=1
      shift
      ;;
    -c|--clean)
      CLEAN=1
      shift
      ;;
    -h|--help)
      _print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*|--*=)
      echo "unknown argument $1" >&2
      exit 1
      ;;
  esac
done

BINUTILS_TARGET=binutils-${BINUTILS_VERSION}
LIBC_TARGET=avr-libc-${LIBC_VERSION}
GCC_TARGET=gcc-trunk

BINUTILS_TARGET_DIR=${TMP_DIR}/${BINUTILS_TARGET}
LIBC_TARGET_DIR=${TMP_DIR}/${LIBC_TARGET}
GCC_TARGET_DIR=${TMP_DIR}/${GCC_TARGET}

if [[ ${GCC_VERSION:+x} == x ]]; then
  # the earliest release of GCC can be 9 only
  if [[ ${GCC_VERSION%%.*} -lt 9 && $LIBSTDCXX != "no" ]]; then
    echo "GCC ${GCC_VERSION} is to old. Patches required for libstdc++ can't be applied"
    exit 1
  fi

  # the required patches are expected to be in GCC 11
  [[ ${GCC_VERSION%%.*} -lt 11 ]] && DOES_NOT_HAVE_PATCHES=1

  GCC_TARGET=gcc-${GCC_VERSION}
  BRANCH="--branch releases/${GCC_TARGET}"
fi

function _cleanup {
  echo "Removing intermidiate artifacts"
  cd $ROOT_DIR
  rm -rf $BINUTILS_TARGET_DIR ${BINUTILS_TARGET_DIR}.tar.gz \
    $LIBC_TARGET_DIR ${LIBC_TARGET_DIR}.tar.bz2 \
    $GCC_TARGET_DIR
  rmdir $TMP_DIR || echo "Tmp directory <tmp> contains artifacts from another build and can not be removed"
}

if [[ ${PRESERVE_ARTIFACTS:+x} != x ]]; then
  trap _cleanup EXIT
fi


PHASE1_CONFIG=" --target=avr"
PHASE1_CONFIG+=" --enable-languages=c,c++ --enable-lto"
PHASE1_CONFIG+=" --disable-shared --disable-threads"
PHASE1_CONFIG+=" --disable-nls --disable-libssp --with-dwarf2"

PHASE2_CONFIG=" --disable-nls --disable-__cxa_atexit"
PHASE2_CONFIG+=" --enable-static --disable-sjlj-exceptions"
PHASE2_CONFIG+=" --enable-libstdcxx --with-avrlibc"

case $LIBSTDCXX in
  no)
    ;;
  freestanding)
    PHASE2_CONFIG+=" --disable-hosted-libstdcxx"
    if [[ ${DOES_NOT_HAVE_PATCHES:+x} == x ]]; then
      echo "GCC patch will be applied"
      SHOULD_APPLY_BUILD_PATCH=1
      SHOULD_APPLY_FREESTANDING_PATCH=1
    fi
    ;;
  hosted+streams)
    PHASE2_CONFIG+=" --enable-cstdio=stdio_pure"
    if [[ ${DOES_NOT_HAVE_PATCHES:+x} == x ]]; then
      echo "Streams patch will be applied"
      SHOULD_APPLY_STREAM_PATCH=1
    fi
    ;&
  hosted)
    if [[ ${DOES_NOT_HAVE_PATCHES:+x} == x ]]; then
      echo "GCC patch will be applied"
      SHOULD_APPLY_BUILD_PATCH=1
      SHOULD_APPLY_LIBC_PATCH=1
    fi
    ;;
  *)
    echo "Wrong value for -l, --libstdcxx parameter"
    exit 0
    ;;
esac

[[ -d ${OUTPUT_DIR} ]] && echo "Output dir already exists" && exit 1

mkdir -p $OUTPUT_DIR
mkdir -p $TMP_DIR

echo "Will configure with ${PHASE1_CONFIG} ${PHASE2_CONFIG}"

pushd $TMP_DIR

curl -L -O https://ftpmirror.gnu.org/binutils/${BINUTILS_TARGET}.tar.gz
tar xfz ${BINUTILS_TARGET}.tar.gz
_build $BINUTILS_TARGET "--prefix=${OUTPUT_DIR} ${PHASE1_CONFIG}"

git clone --depth 1 ${BRANCH:-} git://gcc.gnu.org/git/gcc.git ${GCC_TARGET}
pushd $GCC_TARGET
./contrib/download_prerequisites
popd
_build $GCC_TARGET "--prefix=${OUTPUT_DIR} ${PHASE1_CONFIG}"

export PATH=${OUTPUT_DIR}/bin:$PATH

curl -L -O http://download.savannah.gnu.org/releases/avr-libc/${LIBC_TARGET}.tar.bz2
tar xfj ${LIBC_TARGET}.tar.bz2

if [[ ${SHOULD_APPLY_LIBC_PATCH:+x} == x ]]; then
  pushd $LIBC_TARGET
  patch -p1 < ${ROOT_DIR}/patches/avr-libc/avr-libc.patch
  popd
fi

_build $LIBC_TARGET "--prefix=${OUTPUT_DIR} --build=$(${LIBC_TARGET}/config.guess) --host=avr"

if [[ $LIBSTDCXX == "no" ]]; then
  echo "no libstdc++ will be built, build completed"
  exit 0
fi

pushd $GCC_TARGET
if [[ ${SHOULD_APPLY_BUILD_PATCH:+x} == x ]]; then
  echo "GCC build patch will be applied"
  git am ${ROOT_DIR}/patches/gcc/0001-libstdc-Disabling-AC_LIBTOOL_DLOPEN-check-if-buildin.patch
fi
if [[ ${SHOULD_APPLY_FREESTANDING_PATCH:+x} == x ]]; then
  echo "patch for freestanding build will be applied"
  git am ${ROOT_DIR}/patches/gcc/0001-libstdc-Declare-malloc-for-freestanding.patch
fi
if [[ ${SHOULD_APPLY_STREAM_PATCH:+x} == x ]]; then
  echo "libstdc++ streams patch will be applied"
  git am ${ROOT_DIR}/patches/gcc/0001-libstdc-Support-libc-with-stdio-only-I-O-in-libstdc.patch
fi
popd

_build $GCC_TARGET "--prefix=${OUTPUT_DIR} ${PHASE1_CONFIG} ${PHASE2_CONFIG}"

popd

echo "build completed"
