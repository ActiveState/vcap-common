ONE_GIG = 1024*1024*1024
SYSADM = "~/stackato/tools/sysadm"

module SA
  def SA.sys (cmd)
    #puts "=============> SA.sys #{cmd}"
    out = `#{cmd} 2>&1`
    raise out unless $?.to_i == 0
    out
  end

  def SA.add_user (uid, username, group)
    #XXX: remove when caller refactoring is done
    raise "This should never be done online. Prepopulate users (in stackato-admin?)"
    system("sudo adduser --system --shell '/bin/sh' --quiet --no-create-home " +
           "--uid #{uid} --home '/nonexistent' #{username}  > /dev/null 2>&1")
    system("sudo usermod -g #{group} #{username}  > /dev/null 2>&1")
  end

  def SA.create_group (name)
    #XXX: remove when caller refactoring is done
    raise "This should never be done online. Pre-create the group (in stackato-admin?)"
    system("sudo addgroup --system #{name} > /dev/null 2>&1")
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

    timer = nil
    terminate = nil
    terminated = false

    exec_operation = proc do |process|
      terminate = proc do
        process.close_connection_after_writing()
      end
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
      # XXX: value may not contain single quotes; see
      # http://bugs.activestate.com/show_bug.cgi?id=90720#c9
      (opts[:env] || {}).each do |k,v| 
        export_line = "export #{k}=#{v}\n"
        process.send_data(export_line)
      end
      process.send_data("#{command}\n") 
      process.send_data("exit\n") # because. (long story)
      process
    end

    exit_callback = proc do |output, status|
      EM.cancel_timer(timer) if timer
      if terminated
        output += "\n" if output.length > 0
        output += "*Terminated by timeout*\n"
      end
      block.call(output, status) if block
    end
    
    # it *must* use the three-arg form, otherwise the stderr output gets lost
    pid = EM.system("/bin/sh", "-c", "env -i #{SYSADM} runas #{user} 2>&1",
                    exec_operation, exit_callback)

    timeout = opts[:timeout] || 0
    if timeout > 0
      timer = EM.add_timer(timeout) do
        timer = nil
        terminated = true
        terminate.call
      end
    end
    pid
  end

end

