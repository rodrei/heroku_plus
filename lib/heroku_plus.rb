require "optparse"
require "yaml"

class HerokuPlus
  VERSION = "1.3.0"
  
  # Execute.
  def self.run args = ARGV
    hp = HerokuPlus.new
    hp.parse_args args
  end

  def initialize
    # Set defaults.
    @heroku_home = File.join ENV["HOME"], ".heroku"
    @heroku_credentials = "credentials"
    @ssh_home = File.join ENV["HOME"], ".ssh"
    @ssh_id = "id_rsa"
    @git_config_file = ".git/config"
    @settings_file = File.join @heroku_home, "heroku_plus.yml"
    @current_mode = :stage

    # Override defaults with custom settings (if found).
    if File.exists? @settings_file
      settings_file = YAML::load_file @settings_file
      @ssh_id = settings_file[:ssh_id] unless settings_file[:ssh_id].nil?
      @current_mode = settings_file[:current_mode].to_sym unless settings_file[:current_mode].nil?
    end
    
    # Load modes and ensure current mode is set.
    load_modes
  end

  # Read and parse the supplied command line arguments.
  def parse_args args = ARGV
    # Defaults.
    args = ["-h"] if args.empty?

    # Configure.
    parser = OptionParser.new do |o|
      o.banner = "Usage: hp [options]"

      o.on_tail "-s", "--switch ACCOUNT", String, "Switch Heroku credentials and SSH identity to specified account." do |account|
        puts
        switch_credentials account
        switch_identity account
        print_info
        exit
      end

      o.on_tail "-b", "--backup ACCOUNT", String, "Backup existing Heroku credentials and SSH identity to specified account." do |account|
        backup_credentials account
        backup_identity account
        exit
      end

      o.on_tail "-d", "--destroy ACCOUNT", String, "Destroy Heroku credentials and SSH identity for specified account." do |account|
        destroy_credentials account
        destroy_identity account
        exit
      end

      o.on_tail "-p", "--pass COMMAND", "Pass command to Heroku with current app info." do |command|
        verbose_system "heroku", command, "--app", current_app
        exit
      end

      o.on_tail "-m", "--migrate", "Migrate remote database and restart Heroku server with current app info." do |command|
        verbose_system "heroku rake db:migrate --app #{current_app} && heroku restart --app #{current_app}"
        exit
      end

      o.on_tail "-l", "--list", "Show all Heroku accounts." do
        print_accounts and exit
      end

      o.on_tail "-i", "--info", "Show the current Heroku credentials and SSH identity." do
        print_info and exit
      end

      o.on_tail "-h", "--help", "Show this help message." do
        puts parser and exit
      end

      o.on_tail("-v", "--version", "Show the current version.") do
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
  
  def current_app
    !@modes.keys.empty? && @modes.has_key?(@current_mode) ? @modes[@current_mode][:app] : "unknown"
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
  
  # Backup current SSH identity to given account.
  # ==== Parameters
  # * +account+ - Required. The account name for the backup. Defaults to "unknown".
  def backup_identity account = "unknown"
    puts "\nBacking up current SSH identity to \"#{account}\" account..."
    backup_file File.join(@ssh_home, @ssh_id), File.join(@ssh_home, account + ".identity")
    backup_file File.join(@ssh_home, @ssh_id + ".pub"), File.join(@ssh_home, account + ".identity.pub")
  end  
  
  # Destroy SSH identity for given account.
  # ==== Parameters
  # * +account+ - Required. The account to destroy. Defaults to "unknown".
  def destroy_identity account
    puts "\nDestroying SSH identity for \"#{account}\" account..."
    destroy_file File.join(@ssh_home, account + ".identity")
    destroy_file File.join(@ssh_home, account + ".identity.pub")
  end  
  
  # Switch SSH identity to given account.
  # ==== Parameters
  # * +account+ - Required. The account name to switch to. Defaults to "unknown".
  def switch_identity account = "unknown"
    old_private_file = File.join @ssh_home, @ssh_id
    old_public_file = File.join @ssh_home, @ssh_id + ".pub"
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
    ssh_private_file = File.join @ssh_home, @ssh_id
    ssh_public_file = File.join @ssh_home, @ssh_id + ".pub"
    
    # Account
    if valid_file?(credentials_file) && valid_file?(ssh_private_file) && valid_file?(ssh_public_file)
      puts "\nCurrent account settings:"
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
      puts "\nCurrent project settings:"
      puts " - Mode: #{@current_mode}"
      puts " - App:  #{current_app}"
      if @modes.keys.empty?
        puts " - unknown"
      else
        puts " - Available Options:"
        @modes.each_key do |key|
          puts "    - Mode: #{key}, App: #{current_app}"
        end
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
  
  def load_modes
    @modes = {}
    mode = nil
    if File.exists? @git_config_file
      open(@git_config_file, 'r').readlines.each do |line|
        unless mode.nil?
          @modes[mode][:app] = grab_substring(line, ':', ".git")
          mode = nil
        end
        if line.include? "[remote "
          mode = grab_substring(line, "\"", "\"").to_sym
          @modes.merge! mode => {:app => nil}
        end
      end
      @current_mode = @modes.keys.first if !@modes.keys.empty? && !@modes.has_key?(@current_mode)
    else
      puts "ERROR: Could not load Git configuration file for current project: #{@git_config_file}"
    end
  end
  
  def verbose_system *args
    puts args.join(' ')
    system *args
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
