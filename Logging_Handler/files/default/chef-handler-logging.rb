require 'chef'
require 'chef/handler'
require 'net/smtp'

module Logging
  class LogChefRuns < Chef::Handler
    attr_reader :options

    def initialize(options = {})
      #get all the arguments passed to the class into an array called "options". reference attributes as options[:run_list], etc
      @options = options
    end
    
    def report
      if run_status.success?
        status = "0"
      else
        status = "1"
      end
      
      if options[:policy_name] == nil
         policy_name = ''
      else
         policy_name = options[:policy_name]
      end
      
      if options[:policy_group] == nil
         policy_group = ''
      else
         policy_group = options[:policy_group]
      end

      if options[:run_list_array] == nil
         run_list_array = ''
      else
         run_list_array = options[:run_list_array]
      end
      
      if options[:cookbook_collection] == nil
         cookbook_collection = ''
      else
         cookbook_collection = options[:cookbook_collection]
      end
      
      #iterate over the run_list, and pull out the version for each cookbook from the cookbook_collection
      run_list = []
      run_list_array.each do |r|
         recipeName = /recipe\[(\w+):*\w*\]/.match(r.to_s)[1]
         version = cookbook_collection[recipeName].metadata.version
         run_list.push(r.to_s + "(" + version + ")")
      end
      #concat the run_list array into a comma-delimited string
      run_list_string = run_list.join(',')
      
      url = 'https://myloggingserver.mydomain.com/Chef/chefCheckin.php?node=' + node.name + '&status=' + status + '&runlist=' + run_list_string + '&totalresources=' + run_status.all_resources.length.to_s + '&updatedresources=' + run_status.updated_resources.length.to_s + '&elapsedtime=' + run_status.elapsed_time.to_s + '&updatedresourcestext=' + run_status.updated_resources.join(",") + '&policyname=' + policy_name + '&policygroup=' + policy_group
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
    end
  end
  class SendEmail < Chef::Handler
    def report
      message = "From: Chef <chef@mydomain.com>\n"
      message << "To: Chef Admins <ChefAdmins@mydomain.com>\n"
      message << "Subject: Chef run failed on node #{node.name}\n"
      message << "Date: #{Time.now.rfc2822}\n\n"
      message << "Chef run failed on #{node.name}\n\n"
      message << "------------------------------------------------------\n"
      message << "                      EXCEPTION                       \n"
      message << "------------------------------------------------------\n"
      message << "#{run_status.formatted_exception}\n"
      message << "------------------------------------------------------\n"
      message << "                     STACK TRACE                      \n"
      message << "------------------------------------------------------\n"
      # Join the backtrace lines. Coerce to an array just in case.
      message << Array(backtrace).join("\n")

      Net::SMTP.start('mysmtpserver.mydomain.com', 25) do |smtp|
        smtp.send_message message, 'chef@mydomain.com', 'ChefAdmins@mydomain.com'
      end
    end
  end
end