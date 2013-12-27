load File.join(File.dirname(__FILE__), 'common.rb')

class Psql
  extend Common

  def Psql.in_schema(schema_name)
    schema_name ||= "public"
    query = <<-SQL
      set search_path to #{schema_name};
      #{yield}
    SQL
    unless schema_exists?(schema_name)
      query = "create schema #{schema_name};\n" + query
    end
    query
  end

  def Psql.run(dbname, opts = {})
    username = opts.delete(:username)
    host = opts.delete(:host)
    port = opts.delete(:port)
    ensure_empty_opts(opts)
    if `which psql` == ""
      error "You must have psql installed"
    elsif dbname.nil?
      error "You must specify the dbname"
    else
      query = yield
      command = "psql"
      command << " -U #{username}" unless username.nil?
      command << " -h #{host}" unless host.nil?
      command << " -p #{port}" unless port.nil?
      Common.run("#{command} -c \"#{query.gsub("\"", "\\\"").gsub("\$", "\\\$")}\" #{dbname}", true)
      if $?.exitstatus == 0
        true
      else
        error "psql command exited with nonzero status [#{$?.exitstatus}]."
        false
      end
    end
  end

  def Psql.schema_exists?(schema_name)
    result = Common.run("psql -U invoicedetail invoicedetail_us_test -c \"select schema_name from information_schema.schemata where schema_name = '#{schema_name}';\"")
    result.include?(schema_name) && !result.include?("0 rows")
  end
end