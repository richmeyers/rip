module Rip
  class Package < OpenStruct
    def self.parse_args(args)
      source = args[0]

      if args[1] =~ /^\//
        path    = args[1]
        version = args[2]
      else
        path    = '/'
        version = args[1]
      end

      [source, path, version]
    end

    def self.parse(text)
      new(Parser.parse(text).first)
    end

    def to_s
      "#{name} (#{version})"
    end

    def inspect
      "#<Rip::Package name=#{name.inspect} version=#{version.inspect}>"
    end

    def version(long = false)
      return super() if long

      if real_version = super()
        real_version.length == 40 ? real_version[0,10] : real_version
      end
    end

    def name
      source.split('/').last.chomp('.git').chomp('.gem')
    end

    def dependencies
      Array(super).map { |dep| self.class.new(dep) }
    end
  end

  class Environment
    attr_accessor :text

    def initialize(path = nil)
      path = path.strip if path.is_a?(String)

      if path && path.is_a?(Array)
        @text = ''
        path.each { |p| merge(p) }
      elsif path && path.include?('/') && File.directory?(path)
        @path = "#{path}/metadata.rip"
        @text = File.read(@path)
      elsif path && File.exists?(path)
        @path = path
        @text = File.read(path)
      else
        @text = path.to_s
      end
    end

    def to_s
      packages.map { |package| package.to_s } * "\n"
    end

    def merge(env)
      @text << "\n#{Environment.new(env).text}"
    end

    def [](name)
      packages.detect { |p| p.name == name }
    end

    def packages
      Rip::Parser.parse(@text).map do |hash|
        package_and_dependencies Package.new(hash)
      end.flatten
    end

    def package_and_dependencies(package)
      packages = []
      packages << package
      package.dependencies.each do |dep|
        packages.concat package_and_dependencies(dep)
      end

      packages
    end

    def conflicts?
      conflicts.any?
    end

    def conflicts
      hash = {}
      bad  = []

      packages.each do |package|
        installed_at = hash[package.name]
        if installed_at && package.version && installed_at != package.version
          bad << package
        else
          hash[package.name] = package.version if package.version
        end
      end

      bad
    end
  end
end
