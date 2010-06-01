require 'thor'

module Hudson
  class CLI < Thor
    
    map "-v" => :version, "--version" => :version, "-h" => :help, "--help" => :help
    
    def self.common_options
      method_option :host, :default => ENV['HUDSON_HOST'] || 'localhost', :desc => 'connect to hudson server on this host'
      method_option :port, :default => ENV['HUDSON_PORT'] || '3001', :desc => 'connect to hudson server on this port'
    end
    
    desc "server [options]", "run a hudson server"
    method_option :home, :type => :string, :default => File.join(ENV['HOME'], ".hudson", "server"), :banner => "PATH", :desc => "use this directory to store server data"
    method_option :port, :type => :numeric, :default => 3001, :desc => "run hudson server on this port"
    method_option :control, :type => :numeric, :default => 3002, :desc => "set the shutdown/control port"
    method_option :daemon, :type => :boolean, :default => false, :desc => "fork into background and run as a daemon"
    method_option :kill, :type => :boolean, :desc => "send shutdown signal to control port"
    method_option :logfile, :type => :string, :banner => "PATH", :desc => "redirect log messages to this file"
    def server
      if options[:kill]
        require 'socket'
        TCPSocket.open("localhost", options[:control]) do |sock|
          sock.write("0")
        end
        exit
      end

      serverhome = File.join(options[:home])
      javatmp = File.join(serverhome, "javatmp")
      FileUtils.mkdir_p serverhome
      FileUtils.mkdir_p javatmp
      FileUtils.cp_r Hudson::PLUGINS, serverhome
      ENV['HUDSON_HOME'] = serverhome
      cmd = ["java", "-Djava.io.tmpdir=#{javatmp}", "-jar", Hudson::WAR]
      cmd << "--daemon" if options[:daemon]
      cmd << "--logfile=#{File.expand_path(options[:logfile])}" if options[:logfile]
      cmd << "--httpPort=#{options[:port]}"
      cmd << "--controlPort=#{options[:control]}"
      puts cmd.join(" ")
      exec(*cmd)
    end

    desc "create [project_path] [options]", "create a continuous build for your project"
    common_options
    method_option :name, :banner => "dir_name", :desc => "name of the build"
    def create(project_path = ".")
      FileUtils.chdir(project_path) do
        unless scm = Hudson::ProjectScm.discover
          error "Cannot determine project SCM. Currently supported: #{Hudson::ProjectScm.supported}"
        end
        job_config = Hudson::JobConfigBuilder.new(:rubygem) do |c|
          c.scm = scm.url
        end
        name = options[:name] || File.basename(FileUtils.pwd)
        Hudson::Api.setup_base_url(options[:host], options[:port])
        if Hudson::Api.create_job(name, job_config)
          build_url = "http://#{options[:host]}:#{options[:port]}/job/#{name.gsub(/\s/,'%20')}/build"
          puts "Added project '#{name}' to Hudson."
          puts "Trigger builds via: #{build_url}"
        else
          error "Failed to create project '#{name}'"
        end
      end
    end
    
    desc "list [project_path] [options]", "list builds on a hudson server"
    common_options
    def list(project_path = ".")
      FileUtils.chdir(project_path) do
        Hudson::Api.setup_base_url(options[:host], options[:port])
        if summary = Hudson::Api.summary
          if summary["jobs"]
            summary["jobs"].each do |job|
              color = job['color']
              color = 'green' if color == 'blue'
              color = 'reset' unless Term::ANSIColor.respond_to?(color.to_sym)
              name, url, color = job['name'], job['url'], c.send(color)
              print color, name, c.reset, " - ", url, "\n"
            end
          else
            display "No jobs found on #{options[:host]}:#{options[:port]}"
          end
        else
          error "Failed connection to #{options[:host]}:#{options[:port]}"
        end
      end      
    end
    
    desc "remote command [options]", "manage integration with hudson servers"
    def remote(command)
      puts command
    end
    
    
    desc "help [command]", "show help for hudson or for a specific command"
    def help(*args)
      super(*args)
    end
    
    desc "version", "show version information"
    def version
      shell.say "#{Hudson::VERSION} (Hudson Server #{Hudson::HUDSON_VERSION})"
    end
    
    def self.print_options(shell, options, grp = nil)
      return if options.empty?
      # shell.say "Options:"
      table = options.map do |option|
        prototype = if option.default
          " [#{option.default}]"
        elsif option.boolean
          ""
        elsif option.required?
          " #{option.banner}"
        else
          " [#{option.banner}]"
        end
        ["--#{option.name}#{prototype}", "\t",option.description]
      end
      shell.print_table(table, :ident => 2)
    end
    
    def self.help(shell)
      list = printable_tasks
      shell.say <<-USEAGE
Hudson.rb is a smart set of utilities for making
continuous integration as simple as possible"

Usage: hudson command [arguments] [options]      

USEAGE

      shell.say "Commands:"
      shell.print_table(list, :ident => 2, :truncate => true)
      shell.say
      class_options_help(shell)
    end

    def self.task_help(shell, task_name)
      meth = normalize_task_name(task_name)
      task = all_tasks[meth]
      handle_no_task_error(meth) unless task
      
      shell.say "usage: #{banner(task)}"
      shell.say
      class_options_help(shell, nil => task.options.map { |_, o| o })
      # shell.say task.description
      # shell.say
    end
    
    private 
    
    def error(text)
      shell.say "ERROR: #{text}"
      exit
    end
    
  end
end