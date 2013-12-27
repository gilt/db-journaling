load File.join(File.dirname(__FILE__), 'common.rb')

class Argument
  extend Common

  @args = []
  @opts = {}
  current_opt = nil
  ARGV.each do |argument|
    if match = argument.match("^--(.+)=(.+)$")
      @opts[match[1]] = match[2]
    elsif match = argument.match("^-(.+)")
      opt = match[1]
      opt.chars.each do |opt|
        @opts[opt] ||= nil
      end
      current_opt = opt[-1, 1]
    else
      if current_opt.nil?
        @args << argument
      else
        @opts[current_opt] = argument
        current_opt = nil
      end
    end
  end

  def Argument.accepted_opts(names)
    unrecognized = @opts.keys.select { |name|
      !names.include?(name)
    }
    unless unrecognized.empty?
      tell "Warning: unrecognized options will be ignored [#{unrecognized.join(', ')}]"
    end
  end

  def Argument.all
    @args
  end

  def Argument.required_opts(names, usage = nil)
    missing = names.map { |name|
      if name.is_a?(Array)
        found = name.select { |n|
          @opts.keys.include?(n)
        }
        name[0] if found.empty?
      else
        name unless @opts.keys.include?(name)
      end
    }.compact
    if missing.empty?
      yield
    else
      error "Required arguments are missing: #{missing.join(', ')}\n#{usage}"
    end
  end

  def Argument.opt(names)
    names = [names] unless names.is_a?(Array)
    names.map { |name|
      @opts[name]
    }.compact.first
  end

  def Argument.opts
    @opts
  end

  def Argument.opt_exists?(name)
    @opts.keys.include?(name)
  end
end