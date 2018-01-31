#/bin/bash

clear
cd ~
echo "**********************************************************************"
echo "* Ubuntu 16.04 is the recommended opearting system for this install. *"
echo "*                                                                    *"
echo "* This script will install and configure your Escrow masternode.    *"
echo "**********************************************************************"
echo && echo && echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!                                                 !"
echo "! Make sure you double check before hitting enter !"
echo "!                                                 !"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo && echo && echo
sleep 3

sudo apt-get install systemd -y

# Check for systemd
systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Gather input from user
read -e -p "Masternode Private Key (e.g. 7edfjLCUzGczZi3JQw8GHp434R9kNY33eFyMGeKRymkB56G4324h) : " key
if [[ "$key" == "" ]]; then
    echo "WARNING: No private key entered, exiting!!!"
    echo && exit
fi
read -e -p "Server IP Address : " ip
echo && echo "Pressing ENTER will use the default value for the next prompts."
echo && sleep 3
read -e -p "Add swap space? (Recommended) [Y/n] : " add_swap
if [[ ("$add_swap" == "y" || "$add_swap" == "Y" || "$add_swap" == "") ]]; then
    read -e -p "Swap Size [2G] : " swap_size
    if [[ "$swap_size" == "" ]]; then
        swap_size="2G"
    fi
fi    
read -e -p "Install Fail2ban? (Recommended) [Y/n] : " install_fail2ban
read -e -p "Install UFW and configure ports? (Recommended) [Y/n] : " UFW

# Add swap if needed
if [[ ("$add_swap" == "y" || "$add_swap" == "Y" || "$add_swap" == "") ]]; then
    if [ ! -f /swapfile ]; then
        echo && echo "Adding swap space..."
        sleep 3
        sudo fallocate -l $swap_size /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        sudo sysctl vm.swappiness=10
        sudo sysctl vm.vfs_cache_pressure=50
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
    else
        echo && echo "WARNING: Swap file detected, skipping add swap!"
        sleep 3
    fi
fi


# Add masternode group and user
sudo groupadd masternode
sudo useradd -m -g masternode masternode

# Update system 
echo && echo "Upgrading system..."
sleep 3
sudo apt-get -y update
sudo apt-get -y upgrade

# Add Berkely PPA
echo && echo "Installing bitcoin PPA..."
sleep 3
sudo apt-get -y install software-properties-common
sudo apt-add-repository -y ppa:bitcoin/bitcoin
sudo apt-get -y update
sudo apt-get -y upgrade

# Install required packages
echo && echo "Installing base packages..."
sleep 3
sudo apt-get -y install \
    wget \
    git \
    libevent-dev \
    libboost-dev \
    libboost-chrono-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-system-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libdb4.8-dev \
    libdb4.8++-dev \
    libminiupnpc-dev \
    libboost-all-dev \
    libdb4.8-dev \
    libdb4.8++-dev \
    libminiupnpc-dev \
    libzmq3-dev
    
sudo apt-get -y install build-essential libtool autotools-dev automake pkg-config libssl-dev bsdmainutils

# Install fail2ban if needed
if [[ ("$install_fail2ban" == "y" || "$install_fail2ban" == "Y" || "$install_fail2ban" == "") ]]; then
    echo && echo "Installing fail2ban..."
    sleep 3
    sudo apt-get -y install fail2ban
    sudo service fail2ban restart 
fi

# Install firewall if needed
if [[ ("$UFW" == "y" || "$UFW" == "Y" || "$UFW" == "") ]]; then
    echo && echo "Installing UFW..."
    sleep 3
    sudo apt-get -y install ufw
    echo && echo "Configuring UFW..."
    sleep 3
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow 8018/tcp
    sudo ufw allow 8017/tcp
    echo "y" | sudo ufw enable
    echo && echo "Firewall installed and enabled!"
fi

# Download Escrow
echo && echo "Downloading Escrow..."
sleep 3
wget https://github.com/masterhash-us/EscrowMN/releases/download/1.0/Escrow.tgz
tar -xvf Escrow.tgz
rm Escrow.tgz

# Install Escrow
echo && echo "Installing Escrow..."
sleep 3
cp Escrowd /usr/local/bin

# Create config for Escrow
echo && echo "Configuring Escrow..."
sleep 3
rpcuser=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
rpcpassword=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
sudo mkdir -p /home/masternode/.Escrow
sudo touch /home/masternode/.Escrow/Escrow.conf
echo '
rpcuser='$rpcuser'
rpcpassword='$rpcpassword'
rpcport=8017
port=8018
rpcallowip=127.0.0.1
listen=1
server=1
daemon=0 # required for systemd
logtimestamps=1
maxconnections=256
externalip='$ip'
masternodeaddr='$ip':8018
masternodeprivkey='$key'
masternode=1
' | sudo -E tee /home/masternode/.Escrow/Escrow.conf
sudo chown -R masternode:masternode /home/masternode/.Escrow

# Setup systemd service
echo && echo "Starting Escrow Daemon..."
sleep 3
sudo touch /etc/systemd/system/Escrowd.service
echo '[Unit]
Description=Escrowd
After=network.target
[Service]
Type=simple
User=masternode
WorkingDirectory=/home/masternode
ExecStart=/usr/local/bin/Escrowd -conf=/home/masternode/.Escrow/Escrow.conf -datadir=/home/masternode/.Escrow
ExecStop=/usr/local/bin/Escrowd -conf=/home/masternode/.Escrow/Escrow.conf -datadir=/home/masternode/.Escrow stop
Restart=on-abort
[Install]
WantedBy=multi-user.target
' | sudo -E tee /etc/systemd/system/Escrowd.service
sudo systemctl enable Escrowd
sudo systemctl start Escrowd

cd ~

# Add alias to run Escrowd
echo && echo "Masternode setup complete!"
touch ~/.bash_aliases
echo "alias Escrowd='Escrowd -conf=/home/masternode/.Escrow/Escrow.conf -datadir=/home/masternode/.Escrow'" | tee -a ~/.bash_aliases

echo && echo "Now run 'source ~/.bash_aliases' (without quotes) to use Escrowd"/tcp
   


