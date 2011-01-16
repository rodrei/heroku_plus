require "optparse"
require "yaml"

class HerokuPlus
  VERSION = "1.4.0"
  
  # Execute.
  def self.run args = ARGV
    hp = HerokuPlus.new
    hp.parse_args args
  end

  # Initialize.
  def initialize
    # Set defaults.
    @heroku_home = File.join ENV["HOME"], ".heroku"
    @heroku_credentials = "credentials"
    @ssh_home = File.join ENV["HOME"], ".ssh"
    @git_config_file = ".git/config"
    @settings = {:ssh_id => "id_rsa", :mode => "stage"}
    @settings_file = File.join @heroku_home, "heroku_plus.yml"

    # Apply custom settings (if any).
    if File.exists? @settings_file
      begin
        settings = YAML::load_file @settings_file
        @settings.merge! settings.reject {|key, value| value.nil?}
      rescue
        puts "ERROR: Invalid #{@settings_file} settings file."
      end
    end
    
    # Load modes and ensure current mode is set.
    load_modes
  end

  # Read and parse the supplied command line arguments.
  def parse_args args = ARGV
    # Defaults.
    args = ["-h"] if args.empty?

    # Options.
    parser = OptionParser.new do |o|
      o.banner = "Usage: hp [options]"

      o.separator ''
      o.separator "Account Management:"
      o.on "-s", "--switch ACCOUNT", String, "Switch Heroku credentials and SSH identity for specified account." do |account|
        puts
        switch_credentials account
        switch_identity account
        print_info
        exit
      end

      o.on "-B", "--backup ACCOUNT", String, "Backup existing Heroku credentials and SSH identity for specified account." do |account|
        backup_credentials account
        backup_identity account
        exit
      end

      o.on "-D", "--destroy ACCOUNT", String, "Destroy Heroku credentials and SSH identity for specified account." do |account|
        destroy_credentials account
        destroy_identity account
        exit
      end

      o.on "-M", "--mode MODE", String, "Switches mode for current account." do |mode|
        switch_mode mode
        print_info
        exit
      end
      
      o.separator ''
      o.separator "Heroku Commands:"
      o.on "-p", "--pass COMMAND", "Pass command to Heroku for current app. TIP: Wrap complex commands in quotes." do |command|
        system_with_echo("heroku", command, "--app", current_app) and exit
      end

      o.on "-c", "--console", "Open remote console for current app." do
        system_with_echo("heroku console --app #{current_app}") and exit
      end

      o.on "-m", "--migrate", "Migrate remote database and restart server for current app." do
        system_with_echo("heroku rake db:migrate --app #{current_app} && heroku restart --app #{current_app}") and exit
      end

      o.on "-r", "--restart", "Restart remote server for current app." do
        system_with_echo("heroku console --app #{current_app}") and exit
      end
      
      o.separator ''
      o.separator "General Information:"
      o.on_tail "-i", "--info", "Show current Heroku credentials and SSH identity." do
        print_info and exit
      end

      o.on_tail "-l", "--list", "Show all Heroku accounts." do
        print_accounts and exit
      end

      o.on_tail "-h", "--help", "Show this help message." do
        puts parser and exit
      end

      o.on_tail("-v", "--version", "Show version.") do
        print_version and exit
      end      
    end
    
    # Parse.
    begin
      parser.parse! args
    rescue OptionParser::InvalidOption => error
      puts error.message.capitalize
    rescue OptionParser::MissingArgument => error
      puts error.message.capitalize
    end
  end
  
  # Answer current application information.
  def current_app
    !@modes.keys.empty? && @modes.has_key?(@settings[:mode]) ? @modes[@settings[:mode]][:app] : "unknown"
  end

  # Switch Heroku credentials to given account.
  # ==== Parameters
  # * +account+ - Required. The account name to switch to. Defaults to "unknown".
  def switch_credentials account = "unknown"
    account_file = File.join @heroku_home, account + '.' + @heroku_credentials
    credentials_file = File.join @heroku_home, @heroku_credentials
    puts "Switching Heroku credentials to \"#{account}\" account..."
    if valid_file? account_file
      system "rm -f #{credentials_file}"
      system "ln -s #{account_file} #{credentials_file}"
    else
      puts "ERROR: Heroku account does not exist!"
    end
  end
  
  # Backup current Heroku credentials to given account.
  # ==== Parameters
  # * +account+ - Required. The account name for the backup. Defaults to "unknown".
  def backup_credentials account = "unknown"
    puts "\nBacking up current Heroku credentials to \"#{account}\" account..."
    backup_file File.join(@heroku_home, @heroku_credentials), File.join(@heroku_home, account + '.' + @heroku_credentials)
  end
  
  # Destroy Heroku credentials for given account.
  # ==== Parameters
  # * +account+ - Required. The account to destroy. Defaults to "unknown".
  def destroy_credentials account
    puts "\nDestroying Heroku credentials for \"#{account}\" account..."
    destroy_file File.join(@heroku_home, account + '.' + @heroku_credentials)
  end

  # Switch SSH identity to given account.
  # ==== Parameters
  # * +account+ - Required. The account name to switch to. Defaults to "unknown".
  def switch_identity account = "unknown"
    old_private_file = File.join @ssh_home, @settings[:ssh_id]
    old_public_file = File.join @ssh_home, @settings[:ssh_id] + ".pub"
    new_private_file = File.join @ssh_home, account + ".identity"
    new_public_file = File.join @ssh_home, account + ".identity.pub"
    puts "Switching Heroku SSH identity to \"#{account}\" account..."
    if valid_file?(new_private_file) && valid_file?(new_public_file)
      system "rm -f #{old_private_file}"
      system "rm -f #{old_public_file}"
      system "ln -s #{new_private_file} #{old_private_file}"
      system "ln -s #{new_public_file} #{old_public_file}"
    else
      puts "ERROR: SSH identity does not exist!"
    end
  end
  
  # Backup current SSH identity to given account.
  # ==== Parameters
  # * +account+ - Required. The account name for the backup. Defaults to "unknown".
  def backup_identity account = "unknown"
    puts "\nBacking up current SSH identity to \"#{account}\" account..."
    backup_file File.join(@ssh_home, @settings[:ssh_id]), File.join(@ssh_home, account + ".identity")
    backup_file File.join(@ssh_home, @settings[:ssh_id] + ".pub"), File.join(@ssh_home, account + ".identity.pub")
  end  
  
  # Destroy SSH identity for given account.
  # ==== Parameters
  # * +account+ - Required. The account to destroy. Defaults to "unknown".
  def destroy_identity account
    puts "\nDestroying SSH identity for \"#{account}\" account..."
    destroy_file File.join(@ssh_home, account + ".identity")
    destroy_file File.join(@ssh_home, account + ".identity.pub")
  end  
  
  # Switch mode for current account.
  # ==== Parameters
  # * +mode+ - Required. The mode to switch to. Defaults to "unknown".
  def switch_mode mode = "unknown"
    begin
      settings = YAML::load_file @settings_file
      puts "\nSwitching to \"#{mode}\" mode..."
      @settings[:mode] = mode
      File.open(@settings_file, 'w') {|file| file << YAML::dump(@settings)}
    rescue
      puts "ERROR: Invalid #{@settings_file} settings file."
    end
  end

  # Print all available accounts.
  def print_accounts
    puts "\n Current Heroku accounts are:"
    Dir.glob("#{@heroku_home}/*.#{@heroku_credentials}").each do |path|
      puts " * " + File.basename(path, '.' + @heroku_credentials)
    end
    puts
  end
  
  # Print active account information.
  def print_info
    credentials_file = File.join @heroku_home, @heroku_credentials
    ssh_private_file = File.join @ssh_home, @settings[:ssh_id]
    ssh_public_file = File.join @ssh_home, @settings[:ssh_id] + ".pub"
    
    # Account
    if valid_file?(credentials_file) && valid_file?(ssh_private_file) && valid_file?(ssh_public_file)
      puts "\nCurrent Account Settings:"
      puts " - Account:             #{current_heroku_account credentials_file}" 
      puts " - Password:            #{'*' * current_heroku_password(credentials_file).size}"
      puts " - Credentials:         #{credentials_file}"
      puts " - SSH ID (private):    #{ssh_private_file}"
      puts " - SSH ID (public):     #{ssh_public_file}\n"
    else
      puts "ERROR: Heroku account credentials and/or SSH identity not found!"
    end
    
    # Project
    if File.exists? @git_config_file
      puts "\nCurrent Project Settings:"
      puts " - Mode: #{@settings[:mode]}"
      puts " - App:  #{current_app}"
      puts "\nAvailable Options:"
      if @modes.keys.empty?
        puts " - unknown"
      else
        @modes.each_key {|key| puts " - Mode: #{key}, App: #{current_app}"}
      end
    end

    puts ""
  end
  
  # Print version information.
  def print_version
    puts "Heroku Plus " + VERSION
  end

  protected
  
  # Answer the substring of the given string within a start and end delimiter range.
  # ==== Parameters
  # * +string+ - Required. The string to search.
  # * +delimiter_start+ - Required. The start delimiter.
  # * +delimiter_end+ - Required. The end delimiter.
  def grab_substring string, delimiter_start, delimiter_end
    index = string.index(delimiter_start) + 1
    length = (string.rindex(delimiter_end) || 0) - index
    string[index, length]
  end
  
  # Answer whether the file exists and print an error message when not found.
  # ==== Parameters
  # * +file+ - Required. The file to validate.
  # * +message+ - Optional. The error message to display if file not found.
  def valid_file? file, message = "Invalid file"
    File.exists?(file) ? true : ("ERROR: #{message}: #{file}." and false)
  end

  # Loads and stores the various modes as defined by the .git/config file of a project.
  # An example of modes defined in a .git/config file are as follows:
  #
  # [remote "production"]
  #   url = git@official.heroku.com:example.git
  #   fetch = +refs/heads/*:refs/remotes/heroku/*
  # [remote "stage"]
  #   url = git@official.heroku.com:example-stage.git
  #   fetch = +refs/heads/*:refs/remotes/merc-stage/*
  #
  # In the example above, the valid modes would be: production and stage. The associated apps
  # would be: example and example-stage. The resulting configuration would be: {"production" => {:app => "example"}, "stage" => {:app => "example-stage"}}
  def load_modes
    @modes = {}
    mode = nil
    if File.exists? @git_config_file
      open(@git_config_file, 'r').readlines.each do |line|
        # Look only for lines with a git repository. Example: url = git@official.heroku.com:example.git
        unless mode.nil?
          @modes[mode][:app] = grab_substring(line, ':', ".git")
          mode = nil
        end
        # Acquire the mode from lines that begin with "[remote" only.
        if line.include? "[remote "
          mode = grab_substring line, "\"", "\""
          @modes.merge! mode => {:app => nil}
        end
      end
    else
      puts "ERROR: Could not load Git configuration file for current project: #{@git_config_file}"
    end
  end

  # Executes and echos the given command line arguments.
  # ==== Parameters
  # * +args+ - Required. The command line to be executed.
  def system_with_echo *args
    command = args * ' '
    puts command
    system command
  end  

  # Answer the current Heroku account name of the given credentials file.
  # ==== Parameters
  # * +file+ - Required. The credentials file from which to read the account name from.
  def current_heroku_account file
    open(file, 'r').readlines.first.strip if valid_file?(file)
  end
  
  # Answer the current Heroku password of the given credentials file.
  # ==== Parameters
  # * +file+ - Required. The credentials file from which to read the password from.
  def current_heroku_password file
    open(file, 'r').readlines.last.strip if valid_file?(file)
  end
  
  # Backup (duplicate) existing file to new file.
  # ==== Parameters
  # * +old_file+ - Required. The file to be backed up.
  # * +new_file+ - Required. The file to backup to.
  def backup_file old_file, new_file
    if File.exists? old_file
      if File.exists? new_file
        puts "File exists: \"#{new_file}\". Do you wish to replace the existing file (y/n)?"
        if gets.strip == 'y'
          system "cp #{old_file} #{new_file}"
          puts "Replaced: #{new_file}"
        else
          puts "Backup aborted."
        end
      else
        system "cp #{old_file} #{new_file}"
        puts "Created: #{new_file}"
      end
    else
      puts "ERROR: Backup aborted! File does not exist: #{old_file}"
    end
  end
  
  # Destroy an existing file.
  # ==== Parameters
  # * +file+ - Required. The file to destroy.
  def destroy_file file
    if valid_file? file
      puts "You are about to perminently destroy the \"#{file}\" file. Do you wish to continue (y/n)?"
      if gets.strip == 'y'
        system "rm -f #{file}"
        puts "Destroyed: #{file}"
      else
        puts "Destroy aborted."
      end
    else
      puts "ERROR: Destroy aborted! File not found: #{file}"
    end
  end
end
