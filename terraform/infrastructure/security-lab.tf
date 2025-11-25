# =============================================================================
# Security Lab Infrastructure
# Ubuntu Desktop (target) + Kali Linux (attacker) for offensive/defensive testing
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu_desktop" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Ubuntu base for attacker box (with Kali tools installed via user-data)
data "aws_ami" "ubuntu_attacker" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "security_lab" {
  key_name   = "security-lab-key"
  public_key = var.ssh_public_key

  tags = {
    Name    = "Security Lab SSH Key"
    Purpose = "Security testing and administration"
  }
}

# -----------------------------------------------------------------------------
# Security Groups - Defense in Depth
# -----------------------------------------------------------------------------

# Security group for Kali (attacker box)
resource "aws_security_group" "kali_attacker" {
  name        = "security-lab-kali-attacker"
  description = "Security group for Kali Linux attack platform"
  vpc_id      = data.aws_vpc.default.id

  # SSH access from your IP only (configure in terraform.tfvars)
  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # RDP/VNC for remote desktop (optional, from admin only)
  ingress {
    description = "RDP from admin"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # VNC access
  ingress {
    description = "VNC from admin"
    from_port   = 5900
    to_port     = 5910
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # Allow all outbound (needed for updates and attacks to target)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Kali Attacker SG"
    Purpose     = "Offensive security testing"
    Environment = var.environment
  }
}

# Security group for Ubuntu target (intentionally more permissive from Kali only)
resource "aws_security_group" "ubuntu_target" {
  name        = "security-lab-ubuntu-target"
  description = "Security group for Ubuntu target machine - allows access from Kali only"
  vpc_id      = data.aws_vpc.default.id

  # SSH from admin for initial setup
  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # RDP access from admin for remote desktop
  ingress {
    description = "RDP from admin"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # VNC access from admin
  ingress {
    description = "VNC from admin"
    from_port   = 5900
    to_port     = 5910
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # Allow ALL traffic from Kali (for security testing scenarios)
  # This enables realistic attack simulations
  ingress {
    description     = "All traffic from Kali attacker"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.kali_attacker.id]
  }

  # Outbound - Allow traffic to Kali (for reverse shells, etc.)
  egress {
    description     = "Traffic to Kali for reverse connections"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.kali_attacker.id]
  }

  # Limited internet for updates (optional - can restrict further)
  egress {
    description = "HTTPS for package updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Ubuntu Target SG"
    Purpose     = "Defensive security testing target"
    Environment = var.environment
    Warning     = "Intentionally permissive for lab use"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for EC2 with SSM Access (for secure management)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "security_lab_instance" {
  name        = "security-lab-instance-role"
  description = "Role for security lab EC2 instances with SSM access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "Security Lab Instance Role"
    Purpose = "EC2 SSM management access"
  }
}

# SSM Core for Session Manager access (more secure than SSH over internet)
resource "aws_iam_role_policy_attachment" "security_lab_ssm" {
  role       = aws_iam_role.security_lab_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent for monitoring
resource "aws_iam_role_policy_attachment" "security_lab_cloudwatch" {
  role       = aws_iam_role.security_lab_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "security_lab" {
  name = "security-lab-instance-profile"
  role = aws_iam_role.security_lab_instance.name

  tags = {
    Name = "Security Lab Instance Profile"
  }
}

# -----------------------------------------------------------------------------
# Ubuntu Desktop (Target Machine)
# -----------------------------------------------------------------------------

resource "aws_instance" "ubuntu_target" {
  ami                    = data.aws_ami.ubuntu_desktop.id
  instance_type          = var.security_lab_instance_type
  key_name               = aws_key_pair.security_lab.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ubuntu_target.id]
  iam_instance_profile   = aws_iam_instance_profile.security_lab.name

  # Enable detailed monitoring for security observability
  monitoring = true

  # Disable IMDSv1 for security (require IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "Ubuntu Target Root Volume"
    }
  }

  # User data to install Ubuntu Desktop and configure for remote access
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex

    # Update and install desktop environment
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    # Install Ubuntu Desktop (minimal for remote access)
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ubuntu-desktop-minimal \
      xrdp \
      tigervnc-standalone-server \
      tigervnc-common \
      dbus-x11

    # Configure xrdp
    systemctl enable xrdp
    adduser xrdp ssl-cert

    # Create a lab user for testing
    useradd -m -s /bin/bash labuser
    echo "labuser:LabPassword123!" | chpasswd
    usermod -aG sudo labuser

    # Install common security testing targets (vulnerable services for practice)
    apt-get install -y \
      openssh-server \
      apache2 \
      mysql-server \
      vsftpd \
      net-tools \
      nmap \
      tcpdump \
      wireshark \
      fail2ban

    # Configure SSM agent (usually pre-installed on Ubuntu)
    snap install amazon-ssm-agent --classic
    systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
    systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

    # Set hostname
    hostnamectl set-hostname ubuntu-target

    # Install CloudWatch agent for logging
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb

    # Start services
    systemctl start xrdp
    systemctl start apache2
    systemctl start mysql

    echo "Ubuntu Target setup complete" > /var/log/lab-setup.log
  EOF
  )

  tags = {
    Name        = "Ubuntu Target"
    Purpose     = "Defensive security testing target"
    Environment = var.environment
    Lab         = "security-lab"
    Role        = "target"
  }
}

# -----------------------------------------------------------------------------
# Kali Linux (Attacker Machine)
# -----------------------------------------------------------------------------

