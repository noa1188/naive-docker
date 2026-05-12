#!/usr/bin/env bash
set -e
set -u
set -o pipefail

exec 3>&1
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    ncolors=$(tput colors || echo 0)
    if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        normal="$(tput sgr0 || echo)"
        red="$(tput setaf 1 || echo)"
        yellow="$(tput setaf 3 || echo)"
        cyan="$(tput setaf 6 || echo)"
    fi
fi

say() {
    printf "%b\n" "${cyan:-}ray_naive_install:${normal:-} $1" >&3
}

say_err() {
    printf "%b\n" "${red:-}ray_naive_install: Error: $1${normal:-}" >&2
}

machine_has() {
    command -v "$1" >/dev/null 2>&1
}

check_docker() {
    if machine_has docker; then
        docker --version >&3
    else
        say_err "Missing dependency: docker was not found, please install it first."
        exit 1
    fi
}

extract_host_from_url() {
    local url="$1"
    url="${url#http://}"
    url="${url#https://}"
    url="${url%%/*}"
    url="${url%%:*}"
    printf '%s' "$url"
}

imageName="zai7lou/naiveproxy-docker"
host=""
mail=""
httpsPort=""
user=""
pwd=""
fakeHostDefault="https://demo.cloudreve.org"
fakeHost=""
cfApiToken=""

while [ $# -ne 0 ]; do
    name="$1"
    case "$name" in
        -t|--host|-Host)
            shift; host="$1" ;;
        -m|--mail|-Mail)
            shift; mail="$1" ;;
        -s|--https-port|-HttpsPort)
            shift; httpsPort="$1" ;;
        -u|--user|-User)
            shift; user="$1" ;;
        -p|--pwd|-Pwd)
            shift; pwd="$1" ;;
        -f|--fake-host|-FakeHost)
            shift; fakeHost="$1" ;;
        --cf-api-token|-CloudflareApiToken|-CfApiToken)
            shift; cfApiToken="$1" ;;
        --image|-Image)
            shift; imageName="$1" ;;
        -h|--help|-Help|-?)
            script_name="$(basename "$0")"
            cat <<USAGE
Ray Naiveproxy in Docker (Cloudflare DNS Challenge)
Usage: $script_name --host domain --mail mail@example.com --user xxx --pwd xxx --cf-api-token token [options]

Options:
  -t,--host              Domain name
  -m,--mail              Email for ACME
  -s,--https-port        HTTPS port, default 443
  -u,--user              Naive username
  -p,--pwd               Naive password
  -f,--fake-host         Camouflage site, default https://demo.cloudreve.org
  --cf-api-token         Cloudflare API Token
  --image                Docker image name, default zai7lou/naiveproxy-docker
USAGE
            exit 0 ;;
        *)
            say_err "Unknown argument: $name"
            exit 1 ;;
    esac
    shift
done

read_var_from_user() {
    if [ -z "$host" ]; then read -r -p "请输入域名(如 demo.example.com): " host; else say "域名: $host"; fi
    if [ -z "$mail" ]; then read -r -p "请输入邮箱(如 test@example.com): " mail; else say "邮箱: $mail"; fi
    if [ -z "$httpsPort" ]; then read -r -p "请输入 HTTPS 端口(默认 443): " httpsPort; [ -z "$httpsPort" ] && httpsPort="443"; else say "HTTPS 端口: $httpsPort"; fi
    if [ -z "$user" ]; then read -r -p "请输入节点用户名: " user; else say "节点用户名: $user"; fi
    if [ -z "$pwd" ]; then read -r -p "请输入节点密码: " pwd; else say "节点密码: 已读取"; fi
    if [ -z "$fakeHost" ]; then read -r -p "请输入伪装站点地址(默认 ${fakeHostDefault}): " fakeHost; [ -z "$fakeHost" ] && fakeHost="$fakeHostDefault"; else say "伪装站点地址: $fakeHost"; fi
    if [ -z "$cfApiToken" ]; then read -r -p "请输入 Cloudflare API Token: " cfApiToken; else say "Cloudflare API Token: 已读取"; fi

    fakeHostHost="$(extract_host_from_url "$fakeHost")"
    if [ -z "$fakeHostHost" ]; then
        say_err "无法从伪装站点地址中提取主机名: $fakeHost"
        exit 1
    fi
}

