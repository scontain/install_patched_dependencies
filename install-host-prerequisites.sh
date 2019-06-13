#!//bin/bash
: '
Access to this file is granted under the SCONE COMMERCIAL LICENSE V1.0

Any use of this product using this file requires a commercial license from scontain UG, www.scontain.com.

Permission is also granted  to use the Program for a reasonably limited period of time  (but no longer than 1 month)
for the purpose of evaluating its usefulness for a particular purpose.

THERE IS NO WARRANTY FOR THIS PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING
THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE,
YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED ON IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY
MODIFY AND/OR REDISTRIBUTE THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE PROGRAM INCLUDING BUT NOT LIMITED TO LOSS
OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE
WITH ANY OTHER PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

Copyright (C) 2018 scontain.com
'

set -e -x


RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
ver=true

errorexit() {
  printf "${RED}#####  An error occurred while installing host! Please check the logs. Sometimes it is sufficient to restart this script! #####${NC}\n"
  exit 1
}

trap 'errorexit' ERR


function verbose {
    if [[ $ver != "" ]]  ; then
        printf "${GREEN}$1${NC}\n"
    fi
}

verbose "..downloading more files"

curl -fssl https://raw.githubusercontent.com/scontain/install_patched_dependencies/master/las.service --output /tmp/las.service
curl -fssl https://raw.githubusercontent.com/scontain/install_patched_dependencies/master/las-docker-compose.yml --output /tmp/las-docker-compose.yml
curl -fssl https://raw.githubusercontent.com/scontain/install_patched_dependencies/master/microcode-load.service --output /tmp/microcode-load.service

verbose "..installing microcode update"

installed=$(systemctl status microcode-load.service | grep "Started updated microcode-load service." | wc -l)
if [[ $installed == "1" ]] ; then
    verbose "  microcode update already installed - skipping"
else
    TMPDIR=$(mktemp -d)
    cd $TMPDIR
    curl -o ucode.tgz https://downloadmirror.intel.com/28039/eng/microcode-20180807.tgz
    tar -xzf ucode.tgz
    sudo apt-get update
    sudo apt-get install -y intel-microcode
    # continue even if microcode update fails - could be not possible (running in a VM for example)
    if [ -f /sys/devices/system/cpu/microcode/reload ] ; then
        if [ -d /lib/firmware ] ; then
            mkdir -p OLD
            cp -rf /lib/firmware/intel-ucode OLD
                sudo cp -rf intel-ucode /lib/firmware
            echo "1" | sudo tee /sys/devices/system/cpu/microcode/reload
            verbose "..enable start of new microcode on each reboot"

            cat > /tmp/load-intel-ucode.sh << EOF
#!/bin/bash
echo "1" | sudo tee /sys/devices/system/cpu/microcode/reload
EOF
            sudo mv -f /tmp/load-intel-ucode.sh /lib/firmware/load-intel-ucode.sh
            chmod a+x /lib/firmware/load-intel-ucode.sh

            sudo mv -f /tmp/microcode-load.service  /etc/systemd/system/microcode-load.service
            sudo systemctl daemon-reload
            sudo systemctl start microcode-load.service
            sudo systemctl enable microcode-load.service || echo "looks like microcode-load.service  is already enabled"
        else
            echo "Error: microcode directory does not exist"
        fi
    else
        echo "Error: is intel-micrcode really installed?"
    fi
fi

verbose "..installing patched docker engine"

echo "removing old docker engine - if installed"
(sudo systemctl stop docker) || (sudo service docker stop) || echo "stop docker: neither systemctl nor service are used"
sudo apt-get remove -y docker-engine || echo "docker not installed"
sudo apt-get remove -y docker-ce || echo "docker-ce not installed"

KEYNAME="96B9BADB"
REPO="deb https://sconecontainers.github.io/APT ./"

sudo apt-get install -y linux-image-extra-$(uname -r) || echo "WARNING: Error installing linux-image-extra-$(uname -r) (linux-image-extra not available for all kernels - trying to continue)"

sudo apt-get update
sudo sudo apt-get install -y apt-transport-https ca-certificates
sudo apt-key adv \
  --keyserver hkp://ha.pool.sks-keyservers.net:80 \
  --recv-keys $KEYNAME

echo $REPO | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update

#apt-cache policy docker-engine

S=`apt-cache policy docker-engine | grep $(lsb_release --codename -s) | awk '{print $1}' | head -1`

