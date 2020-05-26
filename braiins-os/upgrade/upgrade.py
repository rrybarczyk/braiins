#!/usr/bin/env python3

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

import argparse
import subprocess
import tempfile
import tarfile
import csv
from getpass import getpass
import sys
import os

import upgrade.hwid as hwid
import upgrade.platform as platform
import upgrade.backup as backup

from upgrade.platform import PlatformStop
from upgrade.ssh import SSHManager, SSHError
from upgrade.transfer import upload_local_files, wait_for_port, Progress

from upgrade.util import get_data_root_path

# default credentials for connecting to device. will ask password if they wont do
USERNAME = 'root'
PASSWORD = None

# binaries necessary for upgrade will be copied onto host from here (sftp, fw_printenv)
SYSTEM_DIR = os.path.join(get_data_root_path(), 'system')
# recovery partition files?
SOURCE_DIR = os.path.join(get_data_root_path(), 'firmware')
# stage3 stagging dir, to be tarballed for transfer
TARGET_DIR = '/tmp/firmware'

STAGE3_BUILTIN_DIR = 'post-upgrade'
STAGE3_DIR = 'upgrade'
STAGE3_FILE = 'stage3.tgz'
STAGE3_SCRIPT = 'stage3.sh'
STAGE3_USER_SCRIPT = 'stage3_usr.sh'

REBOOT_DELAY = (3, 5)


class UpgradeStop(Exception):
    pass


def check_compatibility(ssh):
    try:
        with ssh.open('/tmp/sysinfo/board_name', 'r') as remote_file:
            board_name = next(remote_file).strip()
            print("This script cannot be used for remote target with board name '{}'!".format(board_name))
            if board_name in ('dm1-g9', 'dm1-g19', 'dm1-g29', 'am1-s9', 'am2-s15', 'am2-s17'):
                print("Remote target is running braiins OS already and should be upgraded as follows:")
                print("- from standard web interface")
                print("- from command line with 'opkg' utility")
            raise UpgradeStop
    except subprocess.CalledProcessError:
        pass


def cleanup_system(ssh):
    print("Cleaning remote system...")
    platform.cleanup_system(ssh)


def check_stage3_path(path):
    if not os.path.isdir(path):
        print("Post-upgrade path '{}' is missing or is not a directory!".format(path))
        raise UpgradeStop
    if not os.path.isfile(os.path.join(path, STAGE3_SCRIPT)):
        print("Script '{}' is missing in '{}'!".format(STAGE3_SCRIPT, path))
        raise UpgradeStop


def main(args):
    stage3_user_path = args.post_upgrade
    stage3_builtin_path = None

    if stage3_user_path:
        check_stage3_path(stage3_user_path)
    if os.path.isdir(STAGE3_BUILTIN_DIR):
        check_stage3_path(STAGE3_BUILTIN_DIR)
        stage3_builtin_path = STAGE3_BUILTIN_DIR

    if args.batch:
        try:
            hosts = [row[0].strip() for row in csv.reader(open(args.batch)) if row and row[0].strip()]
        except Exception as ex:
            sys.exit("Invalid input file: %s (%s)" % (args.batch, ex))
        if hosts and hosts[0] == "host":    # possibly skip csv header row
            hosts = hosts[1:]

        # user is not handled at all since we need root
        # ssh wrapper may ask for password based on it's own logic, we just provide default
        if args.install_password:
            password = args.install_password
        else:
            password = getpass('Default password: ') or PASSWORD

        for host in hosts:
            install(args, host, USERNAME, password, stage3_user_path, stage3_builtin_path)
    else:
        install(args, args.hostname, USERNAME, args.install_password or PASSWORD, stage3_user_path, stage3_builtin_path)


