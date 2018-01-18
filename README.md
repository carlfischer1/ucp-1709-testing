# Server 1709 testing on Azure

## UCP

Create a Ubuntu 16.04 VM w static private IP address

Create new network security group with required inbound ports:

443

2376-2377

4789

7946

12376, 12379

12380-12387

### Install Docker
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

Alternatively, to get the latest Edge channel version of Docker CE
```
curl -fsSL get.docker.com > get-docker.sh
sh get-docker.sh
```

### Install UCP

https://docs.docker.com/datacenter/ucp/2.2/guides/admin/install/ 

Host address = resource group subnet (ie 172.*)

Add public IP to SAN list

### Create WS1709 worker
Create "WS1709 with Containers" VM from Azure MarketPlace

Use same network security group as above

Install EE Preview
```
stop-service docker
uninstall-package Docker -Provider DockerMsftProvider

Install-Module DockerProvider
Install-Package Docker -Providername DockerProvider -RequiredVersion preview
```
For use with Windows Server 2016 (RS1) images set daemon to use hyper-v isolation

https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility

```
Create c:\ProgramData\docker\config\daemon.json

{
    "exec-opts":["isolation=hyperv"]
}
```
```
restart-computer
...
docker version
docker info
```

Install UCP agent and run script

```
docker image pull docker/ucp-agent-win:2.2.4
docker image pull docker/ucp-dsinfo-win:2.2.4
docker container run --rm docker/ucp-agent-win:2.2.4 windows-script | powershell -noprofile -noninteractive -command 'Invoke-Expression -Command $input'
```

Add Windows node in UCP and join swarm via provided URL

### Known issues

1 - Warning in UCP windows-script output
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

2 - UCP agent logs feature not working for 1709 workers

3 - After shutdown and restart of cluster all 1709 nodes show red, with status of "Awaiting healthy status in classic node inventory". All nodes are shown as Ready in ```docker node ls```


----------

# VIP service discovery
## Mixed swarm
Create a 3 node swarm 

* 1 x Ubuntu 16.04 master running Docker EE 17.06

* 2 x Windows Server 1709 workers running EE Preview-3

Deploy two services, each will get a VIP address
```
docker network create overlay1 --driver overlay
docker service create --name s1 --replicas 2 --network overlay1 --constraint node.platform.os==windows microsoft/iis
docker service create --name s2 --replicas 2 --network overlay1 --constraint node.platform.os==windows microsoft/iis
```

Find a container ID for each task (run on workers)
```
docker ps --format "{{.ID}}: {{.Names}}"
```

Verify connectiviy between services s1 and s2 via VIP on overlay network. On worker running a task for service s1:
```
docker exec -it <ID of s1 container> powershell
Invoke-WebRequest -Uri http://s2 -UseBasicParsing
```
When the Linux master is running 17.06 the following failure occurs. When running 17.10 the operation succeeds as expected.
```
Invoke-WebRequest : Unable to connect to the remote server
At line:1 char:1
+ Invoke-WebRequest -Uri http://s2 -UseBasicParsing
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (System.Net.HttpWebRequest:HttpWebRequest) [Invoke-WebRequest], WebExc
   eption
    + FullyQualifiedErrorId : WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand
```
The same test but using the VIP IP address directly also fails.

## Native Windows swarm
Create a 2 node Windows Server 1709 swarm running EE Preview-3

Use above image

Use above commands to create overlay network, and deploy services

Verify connectivity between services s1 and s2 via VIP on overlay network. On worker running a task for service s1:
```
docker exec -it <ID of s1 container> powershell
Invoke-WebRequest -Uri http://s2 -UseBasicParsing
```
Returns a ```200``` from the default IIS website:
```
StatusCode        : 200
StatusDescription : OK
Content           : <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
                    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
                    <html xmlns="http://www.w3.org/1999/xhtml">
                    <head>
                    <meta http-equiv="Content-Type" cont...
RawContent        : HTTP/1.1 200 OK
                    Accept-Ranges: bytes
                    Content-Length: 703
                    Content-Type: text/html
                    Date: Wed, 08 Nov 2017 02:01:14 GMT
                    ETag: "f2f79a40d951d31:0"
                    Last-Modified: Mon, 30 Oct 2017 23:46:05 GMT
                    Serve...
Forms             :
Headers           : {[Accept-Ranges, bytes], [Content-Length, 703], [Content-Type, text/html], [Date, Wed, 08 Nov 2017
                    02:01:14 GMT]...}
Images            : {@{outerHTML=<img src="iisstart.png" alt="IIS" width="960" height="600" />; tagName=IMG;
                    src=iisstart.png; alt=IIS; width=960; height=600}}
InputFields       : {}
Links             : {@{outerHTML=<a href="http://go.microsoft.com/fwlink/?linkid=66138&amp;clcid=0x409"><img
                    src="iisstart.png" alt="IIS" width="960" height="600" /></a>; tagName=A;
                    href=http://go.microsoft.com/fwlink/?linkid=66138&amp;clcid=0x409}}
ParsedHtml        :
RawContentLength  : 703
```

