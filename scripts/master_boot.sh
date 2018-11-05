#!/bin/bash

INSTALL_BASEPATH="/root/zk"
LOGS_BASEPATH="/root/logs"
#EMAIL="$email"
#if [ "$EMAIL" == "noalert" ];
#then
#    EMAIL=""
#fi

if [ "$install" == "both" ];
then
	zenko_install=True
	metalk8s_install=True
elif [ "$install" == "metalk8sonly" ];
then
	zenko_install=False
	metalk8s_install=True
else
	zenko_install=False
	metalk8s_install=False
fi


## figure out version of MetalK8s and Zenko to grab for install
if [ "$METALK8S_VERSION" == "master" ];
then
	METALK8S_RELEASE_TYPE="repo"
	METALK8S_PULL_METHOD="git clone "
	METALK8S_URL="https://github.com/scality/metal-k8s.git"
else 
	METALK8S_RELEASE_TYPE="release"
	METALK8S_PULL_METHOD="curl -L -o $INSTALL_BASEPATH/metalK8s-v$METALK8S_VERSION.zip "
	METALK8S_URL="https://github.com/scality/metal-k8s/archive/$METALK8S_VERSION.zip"
fi

if [ "$ZENKO_VERSION" == "master" ];
then
	ZENKO_RELEASE_TYPE="repo"
	ZENKO_PULL_METHOD="git clone "
	ZENKO_URL="https://github.com/scality/Zenko.git"
else 
	ZENKO_RELEASE_TYPE="release"
	ZENKO_PULL_METHOD="curl -L -o $INSTALL_BASEPATH/Zenko-v$ZENKO_VERSION.zip "
	ZENKO_URL="https://github.com/scality/Zenko/archive/$ZENKO_VERSION.zip"
fi

mkdir $LOGS_BASEPATH

echo "Started" `date` | tee -a $LOGS_BASEPATH/install.log
echo "Checking for Happy Resolver..." | tee -a $LOGS_BASEPATH/install.log
while ping -c 2 repo.saltstack.com 2>&1 | grep -q "unknown host" ;do  echo waiting for network resolution...; done

# saving /etc/motd in case it has existing data
mv /etc/motd /etc/motd.old
(
	echo "--------------------------------------------------------"
	echo "Metalk8s and Zenko Installation still in progress"
	echo "Log back a little later for information on how to use"
	echo "Or follow the installation in the logs: /root/logs/*.log"
	echo "--------------------------------------------------------"
) >/etc/motd

## preparing the system
# Logs go into $LOGS_BASEPATH/system_prep.log
(
	## generating the /etc/hosts file
	echo "--> creating /etc/hosts - START - " `date +%R`
	## massaging the IPs list coming from the openstack stack to get individual IPs of nodes
	NODE_IPS="$nodeips"
	NODE1_IP=`echo $NODE_IPS | tr -d '[] ' | cut -f 1 -d ","`
	NODE2_IP=`echo $NODE_IPS | tr -d '[] ' | cut -f 2 -d ","`
	NODE3_IP=`echo $NODE_IPS | tr -d '[] ' | cut -f 3 -d ","`
	#NODE4_IP=`echo $NODE_IPS | tr -d '[] ' | cut -f 4 -d ","`
	#NODE5_IP=`echo $NODE_IPS | tr -d '[] ' | cut -f 5 -d ","`
	MASTER_IP=`hostname -I`

	echo "$MASTER_IP  master" >> /etc/hosts
	echo "$NODE1_IP  node-01" >> /etc/hosts
	echo "$NODE2_IP  node-02" >> /etc/hosts
	echo "$NODE3_IP  node-03" >> /etc/hosts
	#echo "$NODE4_IP  node-04" >> /etc/hosts
	#echo "$NODE5_IP  node-05" >> /etc/hosts
	echo "--> creating /etc/hosts - END - " `date +%R` 

	echo "--> Installing utilities - START - " `date +%R`
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
	## downloading a few things (kubectl & helm)
	curl -o /tmp/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.10.1/bin/linux/amd64/kubectl 
	curl -o /tmp/helm-v2.9.1-linux-amd64.tar.gz https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz 
	## and installing them
	mkdir -p /tmp/helm; cd /tmp/helm; tar -xf /tmp/helm-v2.9.1-linux-amd64.tar.gz;cd /root
	mv /tmp/helm/linux-amd64/helm /usr/bin
	mv /tmp/kubectl /usr/bin
	chmod u+x /usr/bin/kubectl /usr/bin/helm
	## cleaning up
	rm -rf /tmp/helm-v2.9.1-linux-amd64.tar.gz /tmp/get-pip.py /tmp/helm

	## ha proxy needs to be allowed in SE LINUX permissive mode to work properly
	semanage permissive -a haproxy_t
	systemctl enable haproxy
	systemctl restart rsyslog haproxy
	echo "<-- Installing utilities - EMD - " `date +%R`  

	echo "--> Fix authorized_keys, generate master ssh key and distribute it and the /etc/hosts file to the nodes - START - " `date +%R` 
	ssh-keygen -f /root/.ssh/id_rsa -N ""
	for i in {1..3};
	do
		echo "node-0$i"
		/usr/bin/sshpass -p "scality0" ssh -oStrictHostKeyChecking=no root@node-0$i "cat >> /root/.ssh/authorized_keys" < /root/.ssh/id_rsa.pub
		ssh root@node-0$i 'cat >> /home/centos/.ssh/authorized_keys' < /root/.ssh/id_rsa.pub
		ssh root@node-0$i 'chmod 700 /home/centos/.ssh/authorized_keys; chown centos:centos /home/centos/.ssh/authorized_keys'
		scp /etc/hosts root@node-0$i:/etc/hosts
		## removing the security hole we added to share the keys
		ssh root@node-0$i "passwd --delete root; sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd"
	done
	echo "--> Fix authorized_keys, generate master ssh key and distribute it to the nodes - END - " `date +%R`lk

	echo "--> Setting up the ansible inventory and variables for metalk8s install - START - " `date +%R` 
	mkdir -p $INSTALL_BASEPATH/k8s-cluster/group_vars
	cd $INSTALL_BASEPATH/k8s-cluster
	mv /root/inventory .
	mv /root/kube-node.yml /root/bigserver.yml /root/smallserver.yml group_vars
	echo "--> Setting up the ansible inventory and variables for metalk8s install - END - " `date +%R`  
) 2>&1 | tee -a $LOGS_BASEPATH/system_prep.log

