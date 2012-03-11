#!/bin/bash

set -e

function list_platforms()
{
	echo "Known platforms:"
	PLFMS=""
	for i in platforms/*.platform; do
		PLFM=`echo $i | sed -e 's/\.platform$//' -e 's:^platforms/::' |xargs`
		DSCR=`grep 'DESCRIPTION=' "$i" | sed -e 's:.*\"\([^"]*\)\":\1:'`
		PLFMS="$PLFMS$PLFM\$$DSCR\n"
	done
#	echo -en "$PLFMS" | pr -c2 -aT -o4 -W80 -
	echo -en "$PLFMS" | column -t -s\$ | sed 's/^/   /'
}

function status_banner()
{
	echo
	echo
	echo "################################################"
	echo "## $1"
	echo "################################################"
}

function info_banner()
{
	echo
	echo ">>> $1"
	echo
}

# see how many CPUs this machine has -- this will count double for HyperThreaded chips, which is EXACTLY what we want:
# one GCC thread per physical CPU or HyperThreading-provided 'virtual' CPU, plus one awaiting. Except when we're running
# on a unicore box, in which case, one thread is fine.
CPUS=$(expr `cat /proc/cpuinfo  |grep processor |tail -1 |awk '{print $3}'` + 1 || echo 1)
if [ $CPUS -ne 1 ]; then
	JLEV=-j$(expr $CPUS + 1)
else
	JLEV=
fi

BDIR="build-`date +%Y%m%d-%H%M%S`"

PSCRIPT="none"
if [ $# -ge 1 ]; then
	if [ "$1" == "tidy" ]; then
		for i in build-[0-9]*-[0-9]*; do
			info_banner "Tidying build directory '$i'..."
			rm -rf $i
		done
		exit 0
	else
		if [ -f platforms/$1.platform ]; then
			PSCRIPT=$1
			source platforms/$1.platform
		else
			echo "Unrecognised platform '$1'"
			echo
			list_platforms
			exit 1
		fi
	fi
else
	echo "ERROR: Must specify platform on command line, e.g. $0 foobar"
	echo
	list_platforms
	exit 1
fi

# set toolchain base directory if it isn't set already
if [ "x$TCHAINBASE" == "x" ]; then
	TCHAINBASE="$TGT"
fi
PFX="/opt/toolchains/$TCHAINBASE"

mkdir $BDIR
pushd $BDIR

## Info banner
echo "################################################"
echo "## BUILDING A GCC TOOLCHAIN"
echo "################################################"
echo "## Platform script:  $PSCRIPT"
echo "## Target platform:  $TGT"
echo "## Binutils version: $BINUTILS_VER"
echo "## GCC version:      $GCC_VER"
echo "## Newlib version:   $NEWLIB_VER"
if [ x$GDB_VER != x ]; then
	echo "## GDB version:      $GDB_VER"
fi
echo "## Languages:        $LANGUAGES"
echo "## GCC extra config: $GCC_EXTRA_CONFIG"
echo "## Number of CPUs:   $CPUS  (including HyperThreaded virtual CPUs)"
echo "## '-j' option:      $JLEV"
echo "################################################"

## Build Binutils:
status_banner "Building Binutils version $BINUTILS_VER..."

if [ -d binutils-$BINUTILS_DIR ]; then
	info_banner "Deleting old binutils build files..."
	rm -rf binutils-$BINUTILS_DIR
fi

info_banner "Unpacking binutils..."
tar -jxf ../binutils-$BINUTILS_VER.tar.bz2

pushd binutils-$BINUTILS_DIR
mkdir build
cd build

info_banner "Configuring binutils..."
../configure --prefix=$PFX --target=$TGT

info_banner "### Building binutils..."
make $JLEV

info_banner "Installing binutils..."
make install
popd



## Build GCC and Newlib:
status_banner "Building GCC version $GCC_VER with Newlib version $NEWLIB_VER..."

if [ -d gcc-$GCC_VER ]; then
	info_banner "Deleting old gcc build files..."
	rm -rf gcc-$GCC_VER
fi

if [ -d newlib-$NEWLIB_VER ]; then
	info_banner "Deleting old newlib build files..."
	rm -rf newlib-$NEWLIB_VER
fi

info_banner "Unpacking gcc..."
tar -jxf ../gcc-$GCC_VER.tar.bz2

info_banner "Unpacking newlib..."
tar -zxf ../newlib-$NEWLIB_VER.tar.gz

pushd gcc-$GCC_VER
ln -s ../newlib-$NEWLIB_VER/newlib newlib
mkdir build; cd build
export PATH=$PATH:$PFX/bin

info_banner "Configuring gcc..."
../configure --prefix=$PFX --target=$TGT --enable-languages=c,c++ --with-newlib $GCC_EXTRA_CONFIG

info_banner "Building gcc..."
make $JLEV

info_banner "Installing gcc..."
make install
popd


## Build GDB and GDBserver
if [ x$GDB_VER != x ]; then
	status_banner "Building GDB and GDBserver version $GDB_VER..."

	if [ -d gdb-$GDB_VER ]; then
		info_banner "Deleting old gdb build files..."
		rm -rf gdb-$GDB_VER
	fi

	info_banner "Unpacking GDB version $GDB_VER..."
	tar -jxf ../gdb-$GDB_VER.tar.bz2

	pushd gdb-$GDB_VER
	mkdir build; cd build
	
	info_banner "Configuring GDB..."
	../configure --prefix=$PFX --target=$TGT

	info_banner "Building GDB..."
	make $JLEV

	info_banner "Installing GDB..."
	make install

	if [ x$BUILD_GDB_SERVER == x1 ]; then
		cd ../gdbserver
		mkdir build; cd build

		info_banner "Configuring GDB Server..."
		../configure --prefix=$PFX/platform --target=$TGT

		info_banner "Building GDB Server..."
		make $JLEV

		info_banner "Installing GDB Server..."
		make install
	else
		info_banner "GDB Server build skipped -- not required by platform spec."
	fi
	popd
fi


status_banner "Build complete."

popd	# $BDIR



