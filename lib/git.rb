load File.join(File.dirname(__FILE__), 'common.rb')
require 'fileutils'

# A set of static methods to help run Git commands from the command line.
class Git
  extend Common

  def Git.assert_valid_tag(tag)
    Preconditions.check_state(Version.is_valid?(tag), "Invalid tag[%s]. Format must be x.x.x (e.g. 1.1.2)" % tag)
  end

  def Git.clone(url, destination)
    run("git clone #{url} #{destination}", true)
  end

  def Git.get_repo_name
    run("basename `git rev-parse --show-toplevel`")
  end

  def Git.has_remote?
    system("git config --get remote.origin.url")
  end

  def Git.has_tag?(tag)
    if tag.nil?
      error "Tag cannot be null."
    else
      tags = run("git tag").split("\n")
      tags.include?(tag)
    end
  end

  def Git.latest_tag
    `git tag -l`.strip.split.select { |tag| Version.is_valid?(tag) }.map { |tag| Version.new(tag) }.sort.last
  end
end