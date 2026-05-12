# Naive Docker 部署说明

这个项目提供了一个基于 Caddy 自定义构建的镜像，内置 Naive 所需的 `forwardproxy@naive` 模块，并可选配 Cloudflare DNS challenge 能力。[web:77][web:54] 镜像可以直接从 Docker Hub 拉取部署，也可以配合 `docker compose` 或安装脚本使用。[web:246][web:244]

## 镜像说明

镜像在构建时会写入 OCI labels，用于记录镜像版本、Git 提交以及上游 `klzgrad/naiveproxy` release 版本，便于后续追踪。[web:184][web:187] 这类元数据可以通过 `docker inspect` 直接读取，而不需要进入容器内部查看。[web:244]

将下面的镜像名替换为实际仓库名：

```bash
docker pull yourdockerhubusername/naiveproxy-docker:latest
```

如果部署环境强调稳定性，建议优先使用明确版本号 tag，而不是长期只跟 `latest`，因为明确 tag 更利于回滚和排障。[web:246][web:252]

## Docker 直接运行

先准备目录：

```bash
mkdir -p naive-docker/{data,config,share}
cd naive-docker
```

准备 `data/entry.sh`：

```bash
cat > data/entry.sh <<'SH'
#!/usr/bin/env bash
set -e

caddy fmt --overwrite /data/Caddyfile
exec caddy run --config /data/Caddyfile --adapter caddyfile
SH
chmod +x data/entry.sh
```

再准备 `data/Caddyfile`，将下面示例中的域名、用户名、密码和伪装站点替换为自己的值：

```caddyfile
{
    email you@example.com
}

your.domain.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    route {
        forward_proxy {
            basic_auth username password
            hide_ip
            hide_via
            probe_resistance https://www.cloudflare.com/
        }

        reverse_proxy https://www.cloudflare.com {
            header_up Host {upstream_hostport}
        }
    }
}
```

启动容器：

```bash
docker run -d \
  --name naiveproxy \
  -p 443:443 \
  -p 443:443/udp \
  -e CLOUDFLARE_API_TOKEN='your_cloudflare_token' \
  -v "$PWD/data:/data" \
  -v "$PWD/config:/config" \
  -v "$PWD/share:/root/.local/share" \
  yourdockerhubusername/naiveproxy-docker:latest
```

如果宿主机的 443 已被占用，可以把左侧宿主机端口改成其他值，例如 `-p 8443:443`；这能解决本机端口冲突，但公网证书签发是否可用仍取决于你的流量入口与验证方式。[web:244][web:77]

## Docker Compose

也可以使用 `docker compose`：

```yaml
services:
  naiveproxy:
    image: yourdockerhubusername/naiveproxy-docker:latest
    container_name: naiveproxy
    restart: unless-stopped
    environment:
      CLOUDFLARE_API_TOKEN: your_cloudflare_token
    ports:
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./data:/data
      - ./config:/config
      - ./share:/root/.local/share
```

启动命令：

```bash
docker compose up -d
```

Compose 方式的优势是后续升级和回滚更方便，只需要修改镜像 tag 并重新拉取即可。[web:246][web:252]

## 查看镜像元数据

查看这次镜像记录的 Naive 上游版本：

```bash
docker inspect yourdockerhubusername/naiveproxy-docker:latest \
  --format '{{ index .Config.Labels "org.opencontainers.image.naiveproxy.upstream-version" }}'
```

查看全部 labels：

```bash
docker inspect yourdockerhubusername/naiveproxy-docker:latest | jq '.[0].Config.Labels'
```

这类 label 适合用于核对构建来源、镜像版本和上游 release 记录，也是 Docker 推荐的镜像元数据管理方式之一。[web:184][web:246]

## 启动后检查

查看 Caddy 版本：

```bash
docker run --rm yourdockerhubusername/naiveproxy-docker:latest caddy version
```

查看是否包含 Cloudflare 与 forward proxy 模块：

```bash
docker run --rm yourdockerhubusername/naiveproxy-docker:latest caddy list-modules | grep -E 'cloudflare|forward_proxy'
```

查看容器日志：

```bash
docker logs -f naiveproxy
```

如果日志中已经出现证书申请、配置加载成功或监听端口成功的信息，通常说明镜像和挂载文件已正常工作。[web:162][web:77]

## 升级镜像

如果使用 `docker run`：

```bash
docker pull yourdockerhubusername/naiveproxy-docker:latest
docker rm -f naiveproxy
docker run -d \
  --name naiveproxy \
  -p 443:443 \
  -p 443:443/udp \
  -e CLOUDFLARE_API_TOKEN='your_cloudflare_token' \
  -v "$PWD/data:/data" \
  -v "$PWD/config:/config" \
  -v "$PWD/share:/root/.local/share" \
  yourdockerhubusername/naiveproxy-docker:latest
```

如果使用 `docker compose`：

```bash
docker compose pull
docker compose up -d
```

生产环境建议固定到明确版本号 tag，确认新版本可用后再切换，避免 `latest` 在未知时间点引入变化。[web:246][web:252]
