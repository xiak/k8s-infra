# 

用法

```shell script
kubectl apply -f . -n ops
```

mysql -u root -p

如果是非 root 用户连接 mysql

CREATE DATABASE `gitea` DEFAULT CHARACTER SET `utf8mb4` COLLATE `utf8mb4_unicode_ci`;
CREATE USER `gitea`@'localhost' IDENTIFIED BY 'password';

CREATE USER `gitea`@'%' IDENTIFIED BY 'CHANGE';
GRANT ALL PRIVILEGES ON *.* TO `gitea`@'%';
# set password for 'gitea'@'localhost'=password('CHANGE');




CREATE DATABASE IF NOT EXISTS gitea DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON `gitea`.* TO `gitea`@'%';
flush privileges;