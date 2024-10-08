#!/bin/env bash
rm -Rf rocprofiler-sdk-*
snl_proxy_setup () {
  proxy="http://user:pass@proxy.sandia.gov:80"
  for _protocol in \
    "all_proxy" \
    "ftp_proxy" \
    "http_proxy" \
    "https_proxy" \
    "rsync_proxy" \
    "socks_proxy" \
    "ALL_PROXY" \
    "FTP_PROXY" \
    "HTTP_PROXY" \
    "HTTPS_PROXY" \
    "RSYNC_PROXY" \
    "SOCKS_PROXY"
  do
    export $_protocol="$proxy"
  done
#  noproxy="*.local,169.254/16,*.sandia.gov,*.srn.sandia.gov,localhost,127.0.0.1,::1"
  noproxy="web.sandia.gov,srn.sandia.gov,sandia.gov,*.web.sandia.gov,*.srn.sandia.gov,*.sandia.gov,localhost"
  for _noproxy in \
    "no_proxy" \
    "NO_PROXY"
  do
    export "${_noproxy}"="$noproxy"
  done
#  message -g "SANDIA PROXY SETTINGS: $(env | grep -i proxy)"
}

## capture the steps required to reproducibly build rocprofiler-sdk from source
here_spackenv() {
cat << HERE_SPACK_ENV >spack.yaml
# This is a Spack Environment file.
#
# It describes a set of packages to be installed, along with
# configuration settings.
spack:
  specs:
  - cmake
  - git
  - rocm-core@6.2.0
  - hip@6.2.0
  - aqlprofile@6.2.0
  - rocprofiler-dev
  - py-cppheaderparser
  concretizer:
    unify: when_possible
  view:
    rocprof_gnu:
      root: \$spack/../rocprof_gnu
      link: roots
  compilers:
  - compiler:
      spec: gcc@=9.2.0
      paths:
        cc: /home/projects/x86-64/gcc/9.2.0/bin/gcc
        cxx: /home/projects/x86-64/gcc/9.2.0/bin/g++
        f77: /home/projects/x86-64/gcc/9.2.0/bin/gfortran
        fc: /home/projects/x86-64/gcc/9.2.0/bin/gfortran
      flags: {}
      operating_system: rocky8
      target: x86_64
      modules: []
      environment: {}
      extra_rpaths: []

  modules:
    default:
      enable:
        - lmod
      lmod:
        core_compilers:
          - gcc@0.0.0
    rocprof_gnu:
      roots:
        lmod: \$spack/../modulefiles
      use_view: rocprof_gnu
      enable:
        - lmod
      lmod:
        core_compilers:
          - gcc@0.0.0
        hide_implicits: true
        all:
          autoload: direct
        hash_length: 0
        hip:
          environment:
            set:
              ROCM_PATH: '{prefix}'
        projections:
          rocm-core: '{name}/{version}'
          hip: '{name}/{version}'
          cmake: '{name}/{version}'
          git: '{name}/{version}'
          aqlprofile: '{name}/{version}'
          rocprofiler-dev: '{name}/{version}'
          py-cppheaderparser: '{name}/{version}'
          htop: '{name}/{version}'
          all: '{name}/{version}'

    prefix_inspections:
      lib:
      - LD_LIBRARY_PATH
      lib64:
      - LD_LIBRARY_PATH
HERE_SPACK_ENV
}

ml_test() {
  local _mf=$1
  module load ${_mf}
  module list |& grep ${_mf}
}

message () {
    local color
    local OPTIND
    local opt
    while getopts "crgymn" opt; do
        case $opt in
            c)  color=$(tput setaf 6) ;;
            r)  color=$(tput setaf 1) ;;
	    g)  color=$(tput setaf 2) ;;
	    y)  color=$(tput setaf 3) ;;
	    m)  color=$(tput setaf 5) ;;
            *)  color=$(tput sgr0)    ;;
        esac
    done
    shift $(($OPTIND -1))
    printf "${color}%-10s %-50s %-50s %-50s\n" "$1" "$2" "$3" "
$4"
    tput sgr0
}  

die () {
 message -r "ERROR" "$@" >&2
 exit 2
}

