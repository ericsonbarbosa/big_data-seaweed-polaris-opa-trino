Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  # VM 1 - SeaweedFS + Apache Polaris (Iceberg REST Catalog)
  config.vm.define "seaweedfs-node" do |seaweedfs|
    seaweedfs.vm.hostname = "seaweedfs-node"
    seaweedfs.vm.network "private_network", ip: "192.168.56.101"

    # Porta do SeaweedFS Master
    seaweedfs.vm.network "forwarded_port", guest: 9333, host: 9333
    # Porta do SeaweedFS Volume
    seaweedfs.vm.network "forwarded_port", guest: 8080, host: 8888
    # Porta do SeaweedFS Filer
    seaweedfs.vm.network "forwarded_port", guest: 8888, host: 9888
    # Porta do Apache Polaris (REST Catalog)
    seaweedfs.vm.network "forwarded_port", guest: 8181, host: 8181

    seaweedfs.vm.boot_timeout = 120

    seaweedfs.vm.provider "virtualbox" do |vb|
      vb.name = "seaweedfs-node"
      vb.memory = 4096
      vb.cpus = 4
    end
  end

  # VM 2 - Trino
  config.vm.define "trino-sea-node" do |trino|
    trino.vm.hostname = "trino-sea-node"
    trino.vm.network "private_network", ip: "192.168.56.102"
    # Porta do Trino (Consulta SQL)
    trino.vm.network "forwarded_port", guest: 8080, host: 8080
    trino.vm.boot_timeout = 120

    trino.vm.provider "virtualbox" do |vb|
      vb.name = "trino-sea-node"
      vb.memory = 4096
      vb.cpus = 2
    end
  end

  # VM 3 - Kubernetes Node (K3s)
  config.vm.define "k8s-node" do |node|
    node.vm.box = "ubuntu/jammy64"
    node.vm.hostname = "k8s-node"
    node.vm.network "private_network", ip: "192.168.56.103"
    node.vm.boot_timeout = 120

    node.vm.provider "virtualbox" do |vb|
      vb.name   = "k8s-node"
      vb.memory = 2048
      vb.cpus   = 1
    end
  end

  # Evita confirmação manual de SSH entre VMs
  config.vm.provision "shell", inline: "echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config"

end