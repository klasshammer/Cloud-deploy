terraform {

  required_version = ">= 1.0"


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- 1. VPC Y REDES ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "migracion"
  cidr = "10.0.0.0/22"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true # Nat gateway zonal en 1a
  one_nat_gateway_per_az = false

  tags = {
    Terraform = "true"
  }
}

# --- 2. SECURITY GROUPS ---

# SG-Web
resource "aws_security_group" "sg_web" {
  name        = "SG-Web"
  description = "Acceso para aplicacion web"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG-BD
resource "aws_security_group" "sg_bd" {
  name   = "tu-grupo-seguridad-BD"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Recomendado: cambiar a SG-Web por seguridad
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. RDS MYSQL ---

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "gp-subnet-bd"
  description = "grupo subred privado"
  subnet_ids  = module.vpc.private_subnets
}

resource "aws_db_instance" "mysql_db" {
  identifier        = "db-migracion"
  engine            = "mysql"
  engine_version    = "8.0.35" # Versión disponible estable (8.4 puede variar por región)
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  db_name           = "mydb"
  username          = "admin"
  password          = "TuPasswordSegura123" # Cambia esto

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.sg_bd.id]
  availability_zone      = "us-east-1a"
  skip_final_snapshot    = true
  storage_encrypted      = true

  tags = {
    Name = "RDS-MySQL-Migracion"
  }
}

# --- 4. EC2 INSTANCE ---

resource "aws_instance" "web_app" {
  ami                         = "ami-051f8b21383522227" # Amazon Linux 2023 en us-east-1
  instance_type               = "t3.micro"
  key_name                    = "vockey"
  subnet_id                   = module.vpc.public_subnets[0] # subnet-publica-1a
  vpc_security_group_ids      = [aws_security_group.sg_web.id]
  associate_public_ip_address = true
  iam_instance_profile        = "LabInstanceProfile" # Basado en LabInstanceProfile

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "nombre-APP-WEB-tu-ec2"
  }
}