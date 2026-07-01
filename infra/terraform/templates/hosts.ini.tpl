[server]
${server_public_ip} k3s_private_ip=${server_private_ip}

[agents]
%{ for idx, ip in agent_public_ips ~}
${ip} k3s_private_ip=${agent_private_ips[idx]}
%{ endfor ~}

[all:vars]
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
k3s_server_private_ip=${server_private_ip}
