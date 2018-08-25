require "crosstools_builder/version"
require "crosstools_builder/command"
require "crosstools_builder/arch"
require "crosstools_builder/arch/sparc64"

module CrosstoolsBuilder
  BASEDIR = File.join(ENV["HOME"], ".crosstools")

  class Builder
    module Config
      def self.for(arch)
        klass = Class.new do
          include Config
          include Command

          @@mod = arch
          @@basedir = File.join(CrosstoolsBuilder::BASEDIR, arch.arch)
          def initialize(rootdir: File.join(@@basedir, "root"),
                         toolsdir: File.join(@@basedir, "tools"),
                         builddir: File.join(@@basedir, "build"), nproc: 1)
            @arch = @@mod.arch
            @triple = @@mod.triple
            macros = @@mod.macros
            @builds = @@mod.builds
            @sources = @@mod.sources
            @src = @@mod.src
            @rootdir = File.expand_path(rootdir)
            @toolsdir = File.expand_path(toolsdir)
            @builddir = File.expand_path(builddir)
            @nproc = nproc

            delegator = Class.new() do
              def initialize
              end
            end
            me = self
            delegator.define_method(:call) do |name, *args|
              me.instance_exec(*args, &macros.fetch(name))
            end
            @macros = delegator.new
          end

          def shell(&block)
            Command.shell(self, &block)
          end

          attr_accessor :rootdir, :toolsdir, :builddir, :nproc
          attr_reader :macros, :builds, :sources, :triple, :arch
        end
        obj = klass.new
        obj
      end
    end

    def initialize(arch, *args)
      @config = Config.for(arch, *args)
    end

    def create_dirs
      Command.shell(self) do
        mkdir "-p", @config.rootdir
        mkdir "-p", @config.toolsdir
        mkdir "-p", @config.builddir
      end
    end

    def download_sources
      Command.shell(self) do
        chdir @config.builddir
        mkdir "-p", "src"
        chdir "src" do
          @config.sources.each do |name, src|
            if !File.exist?(src[:archive])
              wget  "--no-check-certificate", src[:uri].to_s
            end
          end
        end
      end
      Command.chdir File.join(@config.builddir, "src")
      @config.sources.each do |name, src|
        klass = nil
        case src[:sum_type]
        when :sha256
          require 'digest/sha2'
          klass = Digest::SHA256
        when :sha384
          require 'digest/sha2'
          klass = Digest::SHA384
        when :sha512
          require 'digest/sha2'
          klass = Digest::SHA512
        when :md5
          require 'digest/md5'
          klass = Digest::MD5
        end
        if klass
          obj = klass.new
          if Command.dryrun || Command.verbose
            $stderr.puts "+ #{src[:sum_type]}sum #{src[:archive]}"
          end
          if !Command.dryrun
            File.open(src[:archive], "r") do |fp|
              while (data = fp.read(4096))
                obj << data
              end
            end
            if obj.hexdigest.downcase != src[:sum_value].downcase
              fail "Checksum does not match for source #{src[:name]}"
            end
          end
        end
      end
    end

    def prepare_source(srcname)
      srcinfo = @config.sources[srcname]
      Command.chdir @config.builddir
      Command.shell(self) do
        rm "-rf", "--preserve-root", srcinfo[:dir]
        if srcinfo[:create_dir]
          mkdir "-p", srcinfo[:dir]
          chdir srcinfo[:dir]
        end
        Command.pipe(self) do
          ext1 = File.extname(srcinfo[:archive])
          an = File.basename(srcinfo[:archive], ext1)
          ext2 = File.extname(an)
          fname = File.join(@config.builddir, "src", srcinfo[:archive])
          case ext1
          when ".tgz", ".txz", ".tbz", ".tbz2"
            tar "-xf", fname
          when ".zip", ".ZIP", ".Zip"
            unzip fname
          when ".gz"
            gzip "-dc", fname
          when ".bz2"
            bzip2 "-dc", fname
          when ".xz"
            xz "-dc", fname
          when ".lz"
            lzip "-dc", fname
          else
            fail "How can I extract #{ext1} archive?"
          end
          if ext2 == ".tar"
            tar "-xf", "-"
          end
        end
      end
    end

    def build_from(name = nil)
      e = @config.builds.each
      m = e.next
      while (m[:title] != name)
        m = e.next
      end
      l = [m]
      begin
        l << e.next
      rescue StopIteration
      end
      if !l.empty?
        build(l)
      else
        $stderr.puts "#{$0}: fatal: Nothing to do."
      end
    end

    def build(list)
      create_dirs
      download_sources
      @config.sources.each do |name, map|
        prepare_source(name)
      end
      list.each do |b|
        pid = Process.fork do
          if b.key?(:chdir)
            srcname = b[:chdir]
            Command.chdir @config.sources[srcname][:dir]
          end
          @config.instance_exec(&b[:run])
        end
        Process.wait(pid)
        if $?.exitstatus != 0
          $stderr.puts "#{$0}: fatal: Subprocess exited with failure."
          exit 1
        end
      end
    end

    def build_all
      build(@config.builds)
    end

    def builds
      @config.builds
    end
  end
end

if $0 == __FILE__
  include CrosstoolsBuilder
  Command.dryrun = true
  builder = Builder.new(Architecture::Sparc64)
  builder.build_all
end