spack_env_build () {
  SPACK_COMMIT_HASH=${SPACK_COMMIT_HASH:="482e2fbde88c1f0fe9c05fd066c9cd70054c7196"}
  if ! [ -d myspack ] ; then
    git clone http://github.com/spack/spack.git -b develop myspack ||\
      die "Spack github clone failed"
  fi
  SPACK_ROOT=$(readlink -f myspack)
  pushd $SPACK_ROOT &>>/dev/null
  git checkout ${SPACK_COMMIT_HASH}
  popd &>>/dev/null
  module purge
  ml_test gcc/9.2.0
  source $SPACK_ROOT/share/spack/setup-env.sh
  spack env create rocprof_gnu
  spack env activate rocprof_gnu
  [ -d /projects/AMD_GPU_SAMPLER/spack_build_cache/build_cache ] &&\
    spack mirror add rocprof_cache /projects/AMD_GPU_SAMPLER/spack_build_cache
  spack mirror list |& grep rocprof_cache || die "rocprof_cache was not added"
  spack mirror set --autopush --unsigned --type binary rocprof_cache
  pushd $SPACK_ROOT/var/spack/environments/rocprof_gnu &>/dev/null
  here_spackenv
  popd &>/dev/null
  spack concretize -fU
  spack install -y --use-buildcache auto --no-check-signature
  spack buildcache push -u --update-index --with-build-dependencies /projects/AMD_GPU_SAMPLER/spack_build_cache
  spack module tcl refresh -y
}

snl_proxy_setup
## THESE ARE TEMPORARY
  #SPACK_ROOT=$(readlink -f myspack)
  #source $SPACK_ROOT/share/spack/setup-env.sh
  #spack env activate rocprof_gnu
  #spack module tcl refresh -y
## ^^^ THESE ARE TEMPORARY
START=${PWD}
spack_env_build
module purge
if [ -f load_modules.sh ] ; then rm load_modules.sh ; fi
for package in "rocm-core" "cmake" "git" "hip@6.2.0" "aqlprofile@6.2.0" "rocprofiler-dev" "py-cppheaderparser" ; do
  spack module tcl loads --dependencies $package >>load_modules.sh
done
sort load_modules.sh | uniq >spack_modules.sh