# if installation was not selected, we can exit here
if [ "$install" = "none" ];
then
	echo "Finished" `date` | tee -a $LOGS_BASEPATH/install.log
	exit
fi

#if not, let's keep on with the installation of Metalk8s and optionally Zenko

## MetalK8s installation.
# Logs go into $LOGSBASEPATH/metalk8s_install.log
(
	if [ "$metalk8s_install" == "True" ];
	then
		echo "--> Preparing to run metalk8s install - START - " `date +%R` 
		export ANSIBLE_LOG_PATH=$LOGS_BASEPATH/metalk8s_ansible.log
		#make sure we fail the run at every error to avoid weird situations.
		export ANSIBLE_ANY_ERRORS_FATAL=true
		cd $INSTALL_BASEPATH
		## Depending on the type of release chosen, the treatment is different
		if [ "$METALK8S_RELEASE_TYPE" == "release" ];
		then
			echo "grabbing MetalK8s release..." 
			($METALK8S_PULL_METHOD $METALK8S_URL 2>&1) 
			unzip $INSTALL_BASEPATH/metalK8s-v$METALK8S_VERSION.zip 
			METALK8S_PATH=$INSTALL_BASEPATH/metalk8s-$METALK8S_VERSION
		elif [ "$METALK8S_RELEASE_TYPE" == "repo" ];
		then
			echo "cloning MetalK8s repo..." 
			($METALK8S_PULL_METHOD $METALK8S_URL 2>&1) 
			METALK8S_PATH=$INSTALL_BASEPATH/metal-k8s
		fi

		cd $METALK8S_PATH
		echo "--> Preparing to run metalk8s install - END - " `date +%R` 
		echo "--> Installing metalk8s - START - " `date +%R` 
		cd $METALK8S_PATH
		pip install -r requirements.txt 
		ansible-playbook -i ../k8s-cluster/inventory -b playbooks/deploy.yml 
		#-e metalk8s_ansible_hardening_enabled=false
		## setting up kube config
		mkdir /root/.kube
		cp $INSTALL_BASEPATH/k8s-cluster/artifacts/admin.conf /root/.kube/config
		echo "--> Installing metalk8s - END - " `date +%R` 
	fi
) 2>&1 | tee -a $LOGS_BASEPATH/metalk8s_install.log


