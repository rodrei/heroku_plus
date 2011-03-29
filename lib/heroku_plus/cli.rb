require "yaml"
require "thor"
require "heroku"
require "pgbackups/client"

module HerokuPlus
  class CLI < Thor
    include HerokuPlus::Utilties

    # Initialize.
    def initialize args = [], options = {}, config = {}
      super
      
      # Defaults.
      @shell = shell
      @heroku_credentials = Credentials.new shell
      @settings_file = File.join @heroku_credentials.home_path, "heroku_plus.yml"
      @git_config_file = ".git/config"

      # Load and apply custom settings (if any).
      load_settings
      @ssh_identity = Identity.new shell, @settings[:ssh_id]

      # Load modes and ensure current mode is set.
      load_modes
    end

    desc "account", "Manage accounts."
    map "-a" => :account
    method_option "switch", :aliases => "-s", :desc => "Switch to existing account.", :type => :string, :default => nil
    method_option "backup", :aliases => "-b", :desc => "Backup existing account to new account", :type => :string, :default => nil
    method_option "destroy", :aliases => "-d", :desc => "Delete existing account", :type => :string, :default => nil
    method_option "list", :aliases => "-l", :desc => "Show all configured accounts", :type => :boolean, :default => false
    method_option "info", :aliases => "-i", :desc => "Show current credentials and SSH identity", :type => :boolean, :default => false
    def account
      shell.say
      case
      when options[:switch] then switch(options[:switch])
      when options[:backup] then backup(options[:backup])
      when options[:destroy] then destroy(options[:destroy])
      when options[:list] then @heroku_credentials.print_accounts
      when options[:info] then print_account
      else print_account
      end
      shell.say
    end
    
    desc "pass COMMAND", "Pass command to Heroku."
    map "-p" => :pass
    def pass command
      shell_with_echo "heroku", command, "--app", application
    end

    desc "console", "Open remote console."
    map "-c" => :console
    def console
      shell_with_echo "heroku console --app #{application}"
    end

    desc "mode", "Manage modes."
    map "-m" => :mode
    method_option "switch", :aliases => "-s", :desc => "Switch mode.", :type => :string, :default => nil
    method_option "list", :aliases => "-l", :desc => "Show modes.", :type => :boolean, :default => false
    def mode
      shell.say
      case
      when options[:switch] then switch_mode(options[:switch])
      when options[:list] then print_modes
      else print_modes
      end
      shell.say
    end

    desc "restart", "Restart remote server."
    map "-r" => :restart
    def restart
      shell_with_echo "heroku restart --app #{application}"
    end

    desc "db", "Manage PostgreSQL database."
    method_option "migrate", :aliases => "-m", :desc => "Migrate remote PostgreSQL database and restart server.", :type => :boolean, :default => false
    method_option "backup", :aliases => "-b", :desc => "Backup remote PostgreSQL database.", :type => :boolean, :default => false
    method_option "import", :aliases => "-i", :desc => "Import latest remote PostgreSQL database into local database.", :type => :string, :default => "development"
    def db
      shell.say
      case
      when options[:migrate] then
        shell_with_echo "heroku rake db:migrate --app #{application} && heroku restart --app #{application}"
      when options[:backup] then
        shell_with_echo "heroku pgbackups:capture --expire --app #{application}"
        shell_with_echo "heroku pgbackups --app #{application}"
      when options[:import] then import_remote_database(options[:import])
      else shell.say("Type 'hp help db' for usage.")
      end
      shell.say
    end

    desc "version", "Show version."
    map "-v" => :version
    def version
      shell.say "Heroku Plus " + VERSION
    end
    
    desc "help", "Show this message."
    def help task = nil
      shell.say and super
    end

    protected
    
    # Load settings.
    def load_settings
      if File.exists? @settings_file
        begin
          settings = YAML::load_file @settings_file
          @settings = {:ssh_id => "id_rsa", :mode => "stage"}
          @settings.merge! settings.reject {|key, value| value.nil?}
        rescue
          shell.say "ERROR: Invalid settings: #{@settings_file}."
        end
      end
    end
    
    # Save settings.
    # ==== Parameters
    # * +settings+ - Required. Saves settings to file.
    def save_settings settings
      File.open(@settings_file, 'w') {|file| file << YAML::dump(settings)}
    end

    # Load and store the various modes as defined by the .git/config file of a project.
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
        shell.say "ERROR: Could not load Git configuration file for current project: #{@git_config_file}"
      end
    end

    # Answer current application information.
    def application
      !@modes.keys.empty? && @modes.has_key?(@settings[:mode]) ? @modes[@settings[:mode]][:app] : "unknown"
    end
    
    # Switch Heroku credentials and SSH identity to existing account.
    # ==== Parameters
    # * +account+ - Required. The account to switch to.
    def switch account
      return unless valid_argument?(account, "switch")
      @heroku_credentials.switch account
      @ssh_identity.switch account
    end

    # Backup Heroku credentials and SSH identity for existing account.
    # ==== Parameters
    # * +account+ - Required. The account to backup.
    def backup account
      return unless valid_argument?(account, "backup")
      @heroku_credentials.backup account
      @ssh_identity.backup account
    end

    # Destroy Heroku credentials and SSH identity for existing account.
    # ==== Parameters
    # * +account+ - Required. The account to destroy.
    def destroy account
      return unless valid_argument?(account, "destroy")
      shell.say "Destroying Heroku credentials and SSH identities..."
      @heroku_credentials.destroy account
      @ssh_identity.destroy account
    end

    # Switch mode for current account.
    # ==== Parameters
    # * +mode+ - Required. The mode to switch to. Defaults to "unknown".
    def switch_mode mode = "unknown"
      begin
        settings = YAML::load_file @settings_file
        @settings[:mode] = mode
        save_settings @settings
        shell.say "Switched mode to: #{mode}."
      rescue
        shell.say "ERROR: Invalid #{@settings_file} settings file."
      end
    end

    # Import latest data from remote database into local database.
    # ==== Parameters
    # * +env+ - Optional. The Rails environemnt to be used when importing remote data. Defaults to "development".
    def import_remote_database env = "development"
      settings = database_settings
      if database_settings.empty?
        shell.say "ERROR: Unable to load database setings for current app. Are you within the root folder of your Rails project?"
      else
        answer = shell.yes? "You are about to perminently override all data in the local \"#{env}\" database. Do you wish to continue (y/n)?"
        if answer
          heroku = Heroku::Client.new @heroku_credentials.login, @heroku_credentials.password
          pg = PGBackups::Client.new heroku.config_vars(application)["PGBACKUPS_URL"]
          database = "latest.dump"
          shell_with_echo "curl -o #{database} '#{pg.get_latest_backup["public_url"]}'"
          shell_with_echo "pg_restore --verbose --clean --no-acl --no-owner -h #{settings[env]['host']} -U #{settings[env]['username']} -d #{settings[env]['database']} #{database}"
          shell_with_echo "rm -f #{database}"
        else
          shell.say "Import aborted."
        end
      end
    end

    # Print active account information.
    def print_account
      # Account
      if valid_file?(@heroku_credentials.file_path) && valid_file?(@ssh_identity.public_file) && valid_file?(@ssh_identity.private_file)
        shell.say "Current Account Settings:"
        shell.say " - Login:            #{@heroku_credentials.login}" 
        shell.say " - Password:         #{'*' * @heroku_credentials.password.size}"
        shell.say " - Credentials:      #{@heroku_credentials.file_path}"
        shell.say " - SSH ID (private): #{@ssh_identity.private_file}\n"
        shell.say " - SSH ID (public):  #{@ssh_identity.public_file}"
      else
        shell.say "ERROR: Heroku account credentials and/or SSH identity not found!"
      end

      # Project
      if File.exists? @git_config_file
        shell.say "\nCurrent Project Settings:"
        shell.say " - Mode: #{@settings[:mode]}"
        shell.say " - App:  #{application}"
      end
    end

    def print_modes
      # Project
      if File.exists? @git_config_file
        shell.say "Available Modes:"
        if @modes.keys.empty?
          shell.say " - unknown"
        else
          @modes.each_key {|key| shell.say " - Mode: #{key}, App: #{@modes[key][:app]}"}
        end
      end
    end

    # Print version information.
    def print_version
      shell.say "Heroku Plus " + VERSION
    end

    # Answer database settings for current application.
    def database_settings
      database_settings_file = "config/database.yml"
      valid_file?(database_settings_file) ? YAML::load_file(database_settings_file) : {}
    end
    
    # Answer whether argument is valid or not.
    # ==== Parameters
    # * +name+ - Required. The argument name.
    # * +type+ - Required. The argument type.
    def valid_argument? name, type
      if name.nil? || name.empty? || name == type
        shell.say("ERROR: Argument must be supplied.") and false
      else
        true
      end
    end    
  end
end
