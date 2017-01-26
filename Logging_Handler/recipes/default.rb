#
# Cookbook Name:: Logging_Handler
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.

include_recipe 'chef_handler'

cookbook_file "#{Chef::Config[:file_cache_path]}/chef-handler-logging.rb" do
  source 'chef-handler-logging.rb'
end.run_action(:create)

chef_handler 'Logging::LogChefRuns' do
  source "#{Chef::Config[:file_cache_path]}/chef-handler-logging.rb"
  arguments [
    :run_list_array => Array(Chef.run_context.node.run_list),
    :policy_name => Chef.run_context.node.policy_name,
    :policy_group =>  Chef.run_context.node.policy_group,
    :cookbook_collection => Chef.run_context.cookbook_collection
  ]
  supports :report => true, :exception => true
  action :nothing
end.run_action(:enable)

chef_handler "Logging::SendEmail" do
   source "#{Chef::Config[:file_cache_path]}/chef-handler-logging.rb"
   action :nothing
   supports :exception=>true
end.run_action(:enable)