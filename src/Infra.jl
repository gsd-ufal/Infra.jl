###=============================================================================
#
#          FILE: Infra.jl
#
#         USAGE: include("../Infra.jl")
#
#   DESCRIPTION: Julia interface to launch containers through Azure VM
#
#       OPTIONS: ---
#  DEPENDENCIES: sshpass
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raphael P. Ribeiro <raphaelpr01@gmail.com>
#  ORGANIZATION: GSD-UFAL
#       CREATED: 23-09-2015 17:16
#
###=============================================================================

module Infra

using Requests: get, parse
using Docker

###== Top-level variables ======================================================

const nprocs=16 # number of cpu cores available from server
const ssh_key=homedir()*"/.ssh/azkey"
const ssh_pubkey=homedir()*"/.ssh/azkey.pub"
const carray_dir= length(LOAD_PATH) == 3 ? LOAD_PATH[3]*"Infra/src" : Pkg.dir("Infra")*"/src" # Infra package directory

###=============================================================================

type GlobalSettings
    host::ASCIIString
    url::ASCIIString
    passwd::ASCIIString
    cpuset::Array{Int64,1} # number of cpu cores available from server
end

type Container # Abstraction for Docker container
          cid::AbstractString
          pid::Integer
          cpuset::Array{Int64,1}
          mem_size::Integer

          function Container(cid,pid,cpuset=[],mem_size=512)
              return new(cid,pid,cpuset,mem_size)
          end
end

const map_containers = Dict{Integer, Container}()

GlobalSettings() = GlobalSettings("","","",collect(0:nprocs-1))
const SETTINGS = GlobalSettings()

set_h(h) = SETTINGS.host=h
set_url(u) = SETTINGS.url=u
set_passwd(p) = SETTINGS.passwd=p
set_cpuset(c) = SETTINGS.cpuset=c

let next_key = 1    # cid -> container id
    global get_next_key
    function get_next_key() retval = next_key
        next_key += 1
        retval
    end
end

function parse_cpuset(n_of_cpus)
    if (n_of_cpus == 0 || length(SETTINGS.cpuset) < n_of_cpus)
        "",[]
    else
        s = strip(string(SETTINGS.cpuset[1:n_of_cpus]),['[',']'])
        a = SETTINGS.cpuset[1:n_of_cpus]
        deleteat!(SETTINGS.cpuset,1:n_of_cpus)
        s,a
    end
end

@doc """
### set_host(h::AbstractString,p::AbstractString)

Configures passwordless SSH connections at host `h` whose password is `p`.

This function calls the `cloud_setup.sh` script which requires `sshpass`.

```Example
set_host("cloudarray.cloudapp.net","password")
```
""" ->
function set_host(h::AbstractString,p::AbstractString)
    reply = success(`$(carray_dir)/cloud_setup.sh $h $p`) # set up ssh. if errors occurs, return false
    if (reply)
        set_h(h)
        set_url(h*":4243")
        set_passwd(p)
        true
    else
        error("There is an error during SSH configuration. Please see the log for more details: cloud_setup.log")
        false
    end
end

function get_port()
    response = get("http://$(SETTINGS.host):8000")
    parse(Int,join(map(Char,response.data)))
end

@doc """
### create_containers(n_of_containers::Integer, n_of_cpus::Integer, mem_size::Integer; tunnel::bool)

Launches Docker containers and adds them as Julia workers configured with passwordless SSH.

This function requires `sshpass` to be installed:

* Debian-based Linux distros as Ubuntu:

```
sudo apt-get install sshpass
```

* OS X through [macports](http://macports.org):

```
sudo port install sshpass
```


```Example
create_containers(2,3,1024) # 2 containers with 3 CPU Cores and 1gb RAM
create_containers(1,2,512)  # 1 container with 2 CPU Cores and 512mb RAM
```
""" ->
function create_containers(n_of_containers::Integer, n_of_cpus=0, mem_size=512;tunnel=false)
        reserved_mem=200 # reserved memory for initializing a worker into a container
        mem_size=mem_size+reserved_mem
        for i in 1:n_of_containers
            ssh_config = false
            key = get_next_key()
            port = 3000+get_port()
            n_of_cpus=parse_cpuset(n_of_cpus)
            # Creating a docker container at VM
            info("Creating container ($key)...")
            container = Docker.create_container("$(SETTINGS.url)","cloudarray:latest",memory=mem_size*(10^6),cpuSets=n_of_cpus[1],portBindings=[22,"$port"])
            Docker.start_container("$(SETTINGS.url)",container["Id"])
            info("Creating container ($key)... OK")
            # Configuring ssh without password (transfer public key to container)
            info("SSH configuration ($key)... ")
            while !ssh_config
                ssh_config = success(pipeline(`cat $ssh_pubkey`,`sshpass -p $(SETTINGS.passwd) ssh -o StrictHostKeyChecking=no -p $port root@$(SETTINGS.host) 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'`)) # if ssh configuration is successful: return true or false
                if !ssh_config
                    info("SSH configuration ($key) failed! Trying again...")
                end
            end
            info("SSH configuration ($key)... OK")
            info("Adding worker ($key)...")
            pid = addprocs(["root@$(SETTINGS.host)"];tunnel=tunnel,sshflags=`-i $ssh_key -p $port`,dir="/opt/julia/bin",exename="/opt/julia/bin/julia")
            info("Adding worker ($key)... OK")
            map_containers[key] = Container(chomp(container["Id"]),pid[1],n_of_cpus[2],mem_size) # Adding Container to Dict
        end
