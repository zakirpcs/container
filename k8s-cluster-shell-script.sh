!/bin/bash

# Global Variable
_DOMAIN=example.com
_HOST=k8s-master-01
_IP=`hostname -I`
_K8S-VER=v1.30
_NODE="Master"

# Set Hostname
hostnamectl set-hostname $_HOST.$_DOMAIN
echo "$_IP $_HOST.$_DOMAIN $_HOST" >>/etc/hosts

# Disable SELinux
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

# Disable Firewall
systemctl stop firewalld && systemctl disable firewalld 

# Disable Swap Memory
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Add Required Kernel modules and Enable IP forwarding
  /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Next load the modules using following modprobe command.
modprobe overlay
modprobe br_netfilter

tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Install & configure Conatinerd Runtime
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install containerd.io -y

containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
systemctl status containerd

# Install Kubernetes packages
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$_K8S-VER/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$_K8S-VER/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF

dnf update -y
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

if [[ "$_NODE" == "Master" ]]; then
	echo "Installing Kubernetes Cluster"
    kubeadm init --control-plane-endpoint=$_HOST.$_DOMAIN

elif [[ "$_NODE" == "Worker" ]]; then
   echo "Login into master node & execute below command\n" 
   echo "kubeadm token generate" 
   echo "kubeadm token create newly-created-token --print-join-command"
   echo "You will get the final command here. Then just execute this command to worker node."
else
   echo "This is not a Master or Worker node."
   exit
fi

