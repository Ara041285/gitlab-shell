require 'shellwords'

require_relative 'gitlab_net'

class GitlabShell
  class DisallowedCommandError < StandardError; end

  attr_accessor :key_id, :repo_name, :git_cmd, :repos_path, :repo_name

  def initialize
    @key_id = /key-[0-9]+/.match(ARGV.join).to_s
    @origin_cmd = ENV['SSH_ORIGINAL_COMMAND']
    @config = GitlabConfig.new
    @repos_path = @config.repos_path
  end

  def exec
    if @origin_cmd
      parse_cmd

      if git_cmds.include?(@git_cmd)
        ENV['GL_ID'] = @key_id
        ENV['HOME'] ='/var/opt/gitlab'

        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        # TODO: Fix validation for git-annex-shell !!!!
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        if true #validate_access
          process_cmd
        else
          message = "gitlab-shell: Access denied for git command <#{@origin_cmd}> by #{log_username}."
          $logger.warn message
          $stderr.puts "Access denied."
        end
      else
        raise DisallowedCommandError
      end
    else
      puts "Welcome to GitLab, #{username}!"
    end
  rescue DisallowedCommandError => ex
    message = "gitlab-shell: Attempt to execute disallowed command <#{@origin_cmd}> by #{log_username}."
    $logger.warn message
    puts 'Not allowed command'
  end

  protected

  def parse_cmd
    args = Shellwords.shellwords(@origin_cmd)

    if args.first == 'git-annex-shell'
      # Dont know yet how much arguments allow
      # puts args.count
      # puts args.inspect
    else
      raise DisallowedCommandError unless args.count == 2
    end

    @git_cmd = args.first

    if @git_cmd == 'git-annex-shell'
      @repo_name = escape_path(args[2].gsub("\/~\/", '')) 
    else
      @repo_name = escape_path(args.last)
    end
  end

  def git_cmds
    %w(git-upload-pack git-receive-pack git-upload-archive git-annex-shell)
  end

  def process_cmd
    repo_full_path = File.join(repos_path, repo_name)
    $logger.info "gitlab-shell: executing git command <#{@git_cmd} #{repo_full_path}> for #{log_username}."
    
    if @git_cmd == 'git-annex-shell'
      args = Shellwords.shellwords(@origin_cmd)
      parsed_args = 
        args.map do |arg|
          if arg =~ /\A\/~\/.*\.git\Z/
            repo_full_path
          else
            arg
          end
        end

      exec_cmd(*parsed_args)
    else 
      exec_cmd(@git_cmd, repo_full_path)
    end
  end

  def validate_access
    api.check_access(@git_cmd, @repo_name, @key_id, '_any').allowed?
  end

  # This method is not covered by Rspec because it ends the current Ruby process.
  def exec_cmd(*args)
    Kernel::exec({'PATH' => ENV['PATH'], 'LD_LIBRARY_PATH' => ENV['LD_LIBRARY_PATH'], 'GL_ID' => ENV['GL_ID']}, *args, unsetenv_others: true)
  end

  def api
    GitlabNet.new
  end

  def user
    # Can't use "@user ||=" because that will keep hitting the API when @user is really nil!
    if instance_variable_defined?('@user')
      @user
    else
      @user = api.discover(@key_id)
    end
  end

  def username
    user && user['name'] || 'Anonymous'
  end

  # User identifier to be used in log messages.
  def log_username
    @config.audit_usernames ? username : "user with key #{@key_id}"
  end

  def escape_path(path)
    full_repo_path = File.join(repos_path, path)

    if File.absolute_path(full_repo_path) == full_repo_path
      path
    else
      abort "Wrong repository path"
    end
  end
end
