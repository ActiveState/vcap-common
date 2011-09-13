ONE_GIG = 1024*1024*1024
SYSADM = "~/stackato/tools/sysadm"

require "yaml"

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

  def SA.create_container (id) 
    `#{SYSADM} runlxc create_container #{id}`.strip # this returns the full directory
  end

  def SA.start_container (id)
    system("#{SYSADM} runlxc start_container #{id}")
  end

  def SA.set_mem_limit (id, mem_limit)
    system("#{SYSADM} runlxc set_mem_limit #{id} #{mem_limit}")
  end
  
  def SA.wait_for_ip (id)
    myuid = Process.euid
    `#{SYSADM} runlxc wait_for_ip #{id} #{myuid}`.strip
  end

  def SA.cleanup_containers_dir
    system("#{SYSADM} runlxc create_containers_dir")
  end

  def SA.stop_container (id)
    system("#{SYSADM} runlxc stop_container #{id}")
  end

  def SA.destroy_container (id)
    exec_operation = proc { |process| process }
    exit_callback = proc do |o,s| nil end

    EM.system("/bin/sh", "-c", "#{SYSADM} runlxc destroy_container #{id} 2>&1",
              exec_operation, exit_callback)
  end
 
  def SA.untar (tgz_file, untar_to)
    system("#{SYSADM} runlxc untar_file #{tgz_file} #{untar_to}")
  end

  def SA.runlxc (instance_id, user, dir, cmd, env, &block)
    # HACK: Pass environment data to the `lxctrl` process.
    # FIXME: find a better way to do this.
    File.open( "/tmp/#{instance_id}.env", "w" ) { |file| YAML.dump( env, file ) } 

    exec_operation = proc { |process| process }
    exit_callback = block || (proc do |o,s| nil end)

    EM.system("/bin/sh", "-c", "#{SYSADM} runlxc runlxc #{instance_id} #{user[:user]} #{user[:uid]} #{dir} \"#{cmd}\" 2>&1",
              exec_operation, exit_callback)
  end

  def SA.install_forwarding (port, lxcip, lxcport)
    system("#{SYSADM} runlxc install_forwarding #{port} #{lxcip} #{lxcport}")
  end

  def SA.remove_forwarding (port, lxcip, lxcport)
    system("#{SYSADM} runlxc remove_forwarding #{port} #{lxcip} #{lxcport}")
  end

  # Run a command on host with imposed ulimits.
  # This is currently only used for running staging process.
  # TODO: remove this function once we move staging to LXC.
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

    if not "\"'".include? command[0]  # wrap in quotes if necessary
      command = command.sub("'", "\\\\'")  # escape single quotes
      command = "'#{command}'"
    end
    command = "sh -c #{command}"  # run with `sh -c ...` to allow pipes, quotes, etc..

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

