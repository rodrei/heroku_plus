module HerokuPlus
  module Utilties
    # Executes and echos the given command line arguments.
    # ==== Parameters
    # * +args+ - Required. The command line to be executed.
    def system_with_echo *args
      command = args * ' '
      puts command
      system command
    end

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
end
