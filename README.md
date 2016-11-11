# Table of Contents

1. [Overview](https://github.com/gsd-ufal/Infra.jl#overview)
1. [Installation](https://github.com/gsd-ufal/Infra.jl#installation)
2. [Usage](https://github.com/gsd-ufal/Infra.jl#usage)
3. [Tests](https://github.com/gsd-ufal/Infra.jl#tests)
4. [Documentation](https://github.com/gsd-ufal/Infra.jl#documentation)

https://github.com/gsd-ufal/Infra.jl/tree/tests/tests

# Overview

This repository is part of [CloudArray](https://github.com/gsd-ufal/CloudArray.jl) project

Infra.jl books virtual machines (VMs) and creates, configures, and instantiates Docker containers on top of VMs. Then Julia Workers are configured and deployed on containers. 

# Installation

### Requirements

#### Julia 0.4

[Download Julia 0.4](http://julialang.org/downloads/)

#### sshpass

Debian-based Linux distros as Ubuntu or through 

```
sudo apt-get install sshpass 
```

OS X through [macports](http://macports.org):

```
sudo port install sshpass
```

# Usage

First load Infra package:

```Julia
using Infra
```
Then tell Infra.jl the machine address and the password to passwordless SSH login:

```Julia
Infra.set_host(host_address,ssh_password)
```

To use VMs to test Infra.jl use the following parameters:

```Julia
Infra.set_host("cloudarray.ddns.net","cloudarray@")
```

Now, you can create julia workers inside containers

```Julia
Infra.create_containers(1,1,512)
```

# Tests

Script tests can be found [here](https://github.com/gsd-ufal/Infra.jl/tree/tests/tests).

# Documentation

### set_host(h::AbstractString,p::AbstractString)

Configures passwordless SSH connections at host `h` whose password is `p`.

This function calls the `cloud_setup.sh` script which requires `sshpass`.

```Example
set_host("cloudarray.cloudapp.net","password")
```

### create_containers(n_of_containers::Integer, n_of_cpus::Integer, mem_size::Integer)
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

### delete_containers(args...)
Removes the specified container(s)/worker(s).

```Example
delete_containers(3)    # delete container 3
create_containers(1:5)  # delete from 1st to 5th container
create_containers(all)  # delete all containers
```

### containers()
Returns the list of all containers' processes identifiers (IDs).

```Example
containers()
```

### ncontainers()
Gets the number of available container processes.

```Example
ncontainers()
```

### list_containers()

List container(s) as a sorted list.

```Example
list_containers()
```

### mem_usage(key::Integer)
Returns the container memory usage.

```Example
mem_usage(number_of_container)
```

### cpu_usage(key::Integer)
Returns the container CPU usage (%).

```Example
cpu_usage(number_of_container)
```

### io_usage(key::Integer)
Returns the number of kilobytes read and written by the cgroup.

```Example
io_usage(number_of_container)
```

### net_usage(key::Integer)
Returns networking TX/RX usage.

tx = number of bytes transmitted

rx = number of bytes reiceved

```Example
net_usage(number_of_container)
```
