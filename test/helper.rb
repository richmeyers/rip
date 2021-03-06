require 'test/unit'
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'stringio'

# Ensure lib is in path for subcommands
libdir = File.expand_path('../../lib', __FILE__)
if ENV['RUBYLIB']
  ENV['RUBYLIB'] += ":#{libdir}/"
else
  ENV['RUBYLIB'] = "#{libdir}/"
end

require 'rip'

$stderr = StringIO.new
Rip::Test = Test::Unit::TestCase
$stderr = STDERR

class Rip::Test
  include FileUtils

  # Setup test/ripdir for testing as a valid rip directory.
  # Remove it after test runs.
  def setup
    @ripdir = File.expand_path(File.dirname(__FILE__) + "/ripdir")
    rm_rf @ripdir
    ENV['RIPVERBOSE'] = nil
    ENV['RIPDEBUG'] = nil
    ENV['RIPPROCESSES'] = nil
    ENV['RIPENV'] = nil
    ENV['RIPDIR'] = @ripdir
    rip "setup"

    start_git_daemon
    start_gem_daemon
  end

  def teardown
    rm_rf @ripdir
  end

  def self.test(name, &block)
    define_method("test_#{name.gsub(/\W/, '_')}", &block) if block
  end

  # Asserts that `haystack` includes `needle`.
  def assert_includes(needle, haystack, message = nil)
    message = build_message(message, '<?> is not in <?>.', needle, haystack)
    assert_block message do
      haystack.include? needle
    end
  end

  # Asserts that `haystack` does not include `needle`.
  def assert_not_includes(needle, haystack, message = nil)
    message = build_message(message, '<?> is in <?>.', needle, haystack)
    assert_block message do
      !haystack.include? needle
    end
  end
  alias_method :assert_doesnt_include, :assert_not_includes

  # Asserts that the last exited child process (probably `rip`) exited
  # successfully.
  def assert_exited_successfully(message = nil)
    actual = $?.exitstatus
    message = build_message(message, 'rip exited with <?>, not 0', actual)
    assert_block message do
      $?.success?
    end
  end

  # Asserts that the last exited child process (probably `rip`) did
  # not exit successfully.
  def assert_exited_with_error(message = nil)
    message = build_message(message, 'rip exited with 0, not > 0')
    assert_block message do
      !$?.success?
    end
  end

  # Given a String of content, returns a Tempfile.
  def tempfile(content)
    file = Tempfile.new("rip")
    file.puts content
    file.close

    file
  end

  # Writes the content of a String block to the specified `file`.
  def write(file, &content)
    File.open(file, 'w') { |f| f.puts content.call }
  end

  # Shortcut for running the `rip` command in a subprocess. Returns
  # STDOUT as a string. Pass it what you would normally pass `rip` on
  # the command line, e.g.
  #
  # shell: rip create github
  #  test: rip("create github")
  #
  # If a block is given it will be run in the child process before
  # execution begins. You can use this to monkeypatch or fudge the
  # environment before running `rip`.
  def rip(subcommand)
    args = subcommand.split(' ')
    subcommand = args.shift

    parent_read, child_write = IO.pipe

    pid = fork do
      yield if block_given?
      $stdout.reopen(child_write)
      $stderr.reopen(child_write)
      ENV['PATH'] = "bin/:#{ENV['PATH']}"
      exec "rip-#{subcommand}", *args
    end

    # Wait for the process to exit so we can use $?
    # in our tests.
    Process.waitpid(pid)

    child_write.close
    out = parent_read.read

    # Set the PRINT env variable to see rip command output during
    # test execution.
    if ENV['PRINT']
      require 'colored'
      puts
      puts ['$'.yellow, 'rip', subcommand, *args].join(' ').yellow
      print $?.exitstatus.to_s.send($?.success? ? :green : :red)
      print '> '.blue
      puts out.empty? ? "(no output)" : out
    end

    out
  end

  # Emulates `rip-push env`
  def rip_push(env)
    ENV['RUBYLIB'] += ":#{ENV['RIPDIR']}/#{env}/lib"
    ENV['PATH'] += ":#{ENV['RIPDIR']}/#{env}/bin"
    ENV['MANPATH'] += ":#{ENV['RIPDIR']}/#{env}/man"
  end

  # Given a name, returns the path to the fixture's directory.
  def fixture(name)
    name = name.to_s
    name = name.include?('.') ? name : "#{name}.git"
    "test/fixtures/#{name}"
  end

  def start_git_daemon
    return if `ps aux | grep [g]it-daemon`.to_s.strip.length != 0
    $start_git_daemon ||= start_git_daemon!
  end

  def start_git_daemon!
    daemon_pid = Tempfile.new("pid")

    pid = fork do
      path = daemon_pid.path
      exec "git daemon --export-all --base-path=test/fixtures --pid-file=#{path}"
    end

    at_exit do
      # kill child "git" process
      Process.kill "TERM", pid
      Process.wait pid

      # "git" doesn't kill its child "git-daemon" process
      Process.kill "TERM", daemon_pid.read.to_i
      daemon_pid.unlink
    end

    true
  end

  def start_gem_daemon
    ENV['RPGPATH']     = "#{Dir.tmpdir}/rpg"
    ENV['RPGSPECSURL'] = "http://localhost:8808/specs.4.8.gz"
    ENV['RPGGEMURL']   = "http://localhost:8808/gems"

    ENV['RPGPATH']  = rpgpath = "#{File.dirname(__FILE__)}/fixtures/rpg"
    ENV['RPGDB']    = "#{rpgpath}/db"
    ENV['RPGINDEX'] = "#{rpgpath}/index"
    ENV['RPGPACKS'] = "#{rpgpath}/packs"
    ENV['RPGCACHE'] = "#{rpgpath}/cache"

    ENV['GEM_SERVER'] = "http://localhost:8808/"
    return if `ps aux | grep "[g]em server"`.to_s.strip.length != 0
    $start_gem_daemon ||= start_gem_daemon!
  end

  def start_gem_daemon!
    pid = fork do
      exec "exec gem server --dir test/fixtures/gems --no-daemon &> /dev/null"
    end

    at_exit do
      Process.kill "TERM", pid
      Process.wait pid
    end

    true
  end
end
