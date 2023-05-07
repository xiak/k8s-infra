# Integrate ceph with kubernetes

## ceph filesystem

获取 mount 需要的 secret

```
mkdir /cephfs
secret_string=$(ceph auth get-key client.admin)
mount -t ceph  10.10.10.101:6789:/ /cephfs/ -o name=admin,secret=${secret_string}
mount -t ceph  10.10.10.101:6789,10.10.10.102:6789,10.10.10.103:6789:/ /ceph/ -o name=admin,secret=AQCgKjVfXYbzKBAABOQ0Ii4iS0OsbUB4lmLb8w==
```

## how to get secret key

获取 kubernetes 需要的 secret, 区别是要经过 base64 转码

```
ceph auth get-key client.admin | base64
```


通过 `kubernetes secret` 存储 `ceph auth key`
```
cat ceph.client.admin.keyring 2>&1 |grep "key = " |awk '{print  $3'} |xargs echo -n > ceph.admin.secret
```


```
kubectl create secret generic ceph-admin-secret --from-file=ceph.admin.secret --namespace=kube-system
```

