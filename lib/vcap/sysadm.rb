ONE_GIG = 1024*1024*1024
SYSADM = "~/stackato/tools/sysadm"

module SA
  class Error < Exception
  end
  
  def SA.sys (cmd)
    #puts "=============> SA.sys #{cmd}"
    out = `#{cmd} 2>&1`
    raise Error.new(out) unless $?.to_i == 0
    out
  end

  def SA.grant_ownership (user, dir)
    sys "#{SYSADM} grant #{user} #{dir}"
  end

  def SA.take_ownership (dir)
    sys "#{SYSADM} take #{dir}"
  end

  def SA.kill_user_procs (username)
    sys "#{SYSADM} kill #{username}"
  end

  def SA.cleanup_instance_dir (dir)
    sys "#{SYSADM} rminst #{dir}"
  end

  def SA.remove_tmp_dir (dir)
    sys "#{SYSADM} rmtmp #{dir}"
  end

  def SA.lxc (command, *args, &block)
    exec_operation = proc { |process| process }
    exit_callback = block || (proc do |o,s| nil end)
    
    #XXX: potential vulnerability: unescaped user data.
    #     it might make sense to send args through stdin
    EM.system("/bin/sh", "-c", "#{SYSADM} runlxc #{user} #{args.join(' ')} 2>&1",
              exec_operation, exit_callback)
  end

  def SA.run_as (user, command, opts={}, &block)
    opts = {:dir => nil, :env => nil, :limits => nil, :timeout => 0}.merge(opts)

    # Timeout process termination:
    # 1. We can't simply kill all user processes with kill_user_procs(user)
    #    because this will terminate the app, too. 
    # 2. Closing the /bin/sh's stdin in hope it would send SIGTERM to its 
    #    children didn't work, I think because a forked shell is not a session
    #    owner.
    # 3. Calling Process.kill(SIG*, pid) doesn't make sense because the process
    #    belongs to a different user.
    # Conclusion:
    #    This should happen from inside of the child process.

    exec_operation = proc do |process|
      # set the minimal usable PATH
      process.send_data("export PATH=/usr/bin:/bin\n")
      process.send_data("cd #{opts[:dir]}\n") if opts[:dir]
      # we want to limit all processes potentially running user code, without exceptions
      limits = {:mem => ONE_GIG, :fds => 4096, :disk => ONE_GIG}.merge(opts[:limits] || {})
      # ulimit -m takes kb, soft enforce
      process.send_data("ulimit -m #{(limits[:mem]/1024).to_i} 2> /dev/null\n")  
      # virtual memory at 3G, this will be enforced
      process.send_data("ulimit -v 3000000 2> /dev/null\n") 
      process.send_data("ulimit -n #{limits[:fds]} 2> /dev/null\n")
      process.send_data("ulimit -u 512 2> /dev/null\n") # processes/threads
      # File size to complete disk usage
      process.send_data("ulimit -f #{limits[:disk]} 2> /dev/null\n") 
      process.send_data("umask 027\n") # the group is forced to be "stackato"
      (opts[:env] || {}).each do |k,v| 
        export_line = "export #{k}=#{v}\n"
        process.send_data(export_line)
      end

      # timeout now works with the sigal mask being restored in sysadm
      timeout = opts[:timeout] || 0
      command = "timeout #{timeout} #{command}" if timeout > 0

      process.send_data("#{command}\n") 
      process.send_data("exit\n") # because. (long story)
      process
    end

    # Unfortunately, an extra shell is necessary here because there is no 
    # EM.popen3. This means stderr is merged to the caller's stderr unless
    # redirected inside the child process. Also, stderr redirection works only
    # with the three-arg form of EM.system.
    pid = EM.system("/bin/sh", "-c", "env -i #{SYSADM} runas #{user} 2>&1",
                    exec_operation, block)
    pid
  end

end

