#!/bin/bash

set -e

ZBX_SERVER="noc.jordan.cl"
ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"

deshabilitar_epel_zabbix() {
    local epel_repo="/etc/yum.repos.d/epel.repo"
    if [ -f "$epel_repo" ]; then
        echo "Verificando exclusión de Zabbix en $epel_repo..."
        if ! grep -q "^excludepkgs=zabbix*" "$epel_repo"; then
            echo "Agregando 'excludepkgs=zabbix*' a $epel_repo"
            echo -e "\n[epel]\nexcludepkgs=zabbix*" >> "$epel_repo"
        else
            echo "Ya existe exclusión de Zabbix en EPEL"
        fi
    fi
}

fix_centos7_mirrorlist() {
    local base_repo="/etc/yum.repos.d/CentOS-Base.repo"
    if [[ "$VERSION_ID_CLEAN" == "7" && -f "$base_repo" ]]; then
        echo "🔍 Verificando si es necesario reemplazar mirrorlist en CentOS 7..."
        if grep -q "^mirrorlist=" "$base_repo"; then
            echo "🛠 Reemplazando mirrorlist por vault.centos.org en $base_repo"
            sed -i.bak -e 's|^mirrorlist=|#mirrorlist=|g' \
                       -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/7.9.2009|g' "$base_repo"
        else
            echo "✅ mirrorlist ya fue reemplazado previamente o no es necesario."
        fi
    fi
}

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_ID_CLEAN=$(echo $VERSION_ID | cut -d'.' -f1)
    FULL_VERSION_ID=$(echo $VERSION_ID | tr -d '"')
else
    echo "No se puede detectar el sistema operativo."
    exit 1
fi

install_zabbix_agent_deb() {
    echo "Instalando Zabbix Agent para $DISTRO $FULL_VERSION_ID"
    wget -q "https://repo.zabbix.com/zabbix/7.4/release/$DISTRO/pool/main/z/zabbix-release/zabbix-release_latest_7.4+${DISTRO}${FULL_VERSION_ID}_all.deb"
    dpkg -i zabbix-release_latest_7.4+${DISTRO}${FULL_VERSION_ID}_all.deb
    apt update
    apt install -y zabbix-agent
}

install_zabbix_agent_rpm() {
    echo "Instalando Zabbix Agent para RHEL/CentOS $VERSION_ID_CLEAN"

    if [[ "$VERSION_ID_CLEAN" == "9" || "$VERSION_ID_CLEAN" == "10" ]]; then
        deshabilitar_epel_zabbix
    fi

    if [ "$VERSION_ID_CLEAN" -eq 7 ]; then
        fix_centos7_mirrorlist
        REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/rhel/7/noarch/zabbix-release-latest-7.4.el7.noarch.rpm"
    else
        REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/centos/$VERSION_ID_CLEAN/noarch/zabbix-release-latest-7.4.el${VERSION_ID_CLEAN}.noarch.rpm"
    fi

    echo "📥 Descargando repo desde $REPO_URL"
    curl -k -o /tmp/zabbix-release.rpm "$REPO_URL"
    rpm -Uvh /tmp/zabbix-release.rpm || echo "⚠️ El repo ya estaba instalado"

    if [ "$VERSION_ID_CLEAN" -eq 7 ]; then
        yum clean all
        yum install -y zabbix-agent || echo "⚠️ Ya instalado o falló, intenta verificar manualmente"
    else
        dnf clean all
        dnf install -y zabbix-agent || echo "⚠️ Ya instalado o falló, intenta verificar manualmente"
    fi
}

configurar_zabbix() {
    echo "Configurando Zabbix Agent..."

    if [ ! -f "$ZBX_CONF" ]; then
        echo "❌ No se encontró $ZBX_CONF. Verificando si el paquete se instaló correctamente..."
        echo "Creando archivo básico de configuración..."
        mkdir -p /etc/zabbix
        cat <<EOF > "$ZBX_CONF"
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
Server=${ZBX_SERVER}
ServerActive=${ZBX_SERVER}
Hostname=$(hostname)
Include=/etc/zabbix/zabbix_agentd.d/*.conf
EOF
    else
        sed -i "s|^Server=.*|Server=${ZBX_SERVER}|" "$ZBX_CONF" || echo "Server=${ZBX_SERVER}" >> "$ZBX_CONF"
        sed -i "s|^ServerActive=.*|ServerActive=${ZBX_SERVER}|" "$ZBX_CONF" || echo "ServerActive=${ZBX_SERVER}" >> "$ZBX_CONF"
        sed -i "s|^Hostname=.*|Hostname=$(hostname)|" "$ZBX_CONF" || echo "Hostname=$(hostname)" >> "$ZBX_CONF"
    fi
}

case "$DISTRO" in
    ubuntu|debian)
        install_zabbix_agent_deb
        ;;
    centos|rhel|almalinux|rocky)
        install_zabbix_agent_rpm
        ;;
    *)
        echo "Distribución no soportada: $DISTRO"
        exit 1
        ;;
esac

configurar_zabbix

echo "Reiniciando y habilitando Zabbix Agent..."
systemctl enable --now zabbix-agent

echo -e "\n✅ Zabbix Agent instalado y configurado correctamente para el servidor $ZBX_SERVER con hostname $(hostname)"
echo "Revisa el archivo de configuración en $ZBX_CONF y los logs en /var/log/zabbix/zabbix_agentd.log"