# Ingress service publishing
## Mixed swarm

Ensure port 8080 is open in Azure network security group used by the VMs in the swarm

Create service

```
docker service create --name s3 --replicas 2 --network overlay1 -p 8080:80 --constraint node.platform.os==windows microsoft/iis
```

Browse to ```http://<Public IP address of any VM in the swarm>:8080```

Default IIS website should be displayed

# DNSRR service discovery
## Native Windows swarm

In a three node Windows swarm, create overlay network and services
```
docker network create overlay2 --driver overlay
docker service create --name s4 --replicas 3 --network overlay2 --endpoint-mode dnsrr --constraint node.platform.os==windows microsoft/iis
```

Verify that a task of the service is running on each node
```
docker service ps s4 --filter desired-state=Running --format "{{.ID}}: {{.Name}}: {{.Node}}"
ba4yv41drrc9: s4.1: 1709-3
i0a4oa0mmv7d: s4.2: 1709-4
ju0890skj24k: s4.3: 1709-5
```

Find a container running a task of the service (only containers for tasks running on that node will be returned)
```
docker ps --format "{{.ID}}: {{.Names}}"
e69fffa58401: s4.1.ba4yv41drrc9e4zker0isx4xl
```

Verify DNSRR for service s4 on the overlay network. DNS resolution should include an IP address for each task of the service, with the order of IP addresses changing across multiple queries:
```
docker exec -it <ID of s4 container> powershell

PS C:\> Resolve-DnsName -Name s4 -DnsOnly

Name                                           Type   TTL   Section    IPAddress
----                                           ----   ---   -------    ---------
s4                                             A      600   Answer     10.0.0.5
s4                                             A      600   Answer     10.0.0.4
s4                                             A      600   Answer     10.0.0.7


PS C:\> Resolve-DnsName -Name s4 -DnsOnly

Name                                           Type   TTL   Section    IPAddress
----                                           ----   ---   -------    ---------
s4                                             A      600   Answer     10.0.0.4
s4                                             A      600   Answer     10.0.0.7
s4                                             A      600   Answer     10.0.0.5


PS C:\> Resolve-DnsName -Name s4 -DnsOnly

Name                                           Type   TTL   Section    IPAddress
----                                           ----   ---   -------    ---------
s4                                             A      600   Answer     10.0.0.7
s4                                             A      600   Answer     10.0.0.4
s4                                             A      600   Answer     10.0.0.5
```

Ping each IP address returned from DNS to verify connectivity across tasks in the cluster.

# Background 
------------
Find the VIP addresses for a service
```
docker service inspect s1
```
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

or
```
tail -f /var/log/upstart/docker.log
```

------------
Tailing docker daemon logs on Windows
```
dockerd -D > log.txt
Get-Content .\log.txt -Wait
```
------------

iptables configuration
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
------------
Create a wrapper image to run IIS
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

------------
Methods to get Windows version

Doesn't return UBR pre-1709
```
cmd /c ver
```

Works across versions
```
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
```

------------
Tailing dockerd event logs on Windows
```
$lastCheck = (Get-Date).AddSeconds(-2) 
while ($true) 
{ 
    Get-EventLog Application -Source docker -After $lastcheck |% { $_.TimeGenerated.ToString() + ': ' + $_.ReplacementStrings }
    $lastCheck = Get-Date 
    Start-Sleep -Seconds 2
}
```

------------
Alternate method to view an image manifest (hosted version of https://github.com/estesp/manifest-tool)
```
Dockers-MacBook-Air:carlfischer$ docker run --rm mplatform/mquery library/hello-world
Unable to find image 'mplatform/mquery:latest' locally
latest: Pulling from mplatform/mquery
db6020507de3: Pull complete 
f11a2bcbeb86: Pull complete 
Digest: sha256:e15189e3d6fbcee8a6ad2ef04c1ec80420ab0fdcf0d70408c0e914af80dfb107
Status: Downloaded newer image for mplatform/mquery:latest
Image: library/hello-world
 * Manifest List: Yes
 * Supported platforms:
   - linux/amd64
   - linux/arm/v5
   - linux/arm/v7
   - linux/arm64/v8
   - linux/386
   - linux/ppc64le
   - linux/s390x
   - windows/amd64:10.0.14393.1944
   - windows/amd64:10.0.16299.125
   ```

