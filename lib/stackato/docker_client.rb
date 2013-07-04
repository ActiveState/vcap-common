require 'docker'

# Wrapper around the underlying docker ruby API library. For now, it
# is meant to be used by vcap-services, but we could use it in other
# places as well.
class StackatoDocker
  
  # Return the container by id. If the container doesn't exist, return
  # nil.
  def self.get_container(id)
    # TODO: docker-api gem does not have a direct method to check if a
    # particular ID exists or not. Hence, we fallback on the
    # (reasonably) slower "all" API.
    Docker::Container.all.detect {|c|
      c.id == id
    }
  end

  def self.build_image(image_name, dockerfile_dir)
    img = Docker::Image.build_from_dir(dockerfile_dir)
    img.tag 'repo' => image_name, 'force' => true
    img
  end

end
