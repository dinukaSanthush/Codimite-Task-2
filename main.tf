
# configure gcp infrastructure

provider "google" {
  credentials = file("terraform-363417-5f115e02cd21.json")
  project     = "terraform-363417"      
  region      = "asia-southeast1"
  zone        = "asia-southeast1-b"
}

# create vpc
resource "google_compute_network" "vpc" {
  name                    = "dinukavpc"
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = true
}

# allocate a block of private IP addresses for the vpc 
resource "google_compute_global_address" "private_ip_block" {
  name         = "private-ip-block"
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"
  ip_version   = "IPV4"
  prefix_length = 20
  network       = google_compute_network.vpc.self_link
}

# allows instances to communicate using the internal network.
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block.name]
}

# firewall rule to allow ssh traffic
resource "google_compute_firewall" "allow_ssh" {
  name        = "allow-ssh"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22", "3306"]
  }
  target_tags = ["ssh-enabled"]
}

# create mysql instance
resource "google_sql_database" "main" {
  name     = "main"
  instance = google_sql_database_instance.main_primary.name
}

# add db to private vpc 
resource "google_sql_database_instance" "main_primary" {
  name             = "main-primary"
  database_version = "MYSQL_8_0"
  deletion_protection = false
  depends_on       = [google_service_networking_connection.private_vpc_connection]
  settings {
    tier              = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }
}

#creates mysql user on sql instance
resource "google_sql_user" "db_user" {
  name     = "dinuka"
  instance = google_sql_database_instance.main_primary.name
  password = "1234"
}


# create gcp instance on the same region as the database (same subnet)
data "google_compute_subnetwork" "regional_subnet" {
  name   = google_compute_network.vpc.name
  region = "asia-southeast1"
}

# create instance
resource "google_compute_instance" "db_proxy" {
  name                      = "db-proxy"
  machine_type              = "e2-medium"
  tags = ["ssh-enabled"]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"           
    }
  }

#ssh keys (ssh-keygen)
  metadata = {
    ssh-keys = "${"dinuka"}:${file("~/.ssh/id_rsa.pub")}" 
  }

#add instance to vpc and set to get a public IP
  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = data.google_compute_subnetwork.regional_subnet.self_link
    access_config {}
  }

}
