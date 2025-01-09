#cloud-boothook
#!/bin/bash

echo ECS_CLUSTER=${ecs_cluster} > /etc/ecs/ecs.config
echo ECS_AWSVPC_BLOCK_IMDS=true >> /etc/ecs/ecs.config

yum install iptables-services -y

cat <<EOF > /etc/sysconfig/iptables 
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -d 169.254.169.254/32 -j DROP
-A DOCKER-USER -d 169.254.170.2/32 -j DROP
COMMIT
EOF

systemctl enable iptables && systemctl start iptables
