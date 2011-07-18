ONE_GIG = 1024*1024*1024

module SA
  def SA.add_user (uid, username, group)
    #XXX: This should never be done online. Prepopulate users (in stackato-admin?)
    system("sudo adduser --system --shell '/bin/sh' --quiet --no-create-home " +
           "--uid #{uid} --home '/nonexistent' #{username}  > /dev/null 2>&1")
    system("sudo usermod -g #{group} #{username}  > /dev/null 2>&1")
  end

  def SA.create_group (name)
    #XXX: This should never be done online. Pre-create the group (in stackato-admin?)
    system("sudo addgroup --system #{name} > /dev/null 2>&1")
  end

  def SA.grant_ownership (user, group, dir)
    #XXX: group name should be constant
    system("sudo chown -R #{user}:#{group} #{dir}")
    system("sudo chmod -R go-rwx #{dir}")
  end

  def SA.take_ownership (dir)
    #XXX: group name should be constant
    system("sudo chown -R #{Process.uid}:#{Process.gid} #{dir}")
  end

  def SA.kill_user_procs (uid)
    #XXX: this is brutal
    system("sudo pkill -9 -U #{uid} > /dev/null 2>&1")
  end

  def SA.cleanup_instance_dir (dir)
    #XXX: insecure, check if it's an instance dir
    EM.system("sudo rm -rf #{dir}")
  end

  def SA.remove_tmp_dir (dir)
    #XXX: insecure, check if this is a staging temp dir
    EM.system("sudo rm -rf #{dir}")
  end

  def SA.run_as (user, command, args={})
    #XXX: find a way to limit users
    { :dir => nil, :env => nil, :limits => nil,
      :limits => nil, :completed => nil}.merge! args
    exec_operation = proc do |process|
      process.send_data("cd #{args[:dir]}\n") if args[:dir]
      process.send_data("echo whoami=$(whoami)\n")
      process.send_data("echo pwd=$(pwd)\n")
      process.send_data("echo 'ls -l' && ls -l\n")
      if args[:limits]
        # we want to limit all processes potentially running user code, without exceptions
        limits = {:mem => ONE_GIG, :fds => 4096, :disk => ONE_GIG}.merge! args[:limits]
        process.send_data("ulimit -m #{(limits[:mem]/1024).to_i} 2> /dev/null\n")  # ulimit -m takes kb, soft enforce
        process.send_data("ulimit -v 3000000 2> /dev/null\n") # virtual memory at 3G, this will be enforced
        process.send_data("ulimit -n #{limits[:fds]} 2> /dev/null\n")
        process.send_data("ulimit -u 512 2> /dev/null\n") # processes/threads
        process.send_data("ulimit -f #{limits[:disk]} 2> /dev/null\n") # File size to complete disk usage
        process.send_data("umask 077\n")
      end
      if args[:env]
        args[:env].each { |env| process.send_data("export #{env}\n") }
      end
      process.send_data(command + " 2>&1\n")
      process.send_data("exit\n")
    end

    exit_callback = args[:completed] || proc do |_,_| nil end

    # it *must* use the three-arg form, otherwise the stderr output gets lost
    return EM.system("/bin/sh", "-c", "sudo env -i su -s /bin/sh #{user} 2>&1",
                     exec_operation, exit_callback)
  end

end
