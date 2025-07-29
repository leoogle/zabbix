#!/bin/bash

set -e

ZBX_SERVER="noc.jordan.cl"
ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"

# Función para desactivar Zabbix desde EPEL (CentOS/RHEL 9+)
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

# Detectar distribución
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
        REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/rhel/7/noarch/zabbix-release-latest-7.4.el7.noarch.rpm"
        rpm -Uvh "$REPO_URL"
        yum clean all
        yum install -y zabbix-agent
    else
        REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/centos/$VERSION_ID_CLEAN/noarch/zabbix-release-latest-7.4.el${VERSION_ID_CLEAN}.noarch.rpm"
        rpm -Uvh "$REPO_URL"
        dnf clean all
        dnf install -y zabbix-agent
    fi
}

configurar_zabbix() {
    echo "Configurando Zabbix Agent..."

    if [ ! -f "$ZBX_CONF" ]; then
        echo "❌ No se encontró el archivo $ZBX_CONF"
        exit 1
    fi

    sed -i "s|^Server=.*|Server=${ZBX_SERVER}|" "$ZBX_CONF" || echo "Server=${ZBX_SERVER}" >> "$ZBX_CONF"
    sed -i "s|^ServerActive=.*|ServerActive=${ZBX_SERVER}|" "$ZBX_CONF" || echo "ServerActive=${ZBX_SERVER}" >> "$ZBX_CONF"
    sed -i "s|^Hostname=.*|Hostname=$(hostname)|" "$ZBX_CONF" || echo "Hostname=$(hostname)" >> "$ZBX_CONF"
}

# Dispatcher
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
