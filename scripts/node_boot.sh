#!/bin/bash

echo "Started" `date` | tee -a /root/install.log
echo "Checking for Happy Resolver..."
while ping -c 2 repo.saltstack.com 2>&1 | grep -q "unknown host" ;do  echo waiting for network resolution...; done

## fix authorized hosts
##cut -d " " -f 14,15 /root/.ssh/authorized_keys > /root/.ssh/tmp
#mv -f /root/.ssh/tmp /root/.ssh/authorized_keys

(
  echo "--> Installing utilities" - `date +%R`
  yum install -y bind-utils git ntp sshpass mailx haproxy unzip tmux
  curl -L -o jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
  chmod u+x jq
  mv jq /usr/bin
  systemctl start ntpd
  mv /root/haproxy.cfg /etc/haproxy/haproxy.cfg
  ## downloading and installing pip, kubectl and helm
  echo "downloading and installing pip, kubectl and helm..."
  curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py 
  python /tmp/get-pip.py
  ## "uninstalling" some libs that break the pip install otherwise
  rm -rf /usr/lib/python2.7/site-packages/requests-2.6.0-py2.7.egg-info 
  rm -rf /usr/lib64/python2.7/site-packages/PyYAML-3.10-py2.7.egg-info
  systemctl start ntpd
  echo "Installing utilities <-- done" - `date +%R`
) 2>&1 | tee -a /root/install.log

## Set root password and open up password authentication thru ssh - security hole fixed later in the process
echo `date +%R` " --> Set root password & open up ssh password authentication" 2>&1 | tee -a /root/install.log
  (
  echo "scality0"
  ) | passwd --stdin root
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
echo `date +%R` " & open up ssh password authentication <-- done"| tee -a /root/install.log

echo "Finished" `date` | tee -a /root/install.log
