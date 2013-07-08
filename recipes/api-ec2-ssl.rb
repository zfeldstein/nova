#
# Cookbook Name:: nova
# Recipe:: nova-ssl
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"
include_recipe "osops-utils::mod_ssl"

# Remove monit file if it exists
if node.attribute?"monit"
  if node["monit"].attribute?"conf.d_dir"
    file "#{node['monit']['conf.d_dir']}/nova-api-ec2.conf" do
      action :delete
    end
  end
end

# setup cert files
case node["platform"]
when "ubuntu", "debian"
  grp = "ssl-cert"
else
  grp = "root"
end

cookbook_file "#{node["nova"]["ssl"]["dir"]}/certs/#{node["nova"]["services"]["ec2-public"]["cert_file"]}" do
  source "nova_ec2.pem"
  mode 0644
  owner "root"
  group "root"
  notifies :run, "execute[restore-selinux-context]", :immediately
end

cookbook_file "#{node["nova"]["ssl"]["dir"]}/private/#{node["nova"]["services"]["ec2-public"]["key_file"]}" do
  source "nova_ec2.key"
  mode 0644
  owner "root"
  group grp
  notifies :run, "execute[restore-selinux-context]", :immediately
end

# setup wsgi file

directory "#{node["apache"]["dir"]}/wsgi" do
  action :create
  owner "root"
  group "root"
  mode "0755"
end

cookbook_file "#{node["apache"]["dir"]}/wsgi/#{node["nova"]["services"]["ec2-public"]["wsgi_file"]}" do
  source "ec2api_modwsgi.py"
  mode 0644
  owner "root"
  group "root"
end

ec2_bind = get_bind_endpoint("nova", "ec2-public")

template value_for_platform(
  ["ubuntu", "debian", "fedora"] => {
    "default" => "#{node["apache"]["dir"]}/sites-available/openstack-nova-ec2api"
  },
  "fedora" => {
    "default" => "#{node["apache"]["dir"]}/vhost.d/openstack-nova-ec2api"
  },
  ["redhat", "centos"] => {
    "default" => "#{node["apache"]["dir"]}/conf.d/openstack-nova-ec2api"
  },
  "default" => {
    "default" => "#{node["apache"]["dir"]}/openstack-nova-ec2api"
  }
) do
  source "modwsgi_vhost.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :listen_ip => ec2_bind["host"],
    :service_port => ec2_bind["port"],
    :cert_file => "#{node["nova"]["ssl"]["dir"]}/certs/#{node["nova"]["services"]["ec2-public"]["cert_file"]}",
    :key_file => "#{node["nova"]["ssl"]["dir"]}/private/#{node["nova"]["services"]["ec2-public"]["key_file"]}",
    :wsgi_file  => "#{node["apache"]["dir"]}/wsgi/#{node["nova"]["services"]["ec2-public"]["wsgi_file"]}",
    :proc_group => "nova-ec2api",
    :log_file => "/var/log/nova/ec2api.log"
  )
  notifies :run, "execute[restore-selinux-context]", :immediately
  notifies :reload, "service[apache2]", :delayed
end

apache_site "openstack-nova-ec2api" do
  enable true
  notifies :run, "execute[restore-selinux-context]", :immediately
  notifies :restart, "service[apache2]", :immediately
end
