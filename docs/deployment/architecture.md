# 系统架构

本项目采用简单稳定的 Linux + Samba 独立服务器方案。

```text
Storage Server
├── Ubuntu Server
├── Samba 独立服务器
├── /srv/samba/users/<用户名>
├── Linux 用户权限
└── 文件系统用户配额

Node01 / Node02
├── Ubuntu Server
├── 本地 Linux 登录用户
├── cifs-utils
└── pam_mount 登录自动挂载
```

数据隔离由三层共同保证：

1. Samba 使用 `[homes]`，认证用户只能访问自己的同名共享目录。
2. 每个用户目录权限为 `0700`，属主为该用户。
3. Storage Server 使用文件系统用户配额限制每个用户可用空间。

该方案不依赖 Active Directory、LDAP、Kerberos、NFS、Docker 或 Kubernetes，部署和排错都更适合课程项目规模。
