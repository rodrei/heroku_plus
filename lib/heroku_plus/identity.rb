module HerokuPlus
  # Manages SSH identities.
  class Identity
    include HerokuPlus::Utilties
    
    IDENTITY = "identity"

    # Initialize and configure defaults.
    # ==== Parameters
    # * +shell+ - Required. The Thor shell.
    # * +id+ - Optional. The SSH ID. Defaults to "id_rsa".
    def initialize shell, id = "id_rsa"
      @shell = shell
      @ssh_home = File.join ENV["HOME"], ".ssh"
      @ssh_id = id
    end
    
    # Answer the SSH home path.
    def home_path
      @ssh_home
    end

    # Answer the public SSH identity file.
    def public_file
      File.join @ssh_home, @ssh_id + ".pub"
    end
    
    # Answer the private SSH identity file.
    def private_file
      File.join @ssh_home, @ssh_id
    end

    # Switch to existing SSH identity account.
    # ==== Parameters
    # * +account+ - Required. The account to switch to.
    def switch account
      old_private_file = File.join @ssh_home, @ssh_id
      old_public_file = File.join @ssh_home, @ssh_id + ".pub"
      new_private_file = File.join @ssh_home, account + ".identity"
      new_public_file = File.join @ssh_home, account + ".identity.pub"
      if valid_file?(new_private_file) && valid_file?(new_public_file)
        system "rm -f #{old_private_file}"
        system "rm -f #{old_public_file}"
        system "ln -s #{new_private_file} #{old_private_file}"
        system "ln -s #{new_public_file} #{old_public_file}"
        @shell.say "SSH identity switched to account: #{account}."
      else
        @shell.say "ERROR: SSH identity does not exist!"
      end
    end

    # Backup SSH identity.
    # ==== Parameters
    # * +account+ - Required. The account to backup.
    def backup account
      backup_file File.join(@ssh_home, @ssh_id), File.join(@ssh_home, account + ".identity")
      backup_file File.join(@ssh_home, @ssh_id + ".pub"), File.join(@ssh_home, account + ".identity.pub")
      @shell.say "SSH identity backed up to account: #{account}."
    end  

    # Destroy SSH identity.
    # ==== Parameters
    # * +account+ - Required. The account to destroy.
    def destroy account
      destroy_file File.join(@ssh_home, account + ".identity")
      destroy_file File.join(@ssh_home, account + ".identity.pub")
    end
  end
end