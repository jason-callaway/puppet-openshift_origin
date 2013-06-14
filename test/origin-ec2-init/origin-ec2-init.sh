#!/bin/bash

## These need to go into /etc/puppet/modules/openshift-origin/manifest/init.pp
## or get sed'd on the fly.
#deprepo="https://mirror.openshift.com/pub/openshift-origin/release/1/fedora-18/dependancies/x86_64/"
#pkgrepo="https://mirror.openshift.com/pub/openshift-origin/release/1/fedora-18/packages/x86_64/"

ipaddress=`ifconfig eth0 | grep inet\ | awk '{print $2}'`
domain=example.com
hostname=broker.${domain}

yum install -y git bind puppet facter tar vim
yum update -y

mkdir /etc/puppet/modules

#puppet module install openshift/openshift_origin
puppet module install puppetlabs/ntp
cp -Rp /root/puppet-openshift_origin /etc/puppet/modules/openshift_origin

/usr/sbin/dnssec-keygen -a HMAC-MD5 -b 512 -n USER -r /dev/urandom -K /var/named ${domain}
tsigkey=`cat /var/named/K${domain}.*.key  | awk '{print $8}'`

echo "${ipaddress} ${hostname}" >> /etc/hosts
hostname ${hostname}

cat <<EOF > /root/configure_origin.pp
class { 'openshift_origin' :
  #The DNS resolvable hostname of this host
  node_fqdn                  => "${hostname}",

  #The domain under which application should be created. Eg: <app>-<namespace>.example.com
  cloud_domain               => '${domain}',

  #Upstream DNS server.
  dns_servers                => ['${ipaddress}'],

  enable_network_services    => true,
  configure_firewall         => true,
  configure_ntp              => true,

  #Configure the required services
  configure_activemq         => true,
  configure_mongodb          => true,
  configure_named            => true,
  configure_avahi            => false,
  configure_broker           => true,
  configure_node             => true,

  #Enable development mode for more verbose logs
  development_mode           => true,

  #Update the nameserver on this host to point at Bind server
  update_network_dns_servers => true,

  #Use the nsupdate broker plugin to register application
  broker_dns_plugin          => 'nsupdate',

  #If installing from a local build, specify the path for Origin RPMs
  #install_repo               => 'file:///root/origin-rpms',

  #If using BIND, let the broker know what TSIG key to use
  named_tsig_priv_key         => '${tsigkey}'
}
EOF

puppet apply --verbose /root/configure_origin.pp

## Testing DHCP DNS tweaks
echo "DNS1=${ipaddress}"
echo "DNS2=172.16.0.23"
echo "DOMAIN=compute-1.internal jasoncallaway.com com"
systemctl restart network.service

## Install some missing gems that didn't seem to get 
## caught by puppet.  This shouldn't live here, puppet
## needs to be fixed.
gem install --no-ri --no-rdoc ci_reporter -v 1.7.0
gem install --no-ri --no-rdoc minitest -v 3.5.0
cd /var/www/openshift/console; bundle --local

## Fix this later -- EC2 doesn't really need a host-based
## firewall since the security groups are sufficient
## (if configured correctly).
systemctl stop iptables.service
systemctl disable iptables.service