[ -f spack_modules.sh ] && source spack_modules.sh || echo "cannot source $PWD/spack_modules.sh"
module --no-pager -t list
command -v cmake &>/dev/null || die "cmake didn't successfully load"
[ -d rocprofiler-sdk-source ] && rm -Rf rocprofiler-sdk-source
git clone https://github.com/ROCm/rocprofiler-sdk.git -b rocm-6.2.0 rocprofiler-sdk-source
# perfetto's origin and LC fork are not accessible to us
pushd rocprofiler-sdk-source &>/dev/null
git submodule set-url external/perfetto https://github.com/jennfshr/perfetto.git
git submodule set-branch external/perfetto master
popd &>/dev/null
elf_root=$(spack find -p elfutils | tail -n1 | grep elfutils | awk '{print $NF}' | sed 's/ //g')
message -c "elf_root: $elf_root"
export ELF_ROOT=${elf_root}
CPATH+=":${ELF_ROOT}/include"
CPPFLAGS+=" -I ${ELF_ROOT}/include "
CMAKE_PREFIX_PATH+=";${ELF_ROOT}"
CMAKE_EXE_LINKER_FLAGS+=" -L${ELF_ROOT}/lib -ldw "
LDFLAGS+=" -L${ELF_ROOT}/lib -ldw "
hsakml_roct_root=$(spack find -p hsakmt-roct | tail -n1 | grep hsakmt-roct | awk '{print $NF}' | sed 's/ //g')
message -c "hsakml_roct_root: $hsakml_roct_root"
export HSAKML_ROCT_ROOT=$hsakml_roct_root
CPATH+=":${HSAKML_ROCT_ROOT}/include"
CPPFLAGS+=" -I ${HSAKML_ROCT_ROOT}/include " 
CMAKE_PREFIX_PATH+=";${HSAKML_ROCT_ROOT}"
CMAKE_EXE_LINKER_FLAGS+=" -L${HSAKML_ROCT_ROOT}/lib "
LDFLAGS+=" -L${HSAKML_ROCT_ROOT}/lib "
comgr_root=$(spack find -p comgr | tail -n1 | grep comgr | awk '{print $NF}'| sed 's/ //g')
message -c "comgr_root: $comgr_root"
export COMGR_ROOT=$comgr_root
CPATH+=":${COMGR_ROOT}/include"
CPPFLAGS+=" -I ${COMGR_ROOT}/include "
CMAKE_PREFIX_PATH+=";${COMGR_ROOT}"
CMAKE_EXE_LINKER_FLAGS+=" -L${COMGR_ROOT}/lib -lamd_comgr "
LDFLAGS+=" -L${COMGR_ROOT}/lib -lamd_comgr " 
hip_root=$(spack find -p hip | tail -n1 | grep hip | awk '{print $NF}' | sed 's/ //g')
message -c "hip_root: $hip_root"
export HIP_ROOT=$hip_root
CPATH+=":${HIP_ROOT}/include"
CPPFLAGS+=" -I ${HIP_ROOT} " 
CMAKE_PREFIX_PATH+=";${HIP_ROOT}"
CMAKE_EXE_LINKER_FLAGS+=" -L${HIP_ROOT}/lib "
LDFLAGS+=" -L${HIP_ROOT}/lib "
hsa_rocr_root=$(spack find -p hsa-rocr-dev | tail -n1 | grep hsa-rocr | awk '{print $NF}' | sed 's/ //g') 
message -c "hsa_rocr_root: $hsa_rocr_root"
export HSA_ROCR_ROOT=$hsa_rocr_root
CPATH+=":${HSA_ROCR_ROOT}/include"
CPPFLAGS+=" -I ${HSA_ROCR_ROOT} " 
CMAKE_PREFIX_PATH+=";${HSA_ROCR_ROOT}"
CMAKE_EXE_LINKER_FLAGS+=" -L${HSA_ROCR_ROOT}/lib -lhsa-runtime64 "
LDFLAGS+=" -L${HSA_ROCR_ROOT}/lib -lhsa-runtime64 "
message -c "\$CPATH: $CPATH"
message -c "\$CPPFLAGS: $CPPFLAGS"
message -c "\$CMAKE_EXE_LINKER_FLAGS $CMAKE_EXE_LINKER_FLAGS"
export CPATH
export CPPFLAGS
export CMAKE_PREFIX_PATH
export CMAKE_EXE_LINKER_FLAGS
export LDFLAGS

#cmake_exe_linker_flags="'-L${elf_root}/lib -ldw -L${hsakml_roct_root}/lib  -L${comgr_root}/lib -lamd_comgr -L${hip_root}/lib -L${hsa_rocr_root}/lib -lhsa-runtime64'"

[ -d rocprofiler-sdk-source ] && \
message -g "RUNNING: \
cmake \
  -B rocprofiler-sdk-build \
  -DROCPROFILER_BUILD_TESTS=ON \
  -DROCPROFILER_BUILD_SAMPLES=ON \
  -DCMAKE_INSTALL_PREFIX=${SPACK_ROOT}/../rocprof-sdk-6.2.0 \
  rocprofiler-sdk-source/ \
"
cmake \
  -B rocprofiler-sdk-build \
  -DROCPROFILER_BUILD_TESTS=ON \
  -DROCPROFILER_BUILD_SAMPLES=ON \
  -DCMAKE_INSTALL_PREFIX=${SPACK_ROOT}/../rocprof-sdk-6.2.0 \
  rocprofiler-sdk-source/
  
#-DCMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS} \

if [ $? -ne 0 ] ; then die "cmake configure failure" ; fi
message -g "RUNNING: \
cmake \
  --build rocprofiler-sdk-build \
  --target all \
  --parallel 8 \
"
cmake \
  --build rocprofiler-sdk-build \
  --target all \
  --parallel 8

if [ $? -ne 0 ] ; then die "cmake build failure" ; fi
message -g "RUNNING: \
cmake \
  --build rocprofiler-sdk-build \
  --target install \
"

cmake \
  --build rocprofiler-sdk-build \
  --target install

if [ $? -ne 0 ] ; then die "cmake install failure" ; fi
