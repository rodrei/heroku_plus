require "yaml"
require "thor"
require "thor/actions"
require "heroku"
require "pgbackups/client"

module HerokuPlus
  class CLI < Thor
    include Thor::Actions
    include HerokuPlus::Utilities

    # Initialize.
    def initialize args = [], options = {}, config = {}
      super
      
      # Defaults.
      @heroku_credentials = Credentials.new self
      @settings_file = File.join @heroku_credentials.home_path, "heroku_plus.yml"
      @git_config_file = ".git/config"

      # Load and apply custom settings (if any).
      load_settings

      # Load modes and ensure current mode is set.
      load_modes
    end

    desc "-a, [account]", "Manage accounts."
    map "-a" => :account
    method_option :switch, :aliases => "-s", :desc => "Switch to existing account.", :type => :string, :default => nil
    method_option :backup, :aliases => "-b", :desc => "Backup existing account to new account.", :type => :string, :default => nil
    method_option :destroy, :aliases => "-d", :desc => "Delete existing account.", :type => :string, :default => nil
    method_option :list, :aliases => "-l", :desc => "Show all configured accounts.", :type => :boolean, :default => false
    method_option :info, :aliases => "-i", :desc => "Show current credentials and SSH identity.", :type => :boolean, :default => false
    method_option :files, :aliases => "-f", :desc => "Show current account files.", :type => :boolean, :default => false
    def account
      say
      case
      when options[:switch] then switch(options[:switch])
      when options[:backup] then backup(options[:backup])
      when options[:destroy] then destroy(options[:destroy])
      when options[:list] then @heroku_credentials.print_accounts
      when options[:info] then print_account_info
      when options[:files] then print_account_files
      else print_account_info
      end
      say
    end
    
    desc "-p, [pass=COMMAND]", "Pass command to Heroku for current app/mode."
    map "-p" => :pass
    def pass command
      run "heroku #{command} --app #{application}"
    end

    desc "-c, [console]", "Open remote console."
    map "-c" => :console
    def console
      run "heroku console --app #{application}"
    end

    desc "-m, [mode]", "Manage development modes."
    map "-m" => :mode
    method_option :switch, :aliases => "-s", :desc => "Switch development mode.", :type => :string, :lazy_default => "stage"
    method_option :list, :aliases => "-l", :desc => "Show development modes.", :type => :boolean, :default => false
    def mode mode = nil
      say
      case
      when options[:switch] then switch_mode(options[:switch])
      when options[:list] then print_modes
      else print_modes
      end
      say
    end

    desc "-r, [restart]", "Restart remote server."
    map "-r" => :restart
    def restart
      run "heroku restart --app #{application}"
    end

    desc "db", "Manage PostgreSQL database."
    method_option :migrate, :aliases => "-m", :desc => "Migrate remote PostgreSQL database (for current mode) and restart server.", :type => :boolean, :default => false
    method_option :backup, :aliases => "-b", :desc => "Backup remote PostgreSQL database (for current mode).", :type => :boolean, :default => false
    method_option :import, :aliases => "-i", :desc => "Import latest remote PostgreSQL database (for current mode) into local database.", :type => :string, :lazy_default => "development"
    method_option :import_full, :aliases => "-I", :desc => "Import remote PostgreSQL database (for current mode) into local database by destroying local datbase, backing up and importing remote database, and running local migrations.", :type => :string, :lazy_default => "development"
    method_option :reset, :aliases => "-R", :desc => "Reset and destroy all data in remote PostgreSQL database (for current mode).", :type => :string, :lazy_default => "SHARED_DATABASE_URL"
    def db
      say
      case
      when options[:migrate] then
        run "heroku rake db:migrate --app #{application} && heroku restart --app #{application}"
      when options[:backup] then backup_remote_database
      when options[:import] then import_remote_database(options[:import])
      when options[:import_full] then import_remote_database(options[:import_full], :type => "full")
      when options[:reset] then reset_remote_database(options[:reset])
      else say("Type 'hp help db' for usage.")
      end
      say
    end

    desc "-e, [edit]", "Edit settings in default editor (as set via the $EDITOR environment variable)."
    map "-e" => :edit
    def edit
      `$EDITOR #{@settings_file}`
    end

    desc "-v, [version]", "Show version."
    map "-v" => :version
    def version
      say "Heroku Plus " + VERSION
    end
    
    desc "-h, [help]", "Show this message."
    def help task = nil
      say and super
    end

    protected
    
    # Load settings.
    def load_settings
      # Defaults.
      @settings = {
        :ssh_id => "id_rsa",
        :mode => "stage",
        :skip_switch_warnings => false,
        :pg_restore_options => "-O -w"
      }
      @ssh_identity = Identity.new self, @settings[:ssh_id]
      # Load settings file - Trumps defaults.
      if File.exists? @settings_file
        begin
          settings = YAML::load_file @settings_file
          @settings.merge! settings.reject {|key, value| value.nil?}
        rescue
          say_error "Invalid settings: #{@settings_file}."
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
        say_error "Could not load Git configuration file for current project: #{@git_config_file}"
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
      answer = true
      if @settings[:skip_switch_warnings].to_s == "false"
        say_info "Switching to account \"#{account}\" will destroy the following files:"
        say_info " #{@heroku_credentials.file_path}"
        say_info " #{@ssh_identity.public_file}"
        say_info " #{@ssh_identity.private_file}"
        say_info "You can suppress this warning message by setting skip_switch_warnings = true in your settings file: #{@settings_file}"
        say
        answer = shell.yes? "Do you wish to continue (y/n)?"
        say
      end
      if answer
        @heroku_credentials.switch account
        @ssh_identity.switch account
        say
        print_account_info
      else
        say_info "Switch canceled."
      end
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
      say_info "Destroying Heroku credentials and SSH identities..."
      @heroku_credentials.destroy account
      @ssh_identity.destroy account
    end

    # Switch mode for current account.
    # ==== Parameters
    # * +mode+ - Required. The mode to switch to. Defaults to "stage".
    def switch_mode mode = "stage"
      begin
        settings = YAML::load_file @settings_file
        @settings[:mode] = mode
        save_settings @settings
        say_info "Switched mode to: #{mode}."
        say
        print_account_info
      rescue
        say_error "Invalid #{@settings_file} settings file."
      end
    end

    # Backs up remote datbase.
    def backup_remote_database
      run "heroku pgbackups:capture --expire --app #{application}"
      run "heroku pgbackups --app #{application}"
    end

    # Import latest data from remote database into local database.
    # ==== Parameters
    # * +env+ - Optional. The local environemnt to be used when importing remote data. Defaults to "development".
    # ==== Options
    # * +type+ - Optional. The type of database import. Defaults to "simple".
    # * +skip_warnings+ - Optional. Skips warning messages and prompts. Defaults to false.
    def import_remote_database env = "development", options = {:type => "simple"}
      warning_message = "You are about to perminently override all data in the local \"#{env}\" database. Do you wish to continue (y/n)?"
      case options[:type]
      # Simple remote database import.
      when "simple" then
        db_settings = database_settings
        if db_settings.empty?
          say_error "Unable to load database setings for current app. Are you within the root folder of a Rails project?"
        else
          if options[:skip_warnings] || shell.yes?(warning_message)
            begin
              heroku = Heroku::Client.new @heroku_credentials.login, @heroku_credentials.password
              pg = PGBackups::Client.new heroku.config_vars(application)["PGBACKUPS_URL"]
              database = "latest.dump"
              run "curl -o #{database} '#{pg.get_latest_backup["public_url"]}'"
              # Default PostgreSQL restore settings.
              # -O = Don't restore original data ownership.
              # -w = Don't prompt for a password.
              # -h = The server host name (via the "host" database.yml setting for current mode).
              # -U = The user name to connect as (via the "username" database.yml setting for current mode).
              # -d = The database name (via the "database" database.yml setting for current mode).
              run "pg_restore #{@settings[:pg_restore_options]} -h #{db_settings[env]['host']} -U #{db_settings[env]['username']} -d #{db_settings[env]['database']} #{database}"
              run "rm -f #{database}"
            rescue URI::InvalidURIError
              say_error "Invalid database URI. Does the backup exist?"
            end
          else
            say_info "Import aborted."
          end
        end
      # Full remote database import.
      when "full" then
        if options[:skip_warnings] || shell.yes?(warning_message)
          run "rake db:drop"
          run "rake db:create"
          backup_remote_database
          import_remote_database env, :type => "simple", :skip_warnings => true
          run "rake db:migrate"
        else
          say_info "Import aborted."
        end
      else
        say_error "Unable to determine import type."
      end
    end
    
    # Resets remote datbase.
    def reset_remote_database database
      run "heroku pg:reset #{database} --app #{application}"
    end

    # Print current account information.
    def print_account_info
      # Account
      if valid_file?(@heroku_credentials.file_path)
        say_info "Current Account Settings:"
        say_info " - Login:    #{@heroku_credentials.login}" 
        say_info " - Password: #{'*' * @heroku_credentials.password.size}"
      else
        say_error "Heroku account credentials and/or SSH identity not found!"
      end

      # Project
      if File.exists? @git_config_file
        say_info "Current Project Settings:"
        say_info " - Mode: #{@settings[:mode]}"
        say_info " - App:  #{application}"
      end
    end

    # Print associated files for current account.
    def print_account_files
      if valid_file?(@heroku_credentials.file_path) && valid_file?(@ssh_identity.public_file) && valid_file?(@ssh_identity.private_file)
        say_info "Current Account Files:"
        say_info " - Credentials:      #{@heroku_credentials.file_path}"
        say_info " - SSH ID (private): #{@ssh_identity.private_file}\n"
        say_info " - SSH ID (public):  #{@ssh_identity.public_file}"
      else
        say_error "Heroku account credentials not found!"
      end
    end

    # Print available modes.
    def print_modes
      say_info "Current Mode:"
      say_info " - #{@settings[:mode]}"
      
      if File.exists? @git_config_file
        say_info "Available Modes:"
        if @modes.keys.empty?
          say_info " - unknown"
        else
          @modes.each_key {|key| say_info " - #{key} (#{@modes[key][:app]})"}
        end
      end
    end

    # Answer database settings for current application.
    def database_settings
      database_settings_file = "config/database.yml"
      valid_file?(database_settings_file) ? YAML::load_file(database_settings_file) : {}
    end
    
    # Answer whether the argument is valid or not.
    # ==== Parameters
    # * +name+ - Required. The argument name.
    # * +type+ - Required. The argument type.
    def valid_argument? name, type
      if name.nil? || name.empty? || name == type
        say_error("Invalid/missing argument.") and false
      else
        true
      end
    end
  end
end
