#!/bin/bash

DIST=trixie
LANG_TARGET=en_US.UTF-8
PASSWORD=1234
NAME=ufi003
PARTUUID=598664a9-7976-e692-1cdd-010c5d49b568

cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ $DIST main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ $DIST main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ $DIST-updates main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ $DIST-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ $DIST-backports main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ $DIST-backports main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security $DIST-security main contrib non-free non-free-firmware
# deb-src http://security.debian.org/debian-security $DIST-security main contrib non-free non-free-firmware
EOF

cat <<EOF > /etc/fstab
PARTUUID=$PARTUUID / ext4 defaults,noatime,commit=600,errors=remount-ro 0 1
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF

apt-get update
apt-get full-upgrade -y
apt-get install -y locales network-manager openssh-server systemd-timesyncd fake-hwclock zram-tools rmtfs qrtr-tools
apt-get install -y /tmp/*.deb

# Patch openstick-gc-manager.sh to directly activate USB gadget (rndis,ffs) and bring up usb0 (192.168.68.1/24)
python3 - <<'PYEOF'
p = "/usr/sbin/openstick-gc-manager.sh"
s = open(p).read()
old = '''startup() {
  # force usb host mode enabled by default
  if ! is_usb_connected; then
    set_usb_host_mode
  fi
  # wait usb devices up
  sleep 3

  # enable gadget interfaces if defined
  if [ -n "${GC_MODE}" ] ; then
    logger "Setting up gadgets: $GC_MODE"
    if ! setup_gadget_mode; then
      logger "Cannot activate gadget mode, perhaps already connected to gadget devices as a host"
    fi
  fi
}'''
new = '''startup() {
  # Directly enable gadget mode (RNDIS + ADB) and bring up usb0 192.168.68.1/24
  if [ -n "${GC_MODE}" ] ; then
    logger "Setting up gadgets: $GC_MODE"
    set_usb_gadget_mode
    $GADGET_CONTROL -d
    $GADGET_CONTROL -c
    for i in $(echo "${GC_MODE}" | sed "s/,/ /g") ; do
      case $i in
        (serial|hid|midi|printer|uvc|rndis|ecm|acm)
          $GADGET_CONTROL -a "$i"
          ;;
        (ffs)
          $GADGET_CONTROL -a ffs
          mkdir -p /dev/usb-ffs/adb
          mount -t functionfs adb /dev/usb-ffs/adb
          systemctl restart adbd
          sleep 2
          ;;
      esac
    done
    $GADGET_CONTROL -e
    nmcli con del usb-failsafe 2>/dev/null || true
    nmcli con add type ethernet ifname usb0 con-name "usb-failsafe" ipv4.addresses "192.168.68.1/24" ipv4.method shared autoconnect yes || true
    nmcli con up usb-failsafe 2>/dev/null || true
  fi
}'''
if old in s:
    open(p, "w").write(s.replace(old, new))
PYEOF
chmod 755 /usr/sbin/openstick-gc-manager.sh
sed -i -e "s/# $LANG_TARGET UTF-8/$LANG_TARGET UTF-8/" /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=$LANG_TARGET LC_ALL=$LANG_TARGET LANGUAGE=$LANG_TARGET
echo -n >/etc/resolv.conf
echo -e "$PASSWORD\n$PASSWORD" | passwd
echo $NAME > /etc/hostname
sed -i "1a 127.0.0.1\t$NAME" /etc/hosts
sed -i "s/::1\t\tlocalhost/::1\t\tlocalhost $NAME/g" /etc/hosts
sed -i 's/^.\?PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^.\?ALGO=.*$/ALGO=lzo-rle/g' /etc/default/zramswap
sed -i 's/^.\?PERCENT=.*$/PERCENT=300/g' /etc/default/zramswap

vmlinuz_name=$(basename /boot/vmlinuz-*)
cat <<EOF > /tmp/info.md
- 内核版本: ${vmlinuz_name#*-}
- 默认用户名: root
- 默认密码: $PASSWORD
- WiFi名称: openstick-failsafe
- WiFi密码: 12345678
EOF
rm -rf /etc/ssh/ssh_host_* /var/lib/apt/lists
apt clean
exit
