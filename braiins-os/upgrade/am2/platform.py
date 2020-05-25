# Copyright (C) 2020  Braiins Systems s.r.o.
#
# This file is part of Braiins Open-Source Initiative (BOSI).
#
# BOSI is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Please, keep in mind that we may also license BOSI or any part thereof
# under a proprietary license. For more information on the terms and conditions
# of such proprietary license or if you have any other questions, please
# contact us at opensource@braiins.com.

import subprocess
import tarfile
import hashlib
import shutil
import sys
import time
import os
import io

from urllib.request import Request, urlopen
from contextlib import contextmanager
from tempfile import TemporaryDirectory, TemporaryFile

from .backup import ssh_run, ssh_mac, ssh_factory_mtdparts, ssh_backup, ssh_restore, ssh_restore_reboot
from .backup import get_stream_size, get_default_hostname
from .transfer import Progress
from .util import get_data_root_path

CONFIG_TAR = 'config.tar.gz'
TARGET_DIR = '/tmp/bitmain_fw'

RESTORE_DIR = os.path.join(get_data_root_path(), 'upgrade')
RESTORE_NAME = 'restore.sh'

BACKUP_SUFFIX = '_tmp'

FACTORY_MTDPARTS = \
    'mtdparts=pl35x-nand:40m(BOOT.bin-env-dts-kernel),32m(ramfs),8m(configs),16m(reserve),32m(ramfs-bak),128m(reserve1)'

SUPPORTED_IMAGES = [
    # Antminer-S15-user-OM-201912131535-ssh.tar.gz
    '200654af5ea5f22b479049c5a8269b3d'
]

SYSTEM_BINARIES = [
    ('ld-musl-armhf.so.1', '/lib'),
    ('sftp-server', '/usr/lib/openssh'),
    ('fw_printenv', '/usr/sbin'),
    ('busybox1.25', '/bin')
]

SYSTEM_LINKS = [
    ('/usr/sbin/fw_setenv', '/usr/sbin/fw_printenv'),
    ('/usr/bin/awk', '/bin/busybox1.25')
]


class PlatformStop(Exception):
    pass


def backup_firmware(args, ssh, path, mac):
    print('Preparing system for backup...')
    # before NAND dump try to stop all daemons which modify UBIFS
    # /tmp on AntMiner is mounted directly to UBIFS
    ssh.run('mount', '-t', 'tmpfs', 'tmpfs', '/tmp/')
    # stop bmminer which logs to /tmp
    ssh.run('/etc/init.d/bmminer.sh', 'stop')
    # give to system some time to kill all processes and free handles
    time.sleep(1)
    # sync everything to NAND
    ssh.run('sync')
    print('Backuping configuration files...')
    local_path = os.path.join(path, CONFIG_TAR)
    with open(local_path, 'wb') as local_file, ssh.pipe('tar', 'cvzf', '-', '/config') as remote:
        shutil.copyfileobj(remote.stdout, local_file)
    # start backup process
    return ssh_backup(args, ssh, path, mac)


def upload_bitmain_files(sftp, stream):
    # transfer original Bitmain firmware images needed for upgrade
    with tarfile.open(fileobj=stream, mode='r|*') as tarball:
        for member in tarball:
            member_file = tarball.extractfile(member)
            name = member.name
            with Progress(name, member.size) as progress:
                sftp.putfo(member_file, name, callback=progress)


def md5fo(stream):
    hash_md5 = hashlib.md5()
    for chunk in iter(lambda: stream.read(4096), b''):
        hash_md5.update(chunk)
    return hash_md5.hexdigest()


@contextmanager
def prepare_restore(args, backup_dir):
    url = args.factory_image
    if not url:
        # factory image is not set and standard NAND restore is used
        if not backup_dir:
            print('Backup cannot be found!')
            print('Please use factory image or provide correct path to directory or tarball with previous backup.')
            raise PlatformStop
        yield
        return

    if os.path.isfile(url):
        stream = open(url, 'rb')
    else:
        # download remote image to temporary file
        stream = TemporaryFile()
        remote = urlopen(Request(url, headers={'User-Agent': 'Mozilla/5.0'}))
        print('Downloading factory image...')
        shutil.copyfileobj(remote, stream)
        stream.seek(0)

    image_md5 = md5fo(stream)
    if image_md5 not in SUPPORTED_IMAGES:
        stream.close()
        print('Unsupported factory image with MD5 digest: {}'.format(image_md5))
        raise PlatformStop

    args.factory_stream = stream
    args.factory_stream.seek(0)
    yield
    args.factory_stream.close()


def get_factory_mtdparts(args, ssh, backup_dir):
    if backup_dir:
        return ssh_factory_mtdparts(args, ssh, backup_dir)
    else:
        return FACTORY_MTDPARTS


def restore_bitmain_firmware(args, ssh, backup_dir, mtdparts):
    # prepare target directory
    ssh.run('rm', '-fr', TARGET_DIR)
    ssh.run('mkdir', '-p', TARGET_DIR)

    # copy firmware files to the server over SFTP
    sftp = ssh.open_sftp()
    sftp.chdir(TARGET_DIR)

    print("Uploading firmware...")
    upload_bitmain_files(sftp, args.factory_stream)

    print("Uploading restore scripts...")
    files = [
        (backup_dir, CONFIG_TAR),
        (RESTORE_DIR, RESTORE_NAME)
    ]
    for dir, file_name in files:
        local_path = os.path.join(dir, file_name)
        with Progress(local_path) as progress:
            sftp.put(local_path, file_name, callback=progress)

    sftp.close()

    # run stage1 upgrade process
    try:
        print("Restoring firmware...")
        stdout, _ = ssh.run('cd', TARGET_DIR, '&&', 'ls', '-l', '&&',
                            "/bin/sh {}".format(RESTORE_NAME))
    except subprocess.CalledProcessError as error:
        for line in error.stderr.readlines():
            print(line, end='')
        raise PlatformStop
    else:
        for line in stdout.readlines():
            print(line, end='')


