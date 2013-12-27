#!/usr/bin/env ruby

load File.join(File.dirname(__FILE__), 'lib/all.rb')
include Common

ACCEPTED_OPTIONS = ["?", "h", "help", "host", "p", "port", "schema_name", "s", "U", "username", "version", "v"]
REQUIRED_OPTIONS = [] # Nothing required, but could be this: [["schema_name", "s"], ["version", "v"]]

usage = <<-TEXT
Usage: ./postgres.rb -s <schema_name> -v <version> dbname

This will install the functions on <dbname>.

Arguments:

  -?|--help           Display description of usage.
  -h|--host=          The host name of the machine against which to run the script. Defaults to localhost.
  -p|--port=          The port of the running Postgres instance. Optional.
  -s|--schema_name=   The schema name under which to install the util functions. Defaults to "journal".
  -v|--version=       The tagged version number of the util to install. Defaults to the current version.
  -U|--username=      The postgres user to run the script as. Optional.
TEXT

if Argument.opt_exists?("?") || Argument.opt_exists?("help")
  tell usage
else
  Argument.required_opts(REQUIRED_OPTIONS, usage) do
    if Argument.all.size >= 1
      Argument.accepted_opts(ACCEPTED_OPTIONS)
      version = Argument.opt(["version", "v"])
      Git.with_tmp_version(version) do
        schema_name = Argument.opt(["schema_name", "s"]) || "journal"
        tell "Installing version [#{version || "current"}] on schema [#{schema_name}]"
        success = Psql.run(Argument.all[0], :username => Argument.opt(["username", "U"]),
                 :host => Argument.opt(["host", "h"]),
                 :port => Argument.opt(["port", "p"])) do
          Psql.in_schema(schema_name) do
            File.read("scripts/postgres/install.sql").gsub("journal.", "#{schema_name}.")
          end
        end
        tell "Journaling installed successfully." if success
      end
    else
      error "You must specify the dbname."
    end
  end
end
