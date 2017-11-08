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
uninstall-package Docker -PackageProvider DockerMsftProvider

Install-Module DockerProvider
Install-Package Docker -Providername DockerProvider -RequiredVersion preview
```
For use with Windows Server 2016 (RS1) images set daemon to use hyper-v isolation
https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility
```
Create c:\ProgramData\docker\config\daemon.json

{
    "exec-opts":["isolation=hyperv"],
    "debug": true    
}
```
```
dockerd -D
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

----------

# Mixed swarm VIP testing

Create a 3 node swarm with an Ubuntu 16.04 master and 2 x Windows Server 1709 workers
Create a dockerfile to run IIS
```
FROM microsoft\iis
EXPOSE 80
```

Build and push
```
docker build .
docker tag <image ID> carlfischer/cfiis
docker login --username carlfischer
docker push carlfischer/cfiis
```
See https://github.com/docker/saas-mega/issues/3389. To workaround, build the image on both Windows workers.

Deploy two services, each will get a VIP address
```
docker network create overlay1 --driver overlay
docker service create --name s1 --replicas 2 --network overlay1 --constraint node.platform.os==windows carlfischer/cfiis
docker service create --name s2 --replicas 2 --network overlay1 --constraint node.platform.os==windows carlfischer/cfiis
```

Find the VIP addresses for each service
```
docker service inspect s1
docker service inspect s2
```

Find a container ID for each task (run on workers)
```
docker ps --format "{{.ID}}: {{.Names}}"
```

Verify connectiviy via VIP on overlay network. On worker running a task for service s1:
```
docker exec -it <ID of s1 container> powershell
Invoke-WebRequest -Uri http://<VIP of s2> -UseBasicParsing

Invoke-WebRequest : Unable to connect to the remote server
At line:1 char:1
+ Invoke-WebRequest -Uri http://10.0.0.3 -UseBasicParsing
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (System.Net.HttpWebRequest:HttpWebRequest) [Invoke-WebRequest], WebExc
   eption
    + FullyQualifiedErrorId : WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand
```

# Native Windows swarm VIP testing
Create a 2 node Windows Server 1709 swarm
Use above image
Use above commands to create overlay network, deploy services, and verify connectivity





------------

Opening ports in Windows firewall

```
netsh firewall add portopening TCP 2377 "Port 2377"
netsh firewall add portopening TCP 2376 "Port 2376"
netsh firewall add portopening TCP 7496 "Port 7496"

```

------------

Tailing docker daemon logs on Ubuntu
```
journalctl -f -u docker.service
```

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

