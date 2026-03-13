resource "aws_eip" "lab_relay" {
  instance   = aws_instance.lab_relay.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.default]

  tags = {
    Name = "${local.name}-lab-relay"
  }
}

resource "aws_instance" "lab_relay" {
  ami                         = data.aws_ami.minimal-arm64.id
  availability_zone           = local.availability_zone
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public.id
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  vpc_security_group_ids      = [aws_security_group.lab_relay.id]
  source_dest_check           = false
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 4
  }

  user_data = base64encode(<<-INIT
    #!/bin/bash
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    amazon-linux-extras install epel -y
    yum install -y openvpn easy-rsa

    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # Set up PKI using elliptic curve (avoids slow DH param generation)
    EASYRSA_SRC=$(find /usr/share/easy-rsa -name "easyrsa" | head -1 | xargs dirname)
    mkdir -p /etc/openvpn/easy-rsa
    cp -r $EASYRSA_SRC/* /etc/openvpn/easy-rsa/
    cd /etc/openvpn/easy-rsa

    export EASYRSA_BATCH=1
    export EASYRSA_ALGO=ec
    export EASYRSA_CURVE=prime256v1

    ./easyrsa init-pki
    ./easyrsa build-ca nopass
    ./easyrsa build-server-full server nopass
    ./easyrsa build-client-full client nopass
    ./easyrsa build-client-full chr nopass

    # CCD for CHR: route lab subnets through CHR
    mkdir -p /etc/openvpn/ccd
    cat > /etc/openvpn/ccd/chr <<'CCD'
    iroute 192.168.88.0 255.255.255.0
    iroute 192.168.1.0 255.255.255.0
    CCD

    # Server config
    cat > /etc/openvpn/server/server.conf <<'CONF'
    port 1194
    proto udp
    dev tun
    ca /etc/openvpn/easy-rsa/pki/ca.crt
    cert /etc/openvpn/easy-rsa/pki/issued/server.crt
    key /etc/openvpn/easy-rsa/pki/private/server.key
    dh none
    cipher AES-256-GCM
    auth SHA256
    server 10.8.0.0 255.255.255.0
    client-config-dir /etc/openvpn/ccd
    route 192.168.88.0 255.255.255.0
    route 192.168.1.0 255.255.255.0
    push "route 192.168.88.0 255.255.255.0"
    push "route 192.168.1.0 255.255.255.0"
    keepalive 10 120
    persist-key
    persist-tun
    verb 3
    CONF

    # NAT for VPN clients
    cat <<EOF > /etc/systemd/system/openvpn-nat.service
    [Unit]
    Description=OpenVPN NAT
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    ExecStop=/usr/sbin/iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable openvpn-nat
    systemctl start openvpn-nat

    systemctl enable openvpn-server@server
    systemctl start openvpn-server@server

    # Build the shareable client config with all certs embedded
    cat > /etc/openvpn/client.ovpn <<'OVPN'
    client
    dev tun
    proto udp
    remote vpn.${local.domain} 1194
    resolv-retry infinite
    nobind
    persist-key
    persist-tun
    remote-cert-tls server
    cipher AES-256-GCM
    auth SHA256
    verb 3
    <ca>
    OVPN
    cat /etc/openvpn/easy-rsa/pki/ca.crt >> /etc/openvpn/client.ovpn
    echo "</ca>" >> /etc/openvpn/client.ovpn
    echo "<cert>" >> /etc/openvpn/client.ovpn
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /etc/openvpn/easy-rsa/pki/issued/client.crt >> /etc/openvpn/client.ovpn
    echo "</cert>" >> /etc/openvpn/client.ovpn
    echo "<key>" >> /etc/openvpn/client.ovpn
    cat /etc/openvpn/easy-rsa/pki/private/client.key >> /etc/openvpn/client.ovpn
    echo "</key>" >> /etc/openvpn/client.ovpn
    INIT
  )

  tags = {
    Name = "${local.name}-lab-relay"
  }
}

resource "aws_security_group" "lab_relay" {
  name   = "${local.name}-lab-relay"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port        = 1194
    to_port          = 1194
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_route53_record" "wireguard" {
  zone_id = local.domain_zone_id
  name    = "vpn.${local.domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.lab_relay.public_ip]
}
