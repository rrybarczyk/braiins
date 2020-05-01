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
import sys

import upgrade2bos
import restore2factory
import discover
import multiconfiger

from upgrade.platform import PlatformStop
from upgrade.ssh import SSHError


def add_tool(subparsers, tool):
    """
    Register a new tool into the toolbox
    :param tool: tuple containing tool name used as subcommand and the actual tool module
    :return:
    """
    (name, module) = tool
    parser = subparsers.add_parser(name)
    parser.set_defaults(func=module.main)
    module.build_arg_parser(parser)


def get_version():
    try:
        import version

        return version.toolbox
    except ModuleNotFoundError:
        return 'devel'


if __name__ == '__main__':
    # execute only if run as a script
    parser = argparse.ArgumentParser(
        description='Provides tools for managing mining '
        'devices running Braiins OS and '
        'Braiins OS+'
    )
    parser.add_argument(
        '--version', action='version', version='%(prog)s {}'.format(get_version())
    )
    subparsers = parser.add_subparsers(
        title='subcommands',
        description='Braiins OS tools in the ' 'toolbox',
        help='Choose one of the tools and run '
        'with --help to retrieve additional info '
        'how to use it',
    )

    for t in [
        ('install', upgrade2bos),
        ('uninstall', restore2factory),
        ('discover', discover),
        ('config', multiconfiger),
    ]:
        add_tool(subparsers, t)

    # parse command line arguments
    args = parser.parse_args(sys.argv[1:])

    # Python3 workaround https://bugs.python.org/issue16308
    try:
        func = args.func
    except AttributeError:
        parser.print_help(sys.stderr)
        sys.exit(1)

    try:
        args.func(args)
    except KeyboardInterrupt:
        print()
        sys.exit(1)
    except SSHError as e:
        print(str(e))
        sys.exit(1)
    except upgrade2bos.UpgradeStop:
        sys.exit(2)
    except restore2factory.RestoreStop:
        sys.exit(3)
    except PlatformStop:
        sys.exit(4)