def install(args, host, username, password, stage3_user_path, stage3_builtin_path):
    print("Installing %s to %s..." % (get_fw_image_name(), host))
    with SSHManager(host, username, password, load_host_keys=False) as ssh:
        # check compatibility of remote server
        check_compatibility(ssh)

        if args.backup:
            mac = backup.ssh_mac(ssh)
            backup_dir = backup.get_output_dir(mac)
            if not platform.backup_firmware(args, ssh, backup_dir, mac):
                raise UpgradeStop

        # prepare target directory
        ssh.run('rm', '-fr', TARGET_DIR)
        ssh.run('mkdir', '-p', TARGET_DIR)

        # upgrade remote system with missing utilities
        print("Preparing remote system...")
        platform.prepare_system(ssh, SYSTEM_DIR)

        # copy firmware files to the server over SFTP
        sftp = ssh.open_sftp()
        sftp.chdir(TARGET_DIR)
        print("Uploading firmware...")
        upload_local_files(sftp, SOURCE_DIR)
        if stage3_user_path or stage3_builtin_path:
            print("Uploading post-upgrade (stage3)...")
            with tempfile.TemporaryDirectory() as stage3_dir:
                stage3_file = os.path.join(stage3_dir, STAGE3_FILE)
                with tarfile.open(stage3_file, "w:gz") as stage3:
                    if stage3_builtin_path:
                        stage3.add(stage3_builtin_path, STAGE3_DIR)
                    if stage3_user_path:
                        stage3_user_exclude = None
                        if stage3_builtin_path:
                            stage3_user_script_path = os.path.join(stage3_user_path, STAGE3_SCRIPT)
                            stage3.add(stage3_user_script_path, arcname="{}/{}".format(STAGE3_DIR, STAGE3_USER_SCRIPT))
                            stage3_user_exclude = lambda path: path == stage3_user_script_path
                        stage3.add(stage3_user_path, STAGE3_DIR, exclude=stage3_user_exclude)
                    stage3.close()
                    with Progress(STAGE3_FILE, os.path.getsize(stage3_file)) as progress:
                        sftp.put(stage3_file, STAGE3_FILE, callback=progress)
        sftp.close()

        # generate HW identifier for miner
        hw_id = hwid.generate()

        # get other stage1 parameters
        if args.psu_power_limit == 0:
            # 0 is special parameter for disabling autotuning
            psu_power_limit = ''
        else:
            psu_power_limit = args.psu_power_limit or 'default'

        if args.keep_hostname:
            keep_hostname = 'yes'
        elif args.no_keep_hostname:
            keep_hostname = 'no'
        else:
            # keep only user defined hostname and skip factory one (default behaviour)
            keep_hostname = 'cond'

        pool_user = args.pool_user or ''
        keep_network = 'no' if args.no_keep_network else 'yes'
        keep_pools = 'no' if args.no_keep_pools else 'yes'
        dry_run = 'yes' if args.dry_run else 'no'

        # run stage1 upgrade process
        try:
            print("Upgrading firmware...")
            stdout, _ = ssh.run('cd', TARGET_DIR, '&&', 'ls', '-l', '&&',
                                "/bin/sh stage1.sh '{}' '{}' '{}' '{}' '{}' '{}' '{}'"
                                .format(hw_id, pool_user, psu_power_limit, keep_network, keep_hostname, keep_pools,
                                        dry_run))
        except subprocess.CalledProcessError as error:
            cleanup_system(ssh)
            print()
            print("Error log:")
            for line in error.stderr.readlines():
                print(line, end='')
            raise UpgradeStop
        else:
            if args.dry_run:
                cleanup_system(ssh)
                print('Dry run of upgrade was successful!')
                return

            for line in stdout.readlines():
                print(line, end='')
            print('Upgrade was successful!')
            print('Rebooting...', end='')
            try:
                ssh.run('/sbin/reboot')
            except subprocess.CalledProcessError:
                # reboot returns exit status -1
                pass

    if args.no_wait:
        print()
        print('Wait for 120 seconds before the system becomes fully operational!')
    else:
        wait_for_port(host, 80, REBOOT_DELAY)

def get_fw_image_name():
    '''
    :return: Installation image name (when running from the bundle)
    '''
    if getattr(sys, 'frozen', False):
        bos_version_file = os.path.join(get_data_root_path(), 'bos-version.txt')
        f = open(bos_version_file, "r")
        return '{}'.format(f.read()).strip()
    else:
        return "'unknown version - local unpacked unzipped image'"

def build_arg_parser(parser):
    fw_image_name = get_fw_image_name()

    if getattr(sys, 'frozen', False):
        plus = '+' if 'plus' in fw_image_name else ''
        description_suffix = '{} ({})'.format(plus, fw_image_name)
    else:
        description_suffix=' ({})'.format(fw_image_name)

    parser.description = 'Install Braiins OS{} onto a mining machine'.format(
        description_suffix)
    parser_sources = parser.add_mutually_exclusive_group(required=True)
    parser_sources.add_argument('hostname', nargs='?',
                        help='hostname of miner with original firmware')
    parser_sources.add_argument('--batch',
                        help='path to file with list of hosts to install to')
    parser.add_argument('--backup', action='store_true',
                        help='do miner backup before upgrade')
    parser.add_argument('--no-nand-backup', action='store_true',
                        help='skip full NAND backup (config is still being backed up)')
    parser.add_argument('--pool-user', nargs='?',
                        help='set username and workername for default pool')
    parser.add_argument('--psu-power-limit', nargs='?', type=int,
                        help='set PSU power limit (in watts)')
    parser.add_argument('--no-keep-network', action='store_true',
                        help='do not keep miner network configuration (use DHCP)')
    parser.add_argument('--no-keep-pools', action='store_true',
                        help='do not keep miner pool configuration')
    parser.add_argument('--no-keep-hostname', action='store_true',
                        help='do not keep miner hostname and generate new one based on MAC')
    parser.add_argument('--keep-hostname', action='store_true',
                        help='force to keep any miner hostname')
    parser.add_argument('--no-wait', action='store_true',
                        help='do not wait until system is fully upgraded')
    parser.add_argument('--dry-run', action='store_true',
                        help='do all upgrade steps without actual upgrade')
    parser.add_argument('--post-upgrade', nargs='?',
                        help='path to directory with stage3.sh script')
    parser.add_argument('--install-password',
                        help='ssh password for installation')



if __name__ == "__main__":
    # execute only if run as a script
    parser = argparse.ArgumentParser()
    build_arg_parser(parser)
    # parse command line arguments
    args = parser.parse_args(sys.argv[1:])

    try:
        main(args)
    except (KeyboardInterrupt):
        print()
        sys.exit(1)
    except SSHError as e:
        print(str(e))
        sys.exit(1)
    except UpgradeStop:
        sys.exit(2)
    except PlatformStop:
        sys.exit(3)
