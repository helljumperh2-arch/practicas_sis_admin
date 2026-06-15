SSH(){
    local servicio="openssh-server"
    mon_servicer $servicio
    systemctl enable ssh > /dev/null 2>&1
    systemctl start ssh > /dev/null 2>&1
	echo -e " [*] SSH Arrancado y configurado para que incie en boot ";
    local ip_admin=$(ip addr show enp0s3 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    
    echo -e " [*] SSH activo..."
    echo "Conéctate desde cliente: ssh $USER@$ip_admin"
}
