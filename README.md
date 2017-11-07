# ucp-1709-testing

UCP on Azure

Create a Ubuntu 16.04 VM w static private IP address

Install Docker
https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/

```
sudo -i
apt-get update
apt-get install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-cache show docker-ce
apt-get install docker-ce=17.06.*
docker version
docker run hello-world
```

Azure network group inbound port configuration

443
2376-2377
4789
7946
12376,12379
12380-12387

Install UCP

https://docs.docker.com/datacenter/ucp/2.2/guides/admin/install/ 
Host address = resource group subnet (ie 172.16.8.6)
Licenses pinned to #product-ee channel
Add public IP to SAN list

WS1709 worker

Install WS1709 with Containers from MarketPlace
Use same network security group as above

Install EE Preview
```
stop-service docker
uninstall-package docker -PackageProvider DockerMsftProvider

Install-Module DockerProvider
Install-Package Docker -Providername DockerProvider -RequiredVersion preview
```
* Sometimes the package name is DefaultDocker?

Set daemon to use hyper-v isolation and enable debug logging
https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility

Create c:\ProgramData\docker\config\daemon.json

{
    "exec-opts":["isolation=hyperv"],
    "debug": true    
}
```
dockerd
docker version
```

Install UCP agent and run script

```
docker image pull docker/ucp-agent-win:2.2.4
docker image pull docker/ucp-dsinfo-win:2.2.4
docker container run --rm docker/ucp-agent-win:2.2.4 windows-script | powershell -noprofile -noninteractive -command 'Invoke-Expression -Command $input'
```

Warning in output
```
Testing for required windows updates  = [System.Version]::Parse 10.0.16299.15  = [System.Version]::Parse 10.0.14393.1066 if False       Write-Host "System is missing a required update. Please check windows updates or apply this KB4015217: http://www.catalog.update.microsoft.com/Search.aspx?q=KB4015217 before adding this node to your UCP cluster" -ForegroundColor yellow  Write-Host Setting up Docker daemon to listen on port 2376 with TLS

Generating new certs at C:\ProgramData\docker\daemoncerts
Restarting Docker daemon
Successfully set up Docker daemon
Opening port 2376 in the Windows firewall for inbound traffic
Opening port 12376 in the Windows firewall for inbound traffic
Opening port 2377 in the Windows firewall for inbound traffic
Opening port 4789 in the Windows firewall for inbound and outbound traffic
Opening port 7946 in the Windows firewall for inbound and outbound traffic
```
join swarm via URL from UCP

UCP agent logs feature not working for 1709 workers

Deploy a service
```
docker network create <overlay1>
docker service create --name t1 --replicas 3 --network overlay1 -p 8080:80 --constraint node.platform.os==windows microsoft/iis:1709
```

One worker instead of two
Eliminate overlay network (ingress only)
Start with one replica and scale up
docker service create --name t1 --replicas 1 -p 8080:80 --constraint node.platform.os==windows microsoft/iis:1709

------------

iptables configuration - not needed
```
#!/bin/bash

ports='443 12386 12387 12379 12385 12376 12384 12381 12383 12380 2376 2377 12382 12386 4789 7946'

for port in $ports
do
   iptables -A INPUT -p udp --dport $port -j ACCEPT
   iptables -A INPUT -p tcp --dport $port -j ACCEPT
done
iptables-save > /etc/iptables.conf
add iptables-restore /etc/iptables.conf to /etc/rc.local
```

