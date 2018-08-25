
require 'crosstools_builder/arch'

CrosstoolsBuilder::Architecture.define :Sparc64 do
  arch   "sparc64"
  triple "sparc64-suse-linux-gnu"
  source "binutils",
         "ftp://ftp.gnu.org/pub/gnu/binutils/binutils-2.31.tar.xz",
         sha512: "3448a71c42d790569c1159c1042aa520b2d8ac8af7506fb1f2a4199dfb13b39f1c2271a5cb3a643d10c7d8a388a73f190e90503d4793a016da7893473aa1c635"
  source "gcc",
         "ftp://gcc.gnu.org/pub/gcc/releases/gcc-7.3.0/gcc-7.3.0.tar.xz",
         sha512: "ad41a7e4584e40e92cdf860bc0288500fbaf5dfb7e8c3fcabe9eba809c87bcfa85b46c19c19921b0cdf6d05483faede8287bb9ea120c0d1559449a70e602c8d4"
  source "glibc",
         "ftp://ftp.gnu.org/pub/gnu/glibc/glibc-2.26.tar.xz",
         sha512: "6ed368523bc55f00976f96c5177f114e3f714b27273d7bffc252812c8b98fb81970403c1f5b5f0a61da678811532fb446530745492d2b49bfefc0d5bd71ce8c0"
  source "mpc",
         "ftp://ftp.gnu.org/pub/gnu/mpc/mpc-1.1.0.tar.gz",
         sha512: "72d657958b07c7812dc9c7cbae093118ce0e454c68a585bfb0e2fa559f1bf7c5f49b93906f580ab3f1073e5b595d23c6494d4d76b765d16dde857a18dd239628"
  source "gmp",
         "ftp://ftp.gnu.org/pub/gnu/gmp/gmp-6.1.2.tar.xz",
         sha512: "9f098281c0593b76ee174b722936952671fab1dae353ce3ed436a31fe2bc9d542eca752353f6645b7077c1f395ab4fdd355c58e08e2a801368f1375690eee2c6"
  source "mpfr",
         "ftp://ftp.gnu.org/pub/gnu/mpfr/mpfr-3.1.6.tar.xz",
         sha512: "746ee74d5026f267f74ab352d850ed30ff627d530aa840c71b24793e44875f8503946bd7399905dea2b2dd5744326254d7889337fe94cfe58d03c4066e9d8054"
  source "isl",
         "ftp://gcc.gnu.org/pub/gcc/infrastructure/isl-0.18.tar.bz2",
         sha512: "85d0b40f4dbf14cb99d17aa07048cdcab2dc3eb527d2fbb1e84c41b2de5f351025370e57448b63b2b8a8cf8a0843a089c3263f9baee1542d5c2e1cb37ed39d94"
  source "cloog",
         "ftp://gcc.gnu.org/pub/gcc/infrastructure/cloog-0.18.1.tar.gz",
         sha512: "0b12d9f3c39a2425e28e1d7c0a2b3787287fe3e6e3052f094d2ab6cffeb205ce19044100cbfd805659b3e6b3d21ac2f5a3c92848f476de54edfe6b1cbd2172e9"
  source "kernel",
         "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.63.tar.xz",
         sha512: "5c9a1e472fb5c240d01ee38c4748b75b1dcdda0612f6fcc42fbd6929f17b63c7a601f9e77681fcef1053866e1ec8d1a299562adbf3dca391fe4773d84243a893"
  source "coreutils",
         "ftp://ftp.gnu.org/pub/gnu/coreutils/coreutils-8.30.tar.xz",
         sha512: "25bc132c0d89ce71c33e417f04649c9fcfce6c5ef8b19f093b2e9e2851bfde9b5a31e20499d9c427332228ba54b88d445ddb445551e1944bb8f5cbff5ffa4eda"
  source "bash",
         "https://ftp.gnu.org/pub/gnu/bash/bash-4.4.18.tar.gz",
         sha512: "bd3048338aded9dee31651011aaa46bc8fba83a27fa063e3d47bcbe85ebbd86816d9080d1a658cfbd1736a2c80e98fdb659019c192d332472b00aa305e0285b0"

  define_macro "gcc-clean-deps" do |list = %w[mpc mpfr gmp isl cloog]|
    shell do
      list.each do |m|
        gccdir = File.join(@src["gcc"], m)
        rm "-rf", "--preserve-root", gccdir
      end
    end
  end

  define_macro "gcc-copy-deps" do |list = %w[mpc mpfr gmp isl cloog]|
    shell do
      list.each do |m|
        gccdir = File.join(@src["gcc"], m)
        rm "-rf", "--preserve-root", gccdir
        cp "-R", @src[m], gccdir
      end
    end
  end

  define_macro "make" do |*args|
    begin
      shell do
        make "-j#{@jobs}", *args
      end
    rescue Command::NonZeroExitError
      shell do
        make *args
      end
    end
  end

  build do
    part "binutils", chdir: "binutils" do
      shell do
        ln "-s", "lib", "#{@toolsdir}/lib64"
        rm "-rf", "build"
        mkdir "build"
        chdir "build" do
          run "../configure",
              "--prefix=#{@toolsdir}",
              "--libdir=#{@toolsdir}/lib",
              "--target=#{@triple}"
          @macros.call "make"
          make "install"
        end
      end
    end

    part "kernel-headers", chdir: "kernel" do
      dir = File.join(@rootdir, "usr")
      shell do
        make "clean"
        make "mrproper"
        make "ARCH=#{@arch}", "defconfig"
        make "ARCH=#{@arch}", "headers_check"
        make "ARCH=#{@arch}", "INSTALL_HDR_PATH=#{dir}", "headers_install"
      end
    end

    part "glibc-headers", chdir: "glibc" do
      shell do
        rm "-rf", "build-headers"
        mkdir "build-headers"
        chdir "build-headers" do
          run "../configure",
              "--prefix=#{@rootdir}",
              "--includedir=#{@rootdir}/usr/include",
              "--with-headers=#{@rootdir}/usr/include"
          make "-k", "cross_compiling=yes", "install-headers"
        end
        cp "include/gnu/stubs.h",
           File.join(@rootdir, "usr", "include", "gnu")
      end
    end

    part "adjust-paths" do
      shell do
        chdir "#{@rootdir}" do
          mkdir "-p", "usr"
          ln "-s", "lib", "usr/lib64"
          ln "-s", "lib", "lib64"
        end
      end
    end

    part "gcc-step-1", chdir: "gcc" do
      @macros.call "gcc-clean-deps", %w[isl cloog]
      @macros.call "gcc-copy-deps", %w[mpc mpfr gmp]
      path_prepend File.join(@toolsdir, "bin")
      shell do
        rm "-rf", "build-step-1"
        mkdir "build-step-1"
        chdir "build-step-1"
        run "../configure",
            "--prefix=#{@toolsdir}",
            "--target=#{@triple}",
            "--with-sysroot=#{@rootdir}",
            "--without-headers",
            "--enable-languages=c",
            "--disable-libquadmath",
            "--disable-libssp",
            "--disable-libstdcxx",
            "--disable-libatomic",
            "--disable-shared",
            "--disable-multilib",
            "--disable-cloog",
            "--disable-libgomp"
        @macros.call "make"
        make "install"
      end
    end

    part "glibc-step-1", chdir: "glibc" do
      path_prepend File.join(@toolsdir, "bin")
      shell do
        rm "-rf", "build-step-1"
        mkdir "build-step-1"
        chdir "build-step-1" do
          run "../configure",
              "--prefix=/usr",
              "--libdir=/lib",
              "--host=#{@triple}",
              "--disable-multilib"
          @macros.call "make"
          make "install", "install_root=#{@rootdir}"
        end
      end
    end

    part "gcc-step-2", chdir: "gcc" do
      @macros.call "gcc-copy-deps"
      path_prepend File.join(@toolsdir, "bin")
      shell do
        rm "-rf", "build-step-2"
        mkdir "build-step-2"
        chdir "build-step-2"
        run "../configure",
            "--prefix=#{@toolsdir}",
            "--target=#{@triple}",
            "--with-sysroot=#{@rootdir}",
            "--enable-languages=c,c++,fortran,objc",
            "--disable-multilib"
        @macros.call "make"
        make "install"
      end
    end

    part "gcc-native", chdir: "gcc" do
      @macros.call "gcc-copy-deps"
      path_prepend File.join(@toolsdir, "bin")
      shell do
        rm "-rf", "build-native"
        mkdir "build-native"
        chdir "build-native" do
          run "../configure",
              "--prefix=/usr",
              "--host=#{@triple}",
              "--target=#{@triple}",
              "--disable-bootstrap",
              "--disable-multilib"
          @macros.call "make"
          make "install", "DESTDIR=#{@rootdir}"
        end
      end
    end

    part "bash", chdir: "bash" do
      path_prepend File.join(@toolsdir, "bin")
      shell do
        if File.exist?("Makefile")
          make "distclean"
        end
        run "./configure", "--prefix=/usr", "--host=#{@triple}"
        @macros.call "make"
        make "install", "DESTDIR=#{@rootdir}"
        chdir @rootdir do
          mkdir "-p", "bin"
          ln "-s", "bash", "bin/sh"
          %w[bash].each do |m|
            ln "-s", File.join("..", "usr", "bin", m), File.join("bin", m)
          end
        end
      end
    end

    part "coreutils", chdir: "coreutils" do
      path_prepend File.join(@toolsdir, "bin")
      shell do
        if File.exist?("Makefile")
          make "distclean"
        end
        run "./configure", "--prefix=/usr", "--host=#{@triple}"
        @macros.call "make"
        make "install", "DESTDIR=#{@rootdir}"
        chdir @rootdir do
          mkdir "-p", "bin"
          %w[basename cat chgrp chmod chown cp date dd df echo false
             ln ls md5sum mkdir mknod mktemp mv pwd readlink rm rmdir sleep
             sort stat stty sync touch true uname].each do |m|
            ln "-s", File.join("..", "usr", "bin", m), File.join("bin", m)
          end
        end
      end
    end

  end
end
