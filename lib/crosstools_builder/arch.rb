
require 'uri'
require 'crosstools_builder/command'

module CrosstoolsBuilder
  module Architecture
    def self.define(sym, &block)
      cls = Class.new
      mod = Module.new do |mod|
        @arch = nil
        @triple = nil
        @macros = {}
        @builds = []
        @sources = {}
        @src = {}

        def mod.arch
          @arch
        end
        def mod.triple
          @triple
        end
        def mod.macros
          @macros
        end
        def mod.builds
          @builds
        end
        def mod.sources
          @sources
        end
        def mod.src
          @src
        end
      end
      set = Module.new do |m|
        m.define_method(:set_arch) do |x|
          mod.instance_variable_set(:@arch, x)
        end
        m.define_method(:set_triple) do |x|
          mod.instance_variable_set(:@triple, x)
        end
        m.define_method(:add_source) do |name, x|
          mod.instance_variable_get(:@sources)[name] = x
          mod.instance_variable_get(:@src)[name] = x[:dir]
        end
        m.define_method(:add_macro) do |name, x|
          mod.instance_variable_get(:@macros)[name] = x
        end
        m.define_method(:add_build) do |x|
          mod.instance_variable_get(:@builds) << x
        end
      end
      cls.extend mod
      cls.extend set
      cls.extend Architecture
      cls.instance_eval(&block)
      const_set(sym, mod)
      @@defined_archs ||= {}
      @@defined_archs[cls.instance_variable_get(:@arch)] = cls
    end

    def self.defined_archs
      @@defined_archs
    end

    def arch(name)
      set_arch(name)
    end

    def triple(name)
      set_triple(name)
    end

    def source(name, uri, opts = {})
      uri = URI.parse(uri)
      archive = File.basename(uri.path)
      if opts.key?(:dir)
        dir = opts[:dir]
      else
        ext = File.extname(archive)
        archive_woe = File.basename(archive, ext)
        ext = File.extname(archive_woe)
        if ext == ".tar"
          archive_woe = File.basename(archive_woe, ext)
        end
        dir = archive_woe
      end
      sum_type = %i[sha512 sha384 sha256 md5].find do |x|
        opts.key?(x)
      end
      if sum_type
        sum_value = opts[sum_type]
      else
        sum_type = :none
        sum_value = nil
      end
      src = {
        uri: uri,
        archive: archive,
        dir: dir,
        create_dir: !!opts[:create_dir],
        sum_type: sum_type,
        sum_value: sum_value,
      }
      add_source(name, src)
    end

    def define_macro(name, &block)
      add_macro(name, block)
    end

    def build(&block)
      cls = Class.new(self) do
        def self.part(name, opts = {}, &block)
          m = Hash.new
          m[:name] = name
          m[:run] = block
          if opts.key?(:chdir)
            m[:chdir] = opts[:chdir]
          end
          add_build(m)
        end
      end
      cls.instance_eval(&block)
    end

  end
end