## Zenko installation
# This is logged in $LOGS_BASEPATH/zenko_install.log
(
	if [ "$zenko_install" == "True" ];
	then	
		## Downloading Zenko based on what we picked in the form
		set -x
		cd $INSTALL_BASEPATH
		if [ "$ZENKO_RELEASE_TYPE" == "release" ];
		then
			echo "grabbing Zenko release..."
			($ZENKO_PULL_METHOD $ZENKO_URL 2>&1)
			unzip $INSTALL_BASEPATH/Zenko-v$ZENKO_VERSION.zip
			ZENKO_PATH=$INSTALL_BASEPATH/Zenko-$ZENKO_VERSION
		elif [ "$ZENKO_RELEASE_TYPE" == "repo" ];
		then
			echo "cloning Zenko repo..."
			($ZENKO_PULL_METHOD $ZENKO_URL 2>&1)
			ZENKO_PATH=$INSTALL_BASEPATH/Zenko
		fi

		echo "--> Installing Zenko - START - " `date +%R`
		cd $ZENKO_PATH
		## path has changed between versions so let's just go to the one that exists here
		if [ -d "kubernetes" ];
		then
			# we are in RC>=RC5, everything is in kubernetes/
			cd kubernetes/
		else	
			# we are in RC<RC5, everything is in charts
			cd charts/
		fi
		## moving to 5 nodes.
		#perl -pi -e 's/nodeCount: &nodeCount 3/nodeCount: &nodeCount 5/' zenko/values.yaml
		export HELM_HOME=/root/.helm
		export KUBECONFIG=/root/.kube/config
		echo "helm init..." 
		helm init --wait 
		echo "helm repo add..." 
		helm repo add incubator "http://storage.googleapis.com/kubernetes-charts-incubator" 
		helm repo add scality https://scality.github.io/charts/ 
		echo "helm dependency build zenko..." 
		helm dependency build zenko/  
		echo "helm install..." 
		helm install --name zenko --set ingress.enabled=true --set ingress.hosts[0]=zenko.local --set cloudserver-front.endpoint=zenko.local --set s3-data.persistentVolume.size='15Gi' --set mongodb-replicaset.persistentVolume.size='10Gi' zenko 
		## waiting for zenko cloudserver to be up and running to be able to grep the instance ID
		echo "waiting for the system to be up and running before going to next phase..."
		while [ -z "$(kubectl get pods --field-selector=status.phase=Running --selector=app=cloudserver -o json | jq .items[].metadata.name)" ] ; do echo "waiting for cloudserver..." ; sleep 15; done
		CS_POD_NAME=`kubectl get pods --field-selector=status.phase=Running --selector=app=cloudserver -o json | jq .items[].metadata.name | head -1 | tr -d "\""`
		while [ -z "$(kubectl logs $CS_POD_NAME | grep Instance)" ]; do echo "waiting for instance ID to show up in logs..."  ; sleep 10; done
		echo "system is up and running. Going to last phase to generate deployment.conf..."
	fi
) 2>&1 |tee -a $LOGS_BASEPATH/zenko_install.log

## Final phase
# Setting up Kubernetes dashboard & storing the information needed to access dashboard, grafana and prometheus in /root/deployment.conf
(
	NODE1_IP=`grep node-01 /etc/hosts | cut -f 1 -d ' '`
	export KUBECONFIG=/root/.kube/config
	CS_POD_NAME=`kubectl get pods --field-selector=status.phase=Running --selector=app=cloudserver -o json | jq .items[].metadata.name | head -1 | tr -d "\""`
	ZK_ID=`kubectl logs $CS_POD_NAME | grep Instance | jq .message | awk '/.* Instance ID is/{ print substr($NF,0,length($NF)-1) }'`
	## This is ugly to avoid having to deal with an SSH tunnel, but a correct ingress in kubernetes should do a much better trick
	#echo "--> Patching kubernetes-dashboard, kube-prometheus-prometheus and kube-prometheus-grafana service to be available through internal port..." `date +%R` 
	kubectl -n kube-system patch service kubernetes-dashboard -p '{"spec":{"type": "NodePort"}}'
	DASHBOARD_PORT=`kubectl -n kube-system get service kubernetes-dashboard -o json | jq '.spec.ports[0].nodePort'`
	KUBE_PASSWORD=`cat $INSTALL_BASEPATH/k8s-cluster/credentials/kube_user.creds`
	echo "--> Your Kubernetes cluster and Zenko instance are now available. Here is the info to get to all the services - " `date +%R` 
	echo " ------------------------ KUBERNETES ----------------------------------------------------------------------"
	echo "The Kubernetes dashboard can be accessed on https://$NODE1_IP:$DASHBOARD_PORT" 
	echo "Credentials:" 
	echo "  username: kube"
	echo "  password: $KUBE_PASSWORD" 
	if [ "$zenko_install" == "True" ];
	then
		echo " ------------------------  ZENKO ----------------------------------------------------------------------" 
		echo "You can register your zenko instance with Orbit with this ID: $ZK_ID" 
		echo "Go to https://admin.zenko.io/user and register the above ID" 
		echo " ------------------------------------------------------------------------------------------------------"
	fi
) 2>&1 |tee -a /root/deployment.conf

## echoing deplpyment.conf into /etc/motd so that it shows on a simple ssh on the system	
cat /etc/motd.old /root/deployment.conf >> /etc/motd
rm -f /etc/motd.old

#if [ ! -z "$EMAIL" ];
##then
 #   mail -r "marc.villemade@scality.cloud" -s "Your Zenko instance is ready to use" $EMAIL < /root/deployment.conf
#fi

echo "Finished" `date` | tee -a $LOGS_BASEPATH/install.log
