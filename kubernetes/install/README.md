# 自动化安装高性能高可用 kubernetes 集群

## 目录
- 前提
- 第一步 集群规划
- 第二步 安装 Loadbalancer 集群
- 第三步 安装独立的 ETCD 集群
- 第四步 创建 kubernetes api 节点
- 第五步 安装网络插件
- 第六步 添加节点到创建好的集群中

## 前提

1 下载 repo
```shell script
git clone https://github.com/xiak/k8s-infra.git
```

整个工程的目录结构如下

```
kubernetes
  |- doc
  |- install           (脚手架)
  |- namespace         (一些常用的应用)
  |- network           (ingress 插件)
  |- storage           (后端存储)
```

2 本文将带领大家安装一个高可用的 `k8s` 集群, 最少需要 `11` 台机器(虚拟机或物理机都可以)

|  类型   | 系统  |
|  ----  | ----  |
| etcd  | centos 7 min |
| etcd  | centos 7 min |
| etcd  | centos 7 min |
| soft loadbalancer  | centos 7 min |
| soft loadbalancer  | centos 7 min |
| soft loadbalancer  | centos 7 min |
| kubernetes master  | centos 7 min |
| kubernetes master  | centos 7 min |
| kubernetes master  | centos 7 min |
| kubernetes worker  | centos 7 min |
| kubernetes bastion  | centos 7 min |

- `3` 台 `k8s` 集群外 `etcd cluster`
- `3` 台由 `haproxy + keepalived` 组成的 `soft loadbalancer`
- `3` 台 `k8s master` 节点, 每台节点上分别包含 `kube-apiserver`, `kube-contorller-manager`, `kube-scheduler` 三个服务
- `1` 至少 `1` 台干活的节点 `k8s worker`
- `1` 台跳板机, 所有人访问集群, 必须通过此跳板机

如果资源紧张, 可以去掉 `soft loadbalancer`, 可以把 `etcd` 和 `kubernetes master` 安装在同一台服务器上, 这种情况本文不作阐述

> 接下来所有步骤默认目录都是 `kubernetes/install/`

## 第一步 集群规划

在脚本 `install-etc-hosts.sh` 中定义你的集群

格式为 `IP 主机名`, 主机名最好能够一目了然得看出主机的用途

```shell script
function make::etchosts {
    ......
    cat > "${conf_file}" << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.10.10.2       k8s-bastion            root     password
10.10.10.6       k8s-master-1           root     password
10.10.10.7       k8s-master-2           root     password
10.10.10.8       k8s-master-3           root     password
10.10.10.9       k8s-slb-1              root     password
10.10.10.10      k8s-slb-2              root     password
10.10.10.11      k8s-slb-3              root     password
10.10.10.3       k8s-etcd-1             root     password
10.10.10.4       k8s-etcd-2             root     password
10.10.10.5       k8s-etcd-3             root     password
10.10.10.101     k8s-ceph-1             root     password
10.10.10.102     k8s-ceph-2             root     password
10.10.10.103     k8s-ceph-3             root     password
10.10.10.104     k8s-ceph-4             root     password
10.10.10.105     k8s-ceph-5             root     password
10.10.10.106     k8s-ceph-6             root     password
10.10.10.107     k8s-report             root     password
10.10.10.108     k8s-dnd                root     password
10.10.10.109     k8s-cp                 root     password
10.10.10.110     k8s-dp                 root     password
10.10.10.111     k8s-dash               root     password
10.10.10.112     k8s-ceph-dashboard     root     password
10.10.10.113     k8s-git                root     password
10.10.10.114     k8s-hub                root     password
10.10.10.115     k8s-infra              root     password
EOF
    ......
}
```

除此之外, 集群会使用 `10.10.10.100` 作为 `loadbalancer` 的 ip, 在 `第二步` 中会用到


## 第二步 安装 Loadbalancer 集群

在第一步中定义了三台主机来作为负载均衡的节点:
```shell script
10.10.10.9    k8s-slb-1
10.10.10.10   k8s-slb-2
10.10.10.11   k8s-slb-3
```
在第一步中定义了三台主机作为 etcd 集群
```shell script
10.10.10.3    k8s-etcd-1
10.10.10.4    k8s-etcd-2
10.10.10.5    k8s-etcd-3
```
在第一步中定义了三台主机作为 kubernetes api server
```shell script
10.10.10.6    k8s-master-1
10.10.10.7    k8s-master-2
10.10.10.8    k8s-master-3
```

确保所有主机配置好了 IP 和 主机名


创建一个 `Loadbalancer IP=10.10.10.100` 作为 ETCD 和 Kubernetes 的外部访问接口:
```shell script
install-slb.sh root password 10.10.10.100 ens160 "10.10.10.6 10.10.10.7 10.10.10.8" "10.10.10.3 10.10.10.4 10.10.10.5" 10.10.10.9 10.10.10.10 10.10.10.11
```