def create_bitmain_config(ssh, tmp_dir):
    bitmain_hostname = 'antMiner'
    config_dir = 'config'

    # restore original configuration from running miner
    mac = ssh_mac(ssh)

    config_path = os.path.join(tmp_dir, CONFIG_TAR)
    tar = tarfile.open(config_path, "w:gz")
    stream_info = tar.gettarinfo(config_path)

    # create mac file
    stream = io.BytesIO('{}\n'.format(mac).encode())
    stream_info.name = '{}/mac'.format(config_dir)
    stream_info.size = get_stream_size(stream)
    tar.addfile(stream_info, stream)
    stream.close()

    # create network.conf file
    stream = io.BytesIO()
    net_proto = ssh_run(ssh, 'uci', 'get', 'network.lan.proto')
    if net_proto == 'dhcp':
        try:
            net_hostname = ssh_run(ssh, 'uci', 'get', 'network.lan.hostname')
        except subprocess.CalledProcessError:
            net_hostname = ssh_run(ssh, 'cat', '/proc/sys/kernel/hostname')
        if net_hostname == get_default_hostname(mac):
            # do not restore BOS default hostname
            net_hostname = bitmain_hostname
        stream.write('hostname={}\n'.format(net_hostname).encode())
        stream.write('dhcp=true\n'.encode())
    else:
        # static protocol
        net_ipaddr = ssh_run(ssh, 'uci', 'get', 'network.lan.ipaddr')
        net_mask = ssh_run(ssh, 'uci', 'get', 'network.lan.netmask')
        net_gateway = ssh_run(ssh, 'uci', 'get', 'network.lan.gateway')
        net_dns = ssh_run(ssh, 'uci', 'get', 'network.lan.dns')
        stream.write('hostname={}\n'.format(bitmain_hostname).encode())
        stream.write('ipaddress={}\n'.format(net_ipaddr).encode())
        stream.write('netmask={}\n'.format(net_mask).encode())
        stream.write('gateway={}\n'.format(net_gateway).encode())
        stream.write('dnsservers="{}"\n'.format(net_dns).encode())
    stream.seek(0)
    stream_info.name = '{}/network.conf'.format(config_dir)
    stream_info.size = get_stream_size(stream)
    tar.addfile(stream_info, stream)
    stream.close()

    tar.close()


def restore_firmware(args, ssh, backup_dir, mtdparts):
    if args.factory_image:
        if backup_dir:
            restore_bitmain_firmware(args, ssh, backup_dir, mtdparts)
        else:
            with TemporaryDirectory() as tmp_dir:
                print("Creating configuration files...")
                create_bitmain_config(ssh, tmp_dir)
                restore_bitmain_firmware(args, ssh, tmp_dir, mtdparts)
        ssh_restore_reboot(args, ssh)
    else:
        # use default NAND dump restore
        ssh_restore(args, ssh, backup_dir, mtdparts)


def prepare_system(ssh, path):
    for file_name, remote_path in SYSTEM_BINARIES:
        remote_file_name = '{}/{}'.format(remote_path, file_name)
        try:
            ssh.run('test', '!', '-e', remote_file_name)
        except subprocess.CalledProcessError:
            print("File '{}' exists on remote target already!".format(remote_file_name))
            raise PlatformStop

    for file_name, remote_path in SYSTEM_BINARIES:
        ssh.run('mkdir', '-p', remote_path)
        remote_file_name = '{}/{}'.format(remote_path, file_name)
        print('Copy {} to {}'.format(file_name, remote_file_name))
        ssh.put(os.path.join(path, file_name), remote_file_name)
        ssh.run('chmod', '+x', remote_file_name)

    for link_name, remote_path in SYSTEM_LINKS:
        try:
            ssh.run('test', '!', '-e', link_name)
        except subprocess.CalledProcessError:
            ssh.run('mv', link_name, link_name + BACKUP_SUFFIX)
        ssh.run('mkdir', '-p', os.path.dirname(link_name))
        ssh.run('ln', '-fs', remote_path, link_name)

    print()


def cleanup_system(ssh):
    for file_name, remote_path in SYSTEM_BINARIES:
        remote_file_name = '{}/{}'.format(remote_path, file_name)
        ssh.run('rm', '-r', remote_file_name)

    for link_name, remote_path in SYSTEM_LINKS:
        try:
            ssh.run('test', '!', '-e', link_name + BACKUP_SUFFIX)
        except subprocess.CalledProcessError:
            ssh.run('mv', link_name + BACKUP_SUFFIX, link_name)
        else:
            ssh.run('rm', link_name)


def add_restore_arguments(parser):
    frozen_factory_fw = getattr(sys, 'frozen_factory_fw', None)
    if frozen_factory_fw:
        default_factory_fw = os.path.join(get_data_root_path(), frozen_factory_fw)
        default_factory_fw_help = " (default: {})".format(os.path.basename(
            default_factory_fw))
    else:
        default_factory_fw = None
        default_factory_fw_help = ""

    parser.add_argument('--factory-image', default=default_factory_fw,
                        help='path/url to firmware upgrade image{}'.format(
                            default_factory_fw_help))