if [[ "$S" == "" ]] ; then
  echo "#WARNING: no appropriate docker engine candidate found"
  echo "  # release: " $(lsb_release --codename -s)
  echo "  # candidates:" $(apt-cache policy docker-engine)
  # try anyhow - maybe it works nevertheless?
  sudo apt-get install -y docker-engine
else
  sudo apt-get install -y docker-engine || sudo apt-get install -y docker-engine=$S
fi

## in case file length is wrong - try to uncomment the following:
# sudo apt -o Acquire::https::No-Cache=True -o Acquire::http::No-Cache=True update



stop_it=true
(sudo service docker status | grep running) || (sudo systemctl status docker | grep running) || stop_it=false
if [[ $stop_it==true ]] ; then
  (sudo systemctl stop docker) || (sudo service docker stop) || echo "stop docker: neither systemctl nor service are used"
fi

(sudo systemctl start docker) || (sudo service docker start) || echo "start docker: neither systemctl nor service are used"

echo "Patched docker engine installed"


verbose "..installing docker compose"
installed=$(which docker-compose | wc -l)
if [[ $installed == "1" ]] ; then
    verbose "  docker-compose already installed - skipping"
else
    sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    # simple check
    docker-compose --version
fi

verbose "..installing patched SGX driver"

        verbose "isgx driver might be installed - trying to remove it."
        # try to stop services that might be using isgx
        sudo /usr/sbin/service aesmd stop || aesmd_running=false
        sudo /usr/sbin/service aesmd stop || aesmd_running=false
        # try to remove - force is typically useless
        dorem=true
        sudo lsmod | grep isgx || dorem=false
        if [[ $dorem == true ]] ; then
            sudo rmmod $FORCE isgx 2>/dev/null >/dev/null || verbose "removal of old isgx driver failed - you might need to reboot to be able to offload old driver"
        fi


        rm -rf linux-sgx-driver
        git clone https://github.com/christoffetzer/linux-sgx-driver

        cd linux-sgx-driver/
        sudo apt-get update
        sudo apt-get install -y build-essential
        make

        sudo mkdir -p "/lib/modules/"`uname -r`"/kernel/drivers/intel/sgx"
        sudo cp -f isgx.ko "/lib/modules/"`uname -r`"/kernel/drivers/intel/sgx"

        sudo sh -c "cat /etc/modules | grep -Fxq isgx || echo isgx >> /etc/modules"
        sudo /sbin/depmod
        sudo /sbin/modprobe isgx

        cd ..

verbose "..ensure that we can run docker without sudo"

if getent group ubuntu | grep &>/dev/null "\bubuntu\b"; then
    verbose "  user and group ubuntu already exist"
else
    sudo groupadd ubuntu || verbose "  group ubuntu already exist"
    sudo adduser --ingroup ubuntu ubuntu || verbose "  user ubuntu already exists!"
fi

USER=ubuntu
if getent group docker | grep &>/dev/null "\b${USER}\b"; then
    todo=false
else
    todo=true
fi
if [[ $todo == true ]] ; then
    sudo groupadd docker || verbose "  group docker already exist"
    sudo gpasswd -a $USER docker || verbose "  $USER is already member of group docker"
fi


verbose "..installing LAS service"
verbose "  if the following fails, please log into docker and reruns script"

installed=$(systemctl status las.service | grep "Active: active (running)" | wc -l)

if [[ "$1" == "-f" ]] ; then
    if [[ $installed > 0 ]] ; then
        verbose "  force flag given: stopping running las service"
        sudo systemctl stop las.service || verbose "failed to stop las service ... continue anyhow"
        sudo systemctl disable las.service || verbose "failed to disable las service ... continue anyhow"
        installed=0
    fi
fi

if [[ $installed > 0 ]] ; then
    verbose "  LAS service already installed - skipping"
else
    sudo mkdir -p /home/ubuntu/las
    sudo chown ubuntu:ubuntu /home/ubuntu/las
    sudo mv -f /tmp/las-docker-compose.yml /home/ubuntu/las/docker-compose.yml

    #export DOCKER_CONTENT_TRUST=1

    sudo mv -f /tmp/las.service  /etc/systemd/system/las.service
    docker pull sconecuratedimages/iexecsgx:las
    sudo systemctl daemon-reload
    sleep 2
    sudo systemctl start las.service
    sudo systemctl status las.service
    sudo systemctl enable las.service || echo "looks like las.service  is already enabled"
fi
