module Common
  def ensure_empty_opts(opts)
    if !opts.keys.empty?
      raise "Invalid options passed into method [#{opts.keys.join(", ")}]"
    end
  end

  def error(message)
    tell "Error: #{message}"
  end

  def random_string(length = nil)
    (0...(length || 10)).map { (65 + rand(26)).chr }.join
  end

  def run(command, ignore_output = false)
    tell command unless ignore_output
    if ignore_output
      `#{command} &> /dev/null`
      nil
    else
      `#{command}`.to_s.chomp
    end
  end

  def tell(message)
    puts message
  end
end