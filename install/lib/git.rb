load File.join(File.dirname(__FILE__), 'common.rb')
require 'fileutils'

class Git
  extend Common

  def Git.clone(url, destination)
    run("git clone #{url} #{destination}", true)
  end

  def Git.get_remote_url
    run("git config --get remote.origin.url")
  end

  def Git.get_repo_name
    run("basename `git rev-parse --show-toplevel`")
  end

  def Git.has_tag?(tag)
    if tag.nil?
      error "Tag cannot be null."
    else
      tags = run("git tag").split("\n")
      tags.include?(tag)
    end
  end

  def Git.with_tmp_version(version = nil)
    current_dir = Dir.pwd
    temp_dir = "./tmp/#{random_string}"
    FileUtils.rm_rf(temp_dir)
    FileUtils.mkdir_p(temp_dir)
    Dir.chdir(temp_dir)
    begin
      repo_name = get_repo_name
      clone(get_remote_url, repo_name)
      Dir.chdir("./#{repo_name}")
      unless version.nil?
        if has_tag?(version)
          run("git checkout origin #{version}")
        else
          error "Version not found [#{version}]."
        end
      end
      yield
    rescue Exception => e
      error e.message
    ensure
      Dir.chdir(current_dir)
      FileUtils.rm_rf(temp_dir)
    end
  end
end