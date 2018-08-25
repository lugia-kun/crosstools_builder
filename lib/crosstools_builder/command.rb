#!ruby
# coding: utf-8

module CrosstoolsBuilder
  module Command
    class Error < RuntimeError
    end

    class AlreadyRunningError < Error
    end

    class NotRunningError < Error
    end

    class NonZeroExitError < Error
    end

    @@dryrun = false
    @@verbose = false

    def self.dryrun
      @@dryrun
    end

    def self.verbose
      @@verbose
    end

    def self.dryrun=(flag)
      @@dryrun = !!flag
    end

    def self.verbose=(flag)
      @@verbose = !!flag
    end

    SHELL_SAFE = %r![-:a-zA-Z0-9+/,.@%_=]!
    def self.shell_escape(str)
      if str !~ /^#{SHELL_SAFE}+$/
        flag = false
        m = str
        nstr = ""
        while m.length > 0
          a = m.partition(/[^[:ascii:]]+/)
          n = a[0]
          while n.length > 0
            b = n.partition(/[[:cntrl:]'\\]+/)
            nstr << b[0]
            b[1].each_char do |ch|
              nstr << case ch
                      when "'"
                        flag = true
                        "\\'"
                      when "\\"
                        "\\\\"
                      when "\n"
                        "\\n"
                      when "\r"
                        "\\r"
                      when "\t"
                        "\\t"
                      else
                        flag = true
                        "\\x02x" % (ch.unpack("U"))
                      end
            end
            n = b[2]
          end
          if a[1].length > 0
            if a[1].encoding == Encoding::UTF_8
              enum = a[1].unpack("U*").each
            else
              enum = a[1].unpack("C*").each
            end
            enum.each do |ch|
              flag = true
              if ch < 0x100
                nstr << "\\x%02x" % ch
              elsif ch < 0x10000
                nstr << "\\u%04x" % ch
              else
                nstr << "\\U%08x" % ch
              end
            end
          end
          m = a[2]
        end
        nstr << "'"
        if flag
          nstr = "$'" + nstr
        else
          nstr = "'" + nstr
        end
        str = nstr
      end
      str
    end

    def self.for_fd(obj)
      if obj.is_a?(IO)
        obj.fileno
      elsif obj.is_a?(Integer)
        obj
      elsif obj.is_a?(String)
        obj
      elsif obj.is_a?(Array) && obj[0].is_a?(String)
        obj[0]
      elsif obj == :in
        0
      elsif obj == :out
        1
      elsif obj == :err
        2
      elsif obj == :close
        -1
      else
        nil
      end
    end

    class Process
      def initialize(*args)
        if args.last.is_a?(Hash)
          @opts = args.pop.dup
        else
          @opts = {}
        end
        if args.first.is_a?(Hash)
          @env = args.shift
        else
          @env = {}
        end
        @dryrun = @opts[:dryrun]
        @verbose = @opts[:verbose]
        @ignore_exit = @opts[:ignore_exit]
        @opts.delete(:dryrun)
        @opts.delete(:verbose)
        @opts.delete(:ignore_exit)
        @dryrun = Command.dryrun if @dryrun.nil?
        @verbose = Command.verbose if @verbose.nil?
        @ignore_exit = false if @ignore_exit.nil?
        @pid = nil
        @laststatus = nil
        @command = args.shift
        @args = args
      end

      def initialize_copy
        @pid = nil
        @laststatus = nil
      end

      attr_reader :pid, :laststatus
      attr_reader :dryrun, :verbose
      attr_reader :command

      def dryrun=(flag)
        @dryrun = !!flag
      end

      def verbose=(flag)
        @verbose = !!flag
      end

      def make_command_string
        if @command_string.nil?
          str = []
          if @opts[:chdir]
            chdir = @opts[:chdir]
            chdir ||= ""
            if chdir != ""
              str << "cd"
              str << Command.shell_escape(chdir)
              str << "&&"
            end
          end
          if @env.empty?
            if @opts[:unsetenv_others]
              str << "env"
              str << "-i"
            end
          else
            str << "env"
            if @opts[:unsetenv_others]
              str << "-i"
            end
            @env.each do |k, v|
              if v
                str << Command.shell_escape("#{k}=#{v}")
              else
                str << "-u"
                str << Command.shell_escape(k)
              end
            end
          end
          if @command.is_a?(Array)
            str << Command.shell_escape(@command[1])
          else
            str << Command.shell_escape(@command)
          end
          @args.each do |pa|
            str << Command.shell_escape(pa)
          end
          @opts.each do |k, v|
            if !k.is_a?(Array)
              k = [k]
            end
            k.each do |x|
              fd = Command.for_fd(x)
              if fd
                vfd = Command.for_fd(v)
                if vfd.is_a?(Integer)
                  if vfd < 0
                    str << "#{fd}<>&-"
                  else
                    str << "#{fd}<>&#{vfd}"
                  end
                elsif vfd
                  str << "#{fd}<>#{Command.shell_escape(vfd)}"
                end
              end
            end
          end
          @command_string = str.join(" ")
        end
        @command_string
      end

      #def inspect
      #  b = "#<CrossBuilder::Command %!#{make_command_string}!"
      #  if @pid
      #    b << " (pid #{@pid})"
      #  else
      #    if @laststatus
      #      b << " (exited; #{@laststatus})"
      #    else
      #      b << " (not running)"
      #    end
      #  end
      #  b << ">"
      #  b
      #end

      def start
        fail AlreadyRunningError, "Already running at this instance" if @pid

        if @verbose || @dryrun
          $stderr.puts "+ " + make_command_string
        end
        if !@dryrun
          if !@args.empty?
            @pid = ::Process.spawn(@env, @command, *@args, @opts)
          else
            @pid = ::Process.spawn(@env, @command, @opts)
          end
        else
          @pid = :dryrun
        end
      end

      def wait
        fail NotRunningError, "Command Not Runnng" unless @pid

        if @pid != :dryrun
          ::Process.wait(@pid)
          @laststatus = $?
          unless @ignore_exit
            if @laststatus.exitstatus != 0
              fail NonZeroExitError, "Command exited with #{@laststatus.exitstatus}"
            end
          end
        else
          @laststatus = nil
        end
        @pid = nil
      end

      def run
        start
        wait
      end
    end

    def self.run(*args)
      cmd = Process.new(*args)
      cmd.start
      cmd.wait
    end

    def self.chdir(path, opts = {}, &block)
      verb = opts[:verbose] || verbose
      dry  = opts[:dryrun] || dryrun
      if block_given?
        if verb || dry
          $stderr.puts "+ pushd #{shell_escape(path)}"
        end
        if !dry
          ret = Dir.chdir(path, &block)
        else
          ret = block.call(path)
        end
        if verb || dry
          $stderr.puts "+ popd"
        end
        ret
      else
        if verb || dry
          $stderr.puts "+ cd #{shell_escape(path)}"
        end
        if !dry
          Dir.chdir(path)
        else
          path
        end
      end
    end

    def self.chroot(path, opts = {})
      verb = opts[:verbose] || verbose
      dry  = opts[:dryrun] || dryrun
      if verb || dry
        $stderr.puts "+ chroot #{shell_escape(path)}"
      end
      if !dry
        Dir.chroot(path)
      else
        path
      end
    end

    module DSL
      def self.method_missing_wrapper(name, args)
        env = nil
        if args.first.is_a?(Hash)
          env = args.shift
        end
        args.unshift name.to_s
        if env
          args.unshift env
        end
        args
      end

      def method_missing(name, *args)
        args = DSL.method_missing_wrapper(name, args)
        Command.run(*args)
      end

      def chdir(path, &block)
        Command.chdir(path, &block)
      end

      def cd(path)
        Command.chdir(path)
      end

      def chroot(path)
        Command.chroot(path)
      end

      def run(*args)
        Command.run(*args)
      end
    end

    module PipeDSL
      def method_missing(name, *args)
        args = DSL.method_missing_wrapper(name, args)
        @__pipe_list << Command::Process.new(*args)
      end

      def __pipe_dsl_init
        @__pipe_list ||= []
      end

      def __pipe_dsl_exec
        return nil if @__pipe_list.nil? || @__pipe_list.empty?
        cls_pipe = nil
        @__pipe_list.inject do |a, b|
          r, w = IO.pipe
          a.instance_eval do
            @opts[:out] = w
          end
          b.instance_eval do
            @opts[:in] = r
          end
          a.start
          w.close
          cls_pipe.close if cls_pipe
          cls_pipe = r
          b
        end.start
        cls_pipe.close if cls_pipe
        @__pipe_list.each do |m|
          m.wait
        end
        stat = @__pipe_list[-1].laststatus
        @__pipe_list.clear
        stat
      end
    end

    def self.shell(obj, &block)
      obj = obj.dup
      class << obj
        include DSL
      end
      obj.freeze
      obj.instance_eval(&block)
    end

    def self.pipe(obj, &block)
      obj = obj.dup
      class << obj
        include PipeDSL
      end
      obj.__pipe_dsl_init
      obj.freeze
      obj.instance_exec(&block)
      obj.__pipe_dsl_exec
    end

    def self.path_append(var = "PATH", value)
      val = (ENV[var] || "").split(":")
      val << value
      val.uniq!
      val.delete("")
      val = val.join(":")
      if !dryrun
        ENV[var] = val
      end
      if verbose || dryrun
        esc = shell_escape("#{var}=#{val}")
        $stderr.puts "+ export #{esc}"
      end
    end

    def self.path_prepend(var = "PATH", value)
      val = (ENV[var] || "").split(":")
      val.unshift value
      val.uniq!
      val.delete("")
      val = val.join(":")
      if !dryrun
        ENV[var] = val
      end
      if verbose || dryrun
        esc = shell_escape("#{var}=#{val}")
        $stderr.puts "+ export #{esc}"
      end
    end

    def self.export(var, value)
      if !dryrun
        ENV[var] = value
      end
      if verbose || dryrun
        esc = shell_escape("#{var}=#{val}")
        $stderr.puts "+ export #{esc}"
      end
    end

    def path_append(*args)
      Command.path_append(*args)
    end

    def path_prepend(*args)
      Command.path_prepend(*args)
    end

    def export(*args)
      Command.export(*args)
    end
  end
end


if $0 == __FILE__
  Command = CrosstoolsBuilder::Command
  cmd = Command::Process.new("ls")
  cmd.start
  cmd.wait
  p cmd

  cmd.verbose = true
  cmd.run

  cmd = Command::Process.new("echo", "!", "$", "あ", "?", verbose: true, in: :close, err: "/dev/null")
  cmd.run

  Command.verbose = true
  cmd = Command::Process.new({"FOO" => "BAR", "PATH" => nil}, "env")
  cmd.run

  Command.run("pwd", chdir: "/")
  Command.run({"A" => "Bあ\nfoo bar"}, "env", :unsetenv_others => true)

  # Command.dryrun = true
  @value = 1
  Command.shell(self) do
    p @value
    ls "/"
    pwd
    chdir "/" do
      pwd
      cd "usr"
      pwd
      ls
    end
    ### Not allowed.
    # @value = 5
    pwd

    Command.pipe(self) do
      ls
      sed "-e", "s:a:b:g"
    end
    r, w = IO.pipe
    Command.pipe(self) do
      ls({"LANG" => "C"}, "-l")
      grep "-v", "^d"
      sed "-r", "-e", "s: +:\\t:g"
      cut "-f9"
      xargs "head", "-n", "1"
      grep "-E", "==>|#!", out: w
    end
    w.close
    m = r.read
    $stderr.puts m.inspect
  end

  # modification of @value has no effect.
  fail "@value == 1" unless @value == 1
  begin
    ls
    fail "ls should raise NoMethodError or NameError"
  rescue NoMethodError, NameError
  end
end
