#!/usr/bin/env ruby

load File.join(File.dirname(__FILE__), './lib/all.rb')
include Common

usage = <<-TEXT
Usage: ./release.rb <tag_type>

This will release a new version of these journaling tools.

Arguments:

  -?|--help           Display description of usage.
  -a|--auto           Flag to utomatically push the changes to the remote repo.
TEXT

opts = Trollop::options do
  banner <<-EOS
This will release a new version of these journaling tools.

Usage:
    ./release.rb [options]
where [options] are:
EOS
  opt :auto, 'Flag to automatically push the changes to the remote repo.'
end

TAG_TYPES = ['major', 'minor', 'micro']
VERSION_LOCATION = "versions"

tag_type = ARGV[0].to_s.downcase
base_name = Git.get_repo_name
if TAG_TYPES.include?(tag_type)
  dirty_files = run("git status --porcelain").strip
  #Preconditions.check_state(dirty_files == "", "Local checkout is dirty:\n%s" % dirty_files)
  
  # Run tests here

  # Produce the version
  version = Version.read
  new_version = version.send("next_%s" % tag_type)
  tell "Current version is %s" % version.to_version_string
  tell "New version [#{tag_type}] is %s" % new_version.to_version_string
  Version.write(new_version)

  # Zip the repo for non-Git download/deploy
  run("zip -r %s/%s-%s.zip *" % [VERSION_LOCATION, base_name, new_version.to_version_string])
  run("zip -d %s/%s-%s.zip %s/* %s" % [VERSION_LOCATION, base_name, new_version.to_version_string, VERSION_LOCATION, VERSION_LOCATION])
  run("cp -f %s/%s-%s.zip %s/%s-current.zip" % [VERSION_LOCATION, base_name, new_version.to_version_string, VERSION_LOCATION, base_name])

  # Prep the changes in git
  #run("git commit -m 'autocommit: Update version to %s' VERSION %s/%s-%s.zip %s/%s-current.zip" % [new_version.to_version_string, VERSION_LOCATION, base_name, new_version.to_version_string, VERSION_LOCATION, base_name])
#  run("git tag -a -m '%s' %s" % [new_version.to_version_string, new_version.to_version_string])

  if opts[:auto] && Git.has_remote?
    tell "Pushing changes to remote"
#    run("git push origin")
#    run("git push --tags origin")
  else
    tell "Release tag[%s] created. Need to:" % new_version.to_version_string
    tell " git push origin"
    tell " git push --tags origin"
  end
else
  tell "Please specify one of [#{TAG_TYPES.join(", ")}]"
end