end

@doc """
### delete_containers(args...)

Removes the specified container(s)/worker(s).

```Example
delete_containers(3)    # delete container 3
create_containers(1:5)  # delete from 1st to 5th container
create_containers(all)  # delete all containers
```
""" ->
function delete_containers(args...) #  (splat) variable number of arguments. Ex.: delete_containers(1,2,3) or delete_containers(1:3)
    containers_rmlist = Dict()
    if vcat(args...)[1] == all
        for i in collect(keys(map_containers))
            if haskey(map_containers, i) # container exist?
                container = map_containers[i]
                rmprocs(container.pid)
                delete!(map_containers,i)
                set_cpuset(collect(0:nprocs-1))
                Docker.remove_container("$(SETTINGS.url)","$(container.cid)")
            end
        end
    else
        for i in vcat(args...) # vcat -> concatenate to a array 1 dimension
            if haskey(map_containers, i) # container exist?
                container = map_containers[i]
                rmprocs(container.pid)
                delete!(map_containers,i)
                set_cpuset([container.cpuset;SETTINGS.cpuset])
                Docker.remove_container("$(SETTINGS.url)","$(container.cid)")
            end
        end
    end
end


@doc """
### containers()

Returns the list of all containers' processes identifiers (IDs).

```Example
containers()
```
""" ->
function containers()
    sort(collect(keys(map_containers)))
end

@doc """
### ncontainers()

Gets the number of available container processes.

```Example
ncontainers()
```
""" ->
function ncontainers()
    length(map_containers)
end

@doc """
### list_containers()

List container(s) as a sorted list.

```Example
list_containers()
```
""" ->
function list_containers()
    for key in sort(collect(keys(map_containers)))
           println("$key => $(map_containers[key])")
    end
end

@doc """
### mem_usage(key::Integer)

Returns the container memory usage.

```Example
mem_usage(number_of_container)
```
""" ->
function mem_usage(key::Integer)
    Docker.stats_container("$(SETTINGS.url)","$(map_containers[key].cid)")["memory_stats"]["usage"]/10^6
end

@doc """
### cpu_usage(key::Integer)

Returns the container CPU usage (%).

```Example
cpu_usage(number_of_container)
```
""" ->
function cpu_usage(key)
    stats = Docker.stats_container("$(SETTINGS.url)","$(map_containers[key].cid)")

    percpu_usage = stats["cpu_stats"]["cpu_usage"]["percpu_usage"]
    previousSystem = stats["precpu_stats"]["system_cpu_usage"]
    previousCPU = stats["precpu_stats"]["cpu_usage"]["total_usage"]
    totalUsage = stats["cpu_stats"]["cpu_usage"]["total_usage"]
    systemUsage = stats["cpu_stats"]["system_cpu_usage"]
    
    cpuPercent = 0.0
    cpuDelta = totalUsage - previousCPU
    systemDelta = systemUsage - previousSystem
    cpuPercent = (cpuDelta / systemDelta) * length(percpu_usage) * 100.0
    cpuPercent
end

@doc """
### io_usage(key::Integer)

Returns the number of kilobytes read and written by the cgroup.

```Example
io_usage(number_of_container)
```
""" ->
function io_usage(key::Integer)
    stats = Docker.stats_container("$(SETTINGS.url)","$(map_containers[key].cid)")["blkio_stats"]
    w = stats["io_service_bytes_recursive"][1]["value"]/10^3   # write
    r = stats["io_service_bytes_recursive"][2]["value"]/10^3   # read
    [w,r]
end

@doc """
### net_usage(key::Integer)

Returns networking TX/RX usage.

tx = number of bytes transmitted
rx = number of bytes reiceved

```Example
net_usage(number_of_container)
```
""" ->
function net_usage(key::Integer)
    stats = Docker.stats_container("$(SETTINGS.url)","$(map_containers[key].cid)")["networks"]["eth0"]
    tx = stats["tx_bytes"]
    rx = stats["rx_bytes"]
    [tx,rx]
end

end
