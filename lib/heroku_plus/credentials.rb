module HerokuPlus
  # Manages Heroku credentials.
  class Credentials
    include HerokuPlus::Utilties
    
    CREDENTIALS = "credentials"
    
    # Initialize and configure defaults.
    # ==== Parameters
    # * +shell+ - Required. The Thor shell.
    def initialize shell
      @shell = shell
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
    
    # Answer the current login.
    def login
      open(@credentials_file, 'r').readlines.first.strip if valid_file?(@credentials_file)
    end

    # Answer the current password.
    def password
      open(@credentials_file, 'r').readlines.last.strip if valid_file?(@credentials_file)
    end    
    
    # Switch to existing Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to switch to. Defaults to "unknown".
    def switch account = "unknown"
      account_file = File.join @heroku_home, account + '.' + CREDENTIALS
      if valid_file? account_file
        system "rm -f #{@credentials_file}"
        system "ln -s #{account_file} #{@credentials_file}"
        @shell.say "Heroku credentials switched to account: #{account}."
      else
        @shell.say "ERROR: Heroku account does not exist!"
      end
    end

    # Backup Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to backup. Defaults to "unknown".
    def backup account = "unknown"
      backup_file @credentials_file, File.join(@heroku_home, account + '.' + CREDENTIALS)
      @shell.say "Heroku credentials backed up to account: #{account}."
    end

    # Destroy Heroku account.
    # ==== Parameters
    # * +account+ - Required. The account to destroy. Defaults to "unknown".
    def destroy account
      destroy_file File.join(@heroku_home, account + '.' +  CREDENTIALS)
    end
    
    # Print configured accounts.
    def print_accounts
      @shell.say "Configured Accounts:"
      Dir.glob("#{@heroku_home}/*.#{CREDENTIALS}").each {|path| @shell.say " - " + File.basename(path, '.' + CREDENTIALS)}
    end
  end
end
