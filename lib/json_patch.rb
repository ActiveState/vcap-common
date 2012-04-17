# fixes an issue with json_pure when targetting from client,
# http://blog.ethanvizitei.com/2010/11/json-pure-ruins-my-morning.html

class Fixnum
  def to_json(options = nil)
    to_s
  end
end