resource "aws_instance" "kali_attacker" {
  ami                    = data.aws_ami.ubuntu_attacker.id
  instance_type          = var.security_lab_instance_type
  key_name               = aws_key_pair.security_lab.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.kali_attacker.id]
  iam_instance_profile   = aws_iam_instance_profile.security_lab.name

  # Enable detailed monitoring
  monitoring = true

  # Disable IMDSv1 for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = 60 # Extra space for tools
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "Attacker Root Volume"
    }
  }

  # User data to install Kali tools on Ubuntu
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex
    exec > >(tee /var/log/user-data.log) 2>&1

    echo "Starting attacker box setup at $(date)"

    # Update base system
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    # Install prerequisites
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      curl wget gnupg apt-transport-https \
      software-properties-common ca-certificates

    # Add Kali Linux repository
    curl -fsSL https://archive.kali.org/archive-key.asc | gpg --dearmor -o /usr/share/keyrings/kali-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list.d/kali.list

    # Lower priority for Kali repo to avoid breaking Ubuntu base
    cat > /etc/apt/preferences.d/kali.pref << 'PREF'
Package: *
Pin: release a=kali-rolling
Pin-Priority: 50
PREF

    apt-get update

    # Install XFCE desktop and remote access from Ubuntu repos
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      xfce4 xfce4-goodies \
      xrdp \
      tigervnc-standalone-server \
      dbus-x11

    # Configure xrdp
    systemctl enable xrdp
    echo "xfce4-session" > /etc/skel/.xsession

    # Create pentester user
    useradd -m -s /bin/bash pentester
    echo "pentester:KaliPentester123!" | chpasswd
    usermod -aG sudo pentester
    echo "xfce4-session" > /home/pentester/.xsession
    chown pentester:pentester /home/pentester/.xsession

    # Install security tools from Ubuntu repos (more stable)
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      nmap masscan netcat-openbsd socat \
      tcpdump wireshark tshark \
      sqlmap nikto dirb gobuster ffuf \
      hydra medusa ncrack \
      john hashcat \
      aircrack-ng kismet \
      enum4linux smbclient nbtscan \
      snmp snmpwalk onesixtyone \
      dnsutils dnsrecon dnsenum whois \
      whatweb wfuzz \
      exploitdb searchsploit \
      python3-pip python3-venv python3-dev \
      ruby ruby-dev \
      git build-essential libssl-dev libffi-dev \
      proxychains4 tor \
      wordlists seclists

    # Install Metasploit from Kali repo (pin specifically)
    DEBIAN_FRONTEND=noninteractive apt-get install -y -t kali-rolling metasploit-framework || {
      # Fallback: Install from Rapid7
      curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
      chmod 755 /tmp/msfinstall
      /tmp/msfinstall
    }

    # Install additional tools from Kali repo
    DEBIAN_FRONTEND=noninteractive apt-get install -y -t kali-rolling \
      responder crackmapexec evil-winrm impacket-scripts \
      bloodhound neo4j powershell-empire \
      burpsuite zaproxy 2>/dev/null || true

    # Install Python security tools
    pip3 install --break-system-packages \
      impacket pwntools requests beautifulsoup4 \
      paramiko scapy netaddr ipython \
      ldap3 bloodhound certipy-ad \
      mitm6 coercer || true

    # Clone essential repos
    mkdir -p /opt/tools
    cd /opt/tools
    git clone --depth 1 https://github.com/danielmiessler/SecLists.git || true
    git clone --depth 1 https://github.com/carlospolop/PEASS-ng.git || true
    git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings.git || true
    git clone --depth 1 https://github.com/lgandx/Responder.git || true
    git clone --depth 1 https://github.com/fortra/impacket.git || true
    git clone --depth 1 https://github.com/byt3bl33d3r/CrackMapExec.git || true
    git clone --depth 1 https://github.com/ropnop/kerbrute.git || true
    chown -R pentester:pentester /opt/tools

    # Install SSM agent
    snap install amazon-ssm-agent --classic
    systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
    systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

    # Set hostname
    hostnamectl set-hostname attacker

    # Add target to hosts file
    echo "${aws_instance.ubuntu_target.private_ip} ubuntu-target target" >> /etc/hosts

    # Start xrdp
    systemctl start xrdp

    echo "Attacker box setup complete at $(date)" >> /var/log/lab-setup.log
  EOF
  )

  tags = {
    Name        = "Kali Attacker"
    Purpose     = "Offensive security testing platform"
    Environment = var.environment
    Lab         = "security-lab"
    Role        = "attacker"
  }

  # Wait for Ubuntu target to be created first
  depends_on = [aws_instance.ubuntu_target]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ubuntu_target_public_ip" {
  description = "Public IP of Ubuntu target (use for RDP/VNC from admin location)"
  value       = aws_instance.ubuntu_target.public_ip
}

output "ubuntu_target_private_ip" {
  description = "Private IP of Ubuntu target (use from Kali for attacks)"
  value       = aws_instance.ubuntu_target.private_ip
}

output "kali_attacker_public_ip" {
  description = "Public IP of Kali attacker"
  value       = aws_instance.kali_attacker.public_ip
}

output "kali_attacker_private_ip" {
  description = "Private IP of Kali attacker"
  value       = aws_instance.kali_attacker.private_ip
}

output "security_lab_ssh_command" {
  description = "SSH command to connect to Kali"
  value       = "ssh -i ~/.ssh/id_ed25519 kali@${aws_instance.kali_attacker.public_ip}"
}

output "security_lab_target_credentials" {
  description = "Default credentials for lab user on Ubuntu target"
  value       = "labuser / LabPassword123!"
  sensitive   = true
}

output "security_lab_attacker_credentials" {
  description = "Default credentials for pentester on Kali"
  value       = "pentester / KaliPentester123!"
  sensitive   = true
}