访问 https://10.10.10.100:8443 即可访问 kubernetes api servers
访问 https://10.10.10.100:2379 即可访问 ETCD CLUSTER

> NOTE: IP 地址 `10.10.10.100` 是一个 VIP, 而不是真实的一台服务器

## 第三步 安装独立的 ETCD 集群

在第一步中定义了三台主机作为 etcd 集群
```shell script
10.10.10.3    k8s-etcd-1
10.10.10.4    k8s-etcd-2
10.10.10.5    k8s-etcd-3
```

创建一个 `ETCD (version: 3.4.3)` 集群, `kubernetes` 可以通过负载均衡器访问 `ETCD` 集群 `VIP 10.10.10.100:2379 or cluster-vip.com:2379`

```shell script
install-etcd.sh root password 3.4.3 cluster-vip.com 10.10.10.100 /etc/etcd 10.10.10.3 10.10.10.4 10.10.10.5
```

> 其中需要注意的是, 如果上某台服务器上曾经安装过 etcd, 则需要先卸载, 需执行如下命令
> ```shell script
> uninstall-etcd.sh root password /etc/etcd /usr/local/bin 10.10.10.3 10.10.10.4 10.10.10.5
> ```
> 卸载完成后再执行如下命令安装 `ETCD` 集群
> ```shell script
> install-etcd.sh root password 3.4.3 cluster-vip.com 10.10.10.100 /etc/etcd 10.10.10.3 10.10.10.4 10.10.10.5
> ```

## 第四步 创建 kubernetes master 节点

在第一步中定义了三台主机作为 `kubernetes master`
```shell script
10.10.10.6    k8s-master-1
10.10.10.7    k8s-master-2
10.10.10.8    k8s-master-3
```

首先创建集群中第一台 `kubernetes master`, 剩下的我们可以以后再添加

- IP: 10.10.10.6
- Role: master
- Kubernetes Version: 1.16.2
- Docker Version: 18.09.7
- Docker Registry: hub.docker.com
- Kubernetes API Server VIP: 10.10.10.100:8443
- ETCD Cluster VIP: 10.10.10.100:2379
- One of ETCD Server IP: 10.10.10.3
- ETCD Cert Path: /etc/etcd/pki on 10.10.10.3
- Network Proxy: IPVS
- NTP Servers: 10.10.10.9, 10.10.10.10, 10.10.10.11

```shell script
install-k8s.sh 10.10.10.6 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 10.10.10.3 "" new master ipvs systemd hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11
```

> 其中需要注意的是, 如果 10.10.10.6 上曾经安装过 kubernetes, 则需要先卸载
> ```shell script
> uninstall-k8s.sh root password true true 10.10.10.6 10.10.10.7 10.10.10.8
> ```
> 再执行
> ```shell script
> install-k8s.sh 10.10.10.6 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 10.10.10.3 "" new master ipvs systemd hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11
> ```

## 第五步 安装网络插件

calico 插件用到了 ETCD 集群, 我们需要再看下创建好的 ETCD 集群信息

```shell script
10.10.10.3    k8s-etcd-1
10.10.10.4    k8s-etcd-2
10.10.10.5    k8s-etcd-3
```

安装 calico 网络插件

> 其中 `calico-template.yaml` 为配置文件模板, `https://10.10.10.100:2379` 为 `ETCD` 负载均衡地址

```shell script
install-calico.sh 10.10.10.3 root password https://10.10.10.100:2379 /etc/etcd/pki 10.10.0.0/24 calico-template.yaml
```

如果不使用负载均衡 VIP 节点， 也可以使用如下命令安装 calico
```shell script
install-calico.sh 10.10.10.3 root password https://10.10.10.3:2379,https://10.10.10.4:2379,https://10.10.10.5:2379 /etc/etcd/pki 10.10.0.0/24 calico-template.yaml
```

## 第六步 添加节点到创建好的集群中

在`第四步`中, 我们创建好了第一台 kubernetes 节点

现在我们会把一台 kubernetes 控制节点和一台工作节点加入到集群中

```shell script
10.10.10.7    k8s-master-2
10.10.10.23   k8s-worker-1
```

### 控制节点加入集群

```shell script
install-k8s.sh 10.10.10.7 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 etcd-first-node.com k8s-first-node.com join master ipvs hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11
```

### 工作节点加入集群

```shell script
install-k8s.sh 10.10.10.23 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 etcd-first-node.com k8s-first-node.com join worker ipvs hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11
```

> NOTE: `etcd-first-node.com` 表示任意的一台 `etcd` 节点的 `ip` (10.10.10.3 or ...),  `k8s-first-node.com` 表示集群中的任意 `kubernetes master` 节点的 `ip` (可选集群第一个节点 10.10.10.6)


## 结语

至此我们的一个高可用 kubernetes 集群搭建完毕，如果大家有什么意见或者建议，请提 `pr` , 如发现 `bug` 请提交 `issue`

联系方式: `x@xiak.com`



