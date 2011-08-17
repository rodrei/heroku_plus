module HerokuPlus
  # Manages Heroku credentials.
  class Credentials
    CREDENTIALS = "credentials"
    
    # Initialize and configure defaults.
    # ==== Parameters
    # * +cli+ - Required. The command line interface (assumes Thor-like behavior).
    def initialize cli
      @cli = cli
      @heroku_home = File.join ENV["HOME"], ".heroku"
      @credentials_file = File.join @heroku_home, CREDENTIALS
    end

    # Answer the Heroku home path.
    def home_path
      @heroku_home
    end

    # Answer the credentials file path.
    def file_path
      @credentials_file
    end
    
    # Answer current login.
    def login
      open(@credentials_file, 'r').readlines.first.strip if @cli.valid_file?(@credentials_file)
    end

    # Answer current password.
    def password
      open(@credentials_file, 'r').readlines.last.strip if @cli.valid_file?(@credentials_file)
    end    
    
    # Switch to existing Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to switch to.
    def switch account
      account_file = File.join @heroku_home, account + '.' + CREDENTIALS
      if @cli.valid_file? account_file
        `rm -f #{@credentials_file}`
        `ln -s #{account_file} #{@credentials_file}`
        @cli.say_info "Heroku credentials switched to account: #{account}"
      else
        @cli.say_error "Heroku account does not exist!"
      end
    end

    # Backup Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to backup.
    def backup account
      @cli.backup_file @credentials_file, File.join(@heroku_home, account + '.' + CREDENTIALS)
      @cli.say_info "Heroku credentials backed up to account: #{account}."
    end

    # Destroy Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to destroy.
    def destroy account
      @cli.destroy_file File.join(@heroku_home, account + '.' +  CREDENTIALS)
    end
    
    # Print configured accounts.
    def print_accounts
      @cli.say_info "Configured Accounts:"
      Dir.glob("#{@heroku_home}/*.#{CREDENTIALS}").each {|path| @cli.say_info " - " + File.basename(path, '.' + CREDENTIALS)}
    end
  end
end
