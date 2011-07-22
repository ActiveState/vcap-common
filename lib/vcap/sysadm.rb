ONE_GIG = 1024*1024*1024
SYSADM = "~/stackato/tools/sysadm"

module SA
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

  def SA.grant_ownership (user, group)
    system("#{SYSADM} grant #{user} #{dir}")
  end

  def SA.take_ownership (dir)
    system("#{SYSADM} take #{dir}")
  end

  def SA.kill_user_procs (username)
    system("#{SYSADM} kill #{username}")
  end

  def SA.cleanup_instance_dir (dir)
    system("#{SYSADM} rminst #{dir}")
  end

  def SA.remove_tmp_dir (dir)
    system("#{SYSADM} rmtmp #{dir}")
  end

  def SA.run_as (user, command, options={}, &block)
    { :dir => nil, :env => nil, :limits => nil, :close_stdin => false}.merge! options

    exec_operation = proc do |process|
      process.send_data("cd #{options[:dir]}\n") if options[:dir]
      # we want to limit all processes potentially running user code, without exceptions
      limits = {:mem => ONE_GIG, :fds => 4096, :disk => ONE_GIG}.merge! (options[:limits] || {})
      # ulimit -m takes kb, soft enforce
      process.send_data("ulimit -m #{(limits[:mem]/1024).to_i} 2> /dev/null\n")  
      # virtual memory at 3G, this will be enforced
      process.send_data("ulimit -v 3000000 2> /dev/null\n") 
      process.send_data("ulimit -n #{limits[:fds]} 2> /dev/null\n")
      process.send_data("ulimit -u 512 2> /dev/null\n") # processes/threads
      # File size to complete disk usage
      process.send_data("ulimit -f #{limits[:disk]} 2> /dev/null\n") 
      process.send_data("umask 077\n")

      # XXX: value may not contain single quotes; see
      # http://bugs.activestate.com/show_bug.cgi?id=90720#c9
      (options[:env] || {}).each { |k,v| process.send_data("export #{k}=\"#{v}\"\n") }

      command = "#{command} < /dev/null" if options[:close_stdin]
      process.send_data("#{command}\n")
      process.send_data("exit\n")
      process
    end

    exit_callback = block || (proc do |o,s| nil end)
    
    # it *must* use the three-arg form, otherwise the stderr output gets lost
    EM.system("/bin/sh", "-c", "env -i #{SYSADM} runas #{user} 2>&1",
              exec_operation, exit_callback)
  end

end

