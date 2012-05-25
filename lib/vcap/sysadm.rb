ONE_GIG = 1024*1024*1024
SYSADM = "/home/stackato/stackato/tools/sysadm"

require "yaml"
require "json"
require "tempfile"

module SA
  class Error < Exception
  end
  
  def SA.sys (cmd)
    #puts "=============> SA.sys #{cmd}"
    out = `#{cmd} 2>&1`
    raise Error.new(out) unless $?.to_i == 0
    out
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

  def SA.get_pid(id)
    `#{SYSADM} runlxc get_pid #{id}`.strip
  end

  def SA.ensure_accessible(id, timeout)
    `#{SYSADM} runlxc ensure_accessible #{id} #{timeout} 2>&1`
    return $? == 0 ? true : false
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

  def SA.run_chroot(id, cmd)
    cmd.gsub!('"', '\"')

    out = `#{SYSADM} runlxc run_chroot #{id} #{cmd}`.strip

    return $?, out
  end

  def SA.runlxc (instance_id, dir, cmd, env, &block)
    # HACK: Pass environment data to the `lxctrl` process.
    # FIXME: find a better way to do this.
    File.open( "/tmp/#{instance_id}.env", "w" ) { |file| YAML.dump( env, file ) } 

    exec_operation = proc { |process| process }
    exit_callback = block || (proc do |o,s| nil end)

    # escape all quotes
    cmd.gsub!('"', '\"')

    EM.system("/bin/sh", "-c", "#{SYSADM} runlxc runlxc #{instance_id} #{dir} #{cmd} 2>&1",
              exec_operation, exit_callback)
  end

  def SA.install_forwarding (port, lxcip, lxcport)
    system("#{SYSADM} runlxc install_forwarding #{port} #{lxcip} #{lxcport} &")
  end

  def SA.remove_forwarding (port, lxcip, lxcport)
    system("#{SYSADM} runlxc remove_forwarding #{port} #{lxcip} #{lxcport}")
  end

  def SA.convert_full_path_to_relative(path)
    matched = /\/lxc\/containers\/stackato-.*?\/rootfs(\/.*)/.match(path)
    matched[1]
  end

  def SA.convert_relative_path_to_full(containerid, path)
    "/lxc/containers/stackato-#{containerid}/rootfs#{path}"
  end

  def SA.create_staging_dir(path)
    myuid = Process.euid
    system("#{SYSADM} runlxc create_staging_dir #{myuid} #{path}")
  end

  def SA.install_token(containerid, token, cctarget)
    system("#{SYSADM} runlxc install_token #{containerid} #{token} #{cctarget}")
  end

  def SA.create_filesystem_instance(limit)
    begin
      return JSON.parse( `#{SYSADM} runlxc create_filesystem_instance #{limit}`.strip )
    rescue
      return nil
    end
  end

  def SA.cleanup_filesystem_instance(instance_id)
    system("#{SYSADM} runlxc cleanup_filesystem_instance #{instance_id}")
  end
  
  def SA.mount_sshfs(path)
    system("#{SYSADM} runlxc mount_sshfs #{path}")
  end

  def SA.grant_sudo(id)
    system("#{SYSADM} runlxc grant_sudo #{id}")
  end

  def SA.setup_repos(id, repos)
    datafile = Tempfile.new('stackato')
    path = datafile.path
    datafile.close

    json = repos.to_json
    File.open(path, 'w') { |f| f.write(json) }

    system("#{SYSADM} runlxc setup_repos #{id} #{path}")
  end
end