generate_docker_compose_file() {
    cat > ./docker-compose.yml <<EOF2
version: "3.8"

services:
  naive:
    image: ${imageName}
    container_name: naiveproxy
    tty: true
    restart: unless-stopped
    ports:
      - "${httpsPort}:443"
      - "${httpsPort}:443/udp"
    environment:
      - CLOUDFLARE_API_TOKEN=${cfApiToken}
    volumes:
      - ./data:/data
      - ./config:/config
      - ./share:/root/.local/share
    command: ["/bin/bash", "/data/entry.sh"]
EOF2

    say "Docker compose file:"
    cat ./docker-compose.yml >&3
}

generate_caddyfile() {
    cat > ./data/Caddyfile <<EOF2
{
    email ${mail}
    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    order forward_proxy before reverse_proxy
    order reverse_proxy before file_server
}

:443, ${host}:443 {
    tls {
        protocols tls1.2 tls1.3
        resolvers 1.1.1.1
    }

    forward_proxy {
        basic_auth ${user} ${pwd}
        hide_ip
        hide_via
        probe_resistance
    }

    reverse_proxy ${fakeHost} {
        header_up Host ${fakeHostHost}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Real-IP {remote_host}
        transport http {
            tls
            tls_server_name ${fakeHostHost}
        }
    }
}
EOF2

    say "Caddyfile:"
    cat ./data/Caddyfile >&3
}

generate_entry_sh() {
    cat > ./data/entry.sh <<'EOF2'
#!/usr/bin/env bash
set -e

echo "Format the Caddyfile"
caddy fmt --overwrite /data/Caddyfile

echo "Start server"
exec caddy run --config /data/Caddyfile --adapter caddyfile
EOF2
    chmod +x ./data/entry.sh

    say "entry.sh:"
    cat ./data/entry.sh >&3
}

prepare_files() {
    mkdir -p ./data ./config ./share
    generate_caddyfile
    generate_entry_sh
}

runContainer() {
    say "Try to run docker container..."
    if docker compose version >/dev/null 2>&1; then
        docker compose up -d
    elif machine_has docker-compose; then
        docker-compose up -d
    else
        docker run -itd --name naiveproxy \
            --restart=unless-stopped \
            -p "${httpsPort}:443" \
            -p "${httpsPort}:443/udp" \
            -e CLOUDFLARE_API_TOKEN="${cfApiToken}" \
            -v "$PWD/data:/data" \
            -v "$PWD/config:/config" \
            -v "$PWD/share:/root/.local/share" \
            "${imageName}" bash /data/entry.sh
    fi
}

check_result() {
    docker ps --filter "name=naiveproxy" >&3 || true
    containerId=$(docker ps -q --filter "name=^naiveproxy$")
    if [ -n "$containerId" ]; then
        echo "" >&3
        echo "===============================================" >&3
        echo "Congratulations! 恭喜！" >&3
        echo "创建并运行 naiveproxy 容器成功。" >&3
        echo "" >&3
        echo "请使用浏览器访问 'https://${host}:${httpsPort}'，验证是否可正常访问伪装站点" >&3
        echo "如异常，请运行 'docker logs -f naiveproxy' 查看日志" >&3
        echo "" >&3
        echo "客户端连接：" >&3
        echo "naive+https://${user}:${pwd}@${host}:${httpsPort}#naive" >&3
        echo "===============================================" >&3
    else
        echo "" >&3
        echo "容器可能未正常启动，以下是日志：" >&3
        echo "" >&3
        docker logs -f naiveproxy || true
    fi
}

main() {
    check_docker
    read_var_from_user
    generate_docker_compose_file
    prepare_files
    runContainer
    check_result
}

main
