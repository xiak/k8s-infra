# Kubernetes NFS-Client Provisioner

## 前提

- `Kubernetes >=1.9, <1.20`
- `Existing NFS Share`

## 用途

`Kubernetes NFS-Client Provisioner` 它是一个 nfs client, 为 kubernetes 动态提供访问 NFS 后端存储的能力，它本身不提供 nfs server 存储, 而是去访问已经配置好的 nfs server

## 准备

查看待 mount 的 NFS 的 mount 路径

```shell
$ showmount -e test.example.com
Export list for test.example.com:
/share       aaaaaaaaaaaaaaaa
/home        bbbbbbbbbbbbbbbb
/export      xxxxxxxxxxxxxxxx
/depot       yyyyyyyyyyyyyyyy
/export/repo zzzzzzzzzzzzzzzz
```

这里需要注意下, 在我的 bastion 机器上 /depot 是可以用的, 但是 /export 路径不能 mount 

不过在 k8s worker 上, /export 可用, /depot 反而不可用, 所以这里我们确定路径为 /export

## 安装

使用 `helm` 安装

```shell
$ git clone https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git
$ cd nfs-subdir-external-provisioner/deploy/helm/
$ ls
Chart.yaml  ci  README.md  templates  values.yaml
$ helm install nfs-subdir-external-provisioner . \
    --set nfs.server=x.x.x.x \
    --set nfs.path=/exported/path
```

有两种方法可以设置配置文件:
1. 编辑 `values.yaml`
2. 使用命令行中的 `--set` 来动态设置 `values.yaml` 中的参数

在这里我们使用第二种方法

```shell
$ helm install nfs-provisioner -n ops -f values.yaml . \
    --set nfs.server=test.example.com \
    --set nfs.path=/export
    
NAME: nfs-provisioner
LAST DEPLOYED: Tue Feb  2 18:23:24 2021
NAMESPACE: ops
STATUS: deployed
REVISION: 1
TEST SUITE: None

$ kubectl get pod -n ops
NAME                                                              READY   STATUS              RESTARTS   AGE
nfs-provisioner-nfs-subdir-external-provisioner-65969c88c7bq2p9   1/1     Running             0          18s
```

- `-n ops` 表示把 nfs-provisioner 安装到 `ops` 命名空间里
- `nfs.server` 表示 NFS 服务器地址
- `nfs.path` 表示 NFS 服务器上我们想访问的路径

具体配置的 API 见 [这里](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/blob/master/deploy/helm/README.md)

需要注意: 如果 pod 创建失败, 查看 log 发现 `Protocol not supported mount.nfs`

可能的问题是
1. mount 点不对
2. nfs 版本不对, 需要指定版本 `mount -t nfs -o vers=3 test.example.com:/depot /mnt/`

## 原理

当执行 `helm install` 后，会执行以下步骤让我们的 pod 能够访问 NFS

1. 创建 RBAC 授权
2. 在 kubernetes 集群中安装 `storage class` (简称sc), 默认 sc 名字可以查看 `values.yaml` 中的 `storageClass.name`
3. 在 kubernetes 激情中安装 `NFS client provisioner`, 它以服务的形式运行在 kubernetes 中, 为集群提供动态访问 NFS 后端存储的能力

## 使用

## 卸载

使用 `helm` 卸载
```shell
helm delete nfs-provisioner -n ops
```

