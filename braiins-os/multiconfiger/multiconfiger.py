#!/usr/bin/env python3

import sys
import os
import os.path
import argparse
import csv
import json
import urllib.parse
from pprint import pprint
import re

try:
    import requests
except:
    sys.exit('missing requests library')

# these are in roughly same order as in web UI
fields = [
    # pool group
    'host',
    'pool0_user',
    'pool0_password',
    'pool0_url',
    'pool1_user',
    'pool1_password',
    'pool1_url',
    'pool2_user',
    'pool2_password',
    'pool2_url',
    # hashchain global
    'asic_boost',
    'global_frequency',
    'global_voltage',
    # hashchain specifics
    'hashchain6_enabled',
    'hashchain6_frequency',
    'hashchain6_voltage',
    'hashchain7_enabled',
    'hashchain7_frequency',
    'hashchain7_voltage',
    'hashchain8_enabled',
    'hashchain8_frequency',
    'hashchain8_voltage',
    # thermal control
    'thermal_mode',
    'target_temp',
    'hot_temp',
    'dangerous_temp',
    # fanc control
    'fan_speed',
    'fan_min',
    # autotuning
    'autotuning',
    'power_limit',
]


def main(args):

    if args.password == 'prompt':
        from getpass import getpass

        args.password = getpass()

    total = len(open(args.table, 'r').readlines())

    if args.action == 'load':
        tmp_table = args.table + '.tmp'
        reader = csv.DictReader(open(args.table, newline=''), fields, restval='')
        writer = csv.DictWriter(
            open(tmp_table, 'w'), fields, restval='', dialect=reader.dialect
        )
        writer.writerow({k: k for k in fields})

        for line_no, row in enumerate(reader, 1):
            host = row['host']
            out = {'host': host}
            try:
                if (
                    line_no == 1 and host == fields[0] or host == ''
                ):  # skip first line with headers
                    continue
                print('Pulling from %s (%d/%d)' % (host, line_no, total))
                api = BosApi(host, args.user, args.password)
                cfg = api.get_config()

                # output row data
                csvizer = Csvizer(cfg)
                csvizer.pull(out)
                writer.writerow(out)
            except Exception as ex:
                log_error(row)
                if args.ignore:
                    print(str(ex))
                    writer.writerow(out)
                else:
                    raise

        if not args.check:
            # only replace original file once we are all done so as not to clobber it if error occurs
            os.replace(args.table, args.table + '.bak')
            os.replace(tmp_table, args.table)
        else:
            os.unlink(tmp_table)

    elif args.action in ('save', 'save_apply'):
        reader = csv.DictReader(open(args.table, newline=''), fields, restval='')

        for line_no, row in enumerate(reader, 1):
            try:
                host = row['host']
                if line_no == 1 and host == fields[0] or host == '':
                    continue
                print('Pushing to %s (%d/%d)' % (host, line_no, total))

                api = BosApi(host, args.user, args.password)
                cfg = api.get_config()
                csvizer = Csvizer(cfg)
                csvizer.push(row)
                if not args.check:
                    api.set_config(csvizer.cfg)
                    if args.action == 'save_apply':
                        api.apply_config()
            except Exception as ex:
                log_error(row)
                if args.ignore:
                    print(str(ex))
                else:
                    raise

    elif args.action == 'apply':
        reader = csv.DictReader(open(args.table, newline=''), fields, restval='')
        for line_no, row in enumerate(reader, 1):
            try:
                host = row['host']
                if (
                    line_no == 1 and host == fields[0] or host == ''
                ):  # skip first line with headers
                    continue
                print('Applying on %s (%d/%d)' % (host, line_no, total))
                api = BosApi(host, args.user, args.password)
                if not args.check:
                    api.apply_config()
            except Exception as ex:
                log_error(row)
                if args.ignore:
                    print(str(ex))
                else:
                    raise

    else:
        raise RuntimeError('unknown action')


class Csvizer:
    GROUP_SIZE = 3  # how many pools to have in our group
    DEFAULT_GROUP = {'name': 'default', 'pool': []}  # defaults for created pool group

    def __init__(self, cfg):
        # json struct with config to work on
        self.cfg = cfg

    def pull(self, row):
        """
        Gather data from existing config into dict suitable for csvwriter.
        row: dict to be populated with values pulled from config
        """
        self.pull_groups(row)
        self.pull_hashchain_global(row)
        self.pull_autotuning(row)
        self.pull_fanctl(row)
        self.pull_tempctl(row)
        # hashchains are currently hardcoded in bosminer
        self.pull_hashchain(row, 6)
        self.pull_hashchain(row, 7)
        self.pull_hashchain(row, 8)

    def push(self, row):
        """
        Use data in dict to update existing config.
        row: dict to be populated with values pulled from config
        """
        self.push_groups(row)
        self.push_hashchain_global(row)
        self.push_autotuning(row)
        self.push_fanctl(row)
        self.push_tempctl(row)
        self.push_hashchain(row, 6)
        self.push_hashchain(row, 7)
        self.push_hashchain(row, 8)

    # pools --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_groups(self, row):
        """
        row: dict to be populated with values pulled from config
        for now, only four pools in first group are considered, rest is ignored
        """
        if 'group' in self.cfg:
            # gather the first group, rest is ignored
            for i, pool in enumerate(
                self.cfg['group'][0].get('pool', [])[: self.GROUP_SIZE]
            ):
                row['pool%d_url' % i] = pool.get('url')
                row['pool%d_user' % i] = pool.get('user')
                row['pool%d_password' % i] = pool.get('password')

    def push_groups(self, row):
        """
        row: dict to pull new values from
        no fancy merging yet, if there is anything in four pools in csv, first group is overwriten with that
        """
        if 'group' not in self.cfg:
            self.cfg['group'] = [{'name': 'default', 'pool': []}]
        pools = []
        for i in range(self.GROUP_SIZE):
            pool = {
                'enabled': True,
                'user': row.get('pool%d_user' % i, ''),
                'password': row.get('pool%d_password' % i, ''),
                'url': str2url(row.get('pool%d_url' % i, '')),
            }
            if pool['url'] and pool['user']:
                pools.append(pool)
            elif pool['url'] and not pool['user']:
                raise InvalidUser('(unspecified)')
            elif not pool['url'] and pool['user']:
                raise InvalidUrl('(unspecified)')
            else:
                pass  # neither url nor user == just ignore this
        if pools:
            self.cfg.setdefault('group', [self.DEFAULT_GROUP])[0]['pool'] = pools

    # autotuning --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_autotuning(self, row):
        """
        row: dict to be populated with values pulled from config
        Otherwise logic is reverse of push.
        """
        row['autotuning'] = toggle2str(
            self.cfg.get('autotuning', {}).get('enabled', '')
        )
        row['power_limit'] = power_limit = self.cfg.get('autotuning', {}).get(
            'psu_power_limit', 0
        )

    def push_autotuning(self, row):
        """
        row: dict to pull new values from
        Depending on power_limit column:
            zero = disable autotuning,
            empty = enable with default wattage
            other number = fixed wattage
        """
        enabled = str2toggle(row['autotuning'])
        power_limit = str2int(row['power_limit'], allow_empty=True)

        if enabled is not None:
            self.cfg.setdefault('autotuning', {})['enabled'] = enabled
        if power_limit is not None:
            self.cfg.setdefault('autotuning', {})['psu_power_limit'] = power_limit

    # fan control --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_fanctl(self, row):
        """
        row: dict to be populated with values pulled from config
        """
        row['fan_speed'] = self.cfg.get('fan_control', {}).get('speed', '')
        row['fan_min'] = self.cfg.get('fan_control', {}).get('min_fans', '')

    def push_fanctl(self, row):
        """
        row: dict to pull new values from
        TODO: how to handle empty fields?
        """

        speed = str2int(row['fan_speed'], allow_empty=True)
        if speed is not None:
            self.cfg.setdefault('fan_control', {})['speed'] = speed

        min_fans = str2int(row['fan_min'], allow_empty=True)
        if min_fans is not None:
            self.cfg.setdefault('fan_control', {})['min_fans'] = min_fans

    # thermal  --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_tempctl(self, row):
        """
        row: dict to be populated with values pulled from config
        """
        row['thermal_mode'] = self.cfg.get('temp_control', {}).get('mode', '')
        row['target_temp'] = self.cfg.get('temp_control', {}).get('target_temp', '')
        row['hot_temp'] = self.cfg.get('temp_control', {}).get('hot_temp', '')
        row['dangerous_temp'] = self.cfg.get('temp_control', {}).get(
            'dangerous_temp', ''
        )

    def push_tempctl(self, row):
        """
        row: dict to pull new values from
        TODO: how to handle empty fields again?
        """
        mode = row['thermal_mode'].strip().lower()
        if mode not in ('auto', 'manual', 'disabled', ''):
            raise InvalidThermalMode(mode)
        target_temp = str2float(row['target_temp'], allow_empty=True)
        hot_temp = str2float(row['hot_temp'], allow_empty=True)
        dangerous_temp = str2float(row['dangerous_temp'], allow_empty=True)

        if mode:
            self.cfg.setdefault('temp_control', {})['mode'] = mode
        if target_temp is not None:
            self.cfg.setdefault('temp_control', {})['target_temp'] = target_temp
        if hot_temp is not None:
            self.cfg.setdefault('temp_control', {})['hot_temp'] = hot_temp
        if dangerous_temp is not None:
            self.cfg.setdefault('temp_control', {})['dangerous_temp'] = dangerous_temp

    # global hashchain  --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_hashchain_global(self, row):
        """
        row: dict to be populated with values pulled from config
        """
        row['asic_boost'] = toggle2str(
            self.cfg.get('hash_chain_global', {}).get('asic_boost')
        )
        row['global_frequency'] = self.cfg.get('hash_chain_global', {}).get(
            'frequency', ''
        )
        row['global_voltage'] = self.cfg.get('hash_chain_global', {}).get('voltage', '')

    def push_hashchain_global(self, row):
        """
        row: dict to pull new values from
        TODO: how to handle empty fields again?
        """
        asic_boost = str2toggle(row['asic_boost'])
        frequency = str2float(row['global_frequency'], allow_empty=True)
        voltage = str2float(row['global_voltage'], allow_empty=True)

        if asic_boost is not None:
            self.cfg.setdefault('hash_chain_global', {})['asic_boost'] = asic_boost
        if frequency is not None:
            self.cfg.setdefault('hash_chain_global', {})['frequency'] = frequency
        if voltage is not None:
            self.cfg.setdefault('hash_chain_global', {})['voltage'] = voltage

    # specific hashchain  --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
    def pull_hashchain(self, row, chain):
        """
        row: dict to be populated with values pulled from config
        chain: chain number (6-8)
        """
        hash_chain = self.cfg.get('hash_chain', {}).get(str(chain), {})
        row['hashchain%d_enabled' % chain] = toggle2str(hash_chain.get('enabled'))
        row['hashchain%d_frequency' % chain] = hash_chain.get('frequency', '')
        row['hashchain%d_voltage' % chain] = hash_chain.get('voltage', '')

    def push_hashchain(self, row, chain):
        """
        row: dict to pull new values from
        chain: chain number (6-8)
        """
        enabled = str2toggle(row['hashchain%d_enabled' % chain])
        frequency = str2float(row['hashchain%d_frequency' % chain], allow_empty=True)
        voltage = str2float(row['hashchain%d_voltage' % chain], allow_empty=True)

        if enabled is not None:
            self.cfg.setdefault('hash_chain', {}).setdefault(str(chain), {})[
                'enabled'
            ] = enabled
        if frequency is not None:
            self.cfg.setdefault('hash_chain', {}).setdefault(str(chain), {})[
                'frequency'
            ] = frequency
        if voltage is not None:
            self.cfg.setdefault('hash_chain', {}).setdefault(str(chain), {})[
                'voltage'
            ] = voltage


class CsvizerError(RuntimeError):
    def __str__(self):
        return '%s: %s' % (self.hint, self.args[0])


class InvalidNumber(CsvizerError):
    hint = 'invalid number'


class InvalidThermalMode(CsvizerError):
    hint = 'invalid thermal mode'


class InvalidToggle(CsvizerError):
    hint = 'invalid toggle'


class InvalidUrl(CsvizerError):
    hint = 'invalid pool url'


class InvalidUser(CsvizerError):
    hint = 'invalid pool user'


class BosApi:
    """
    Wrapper over bosminer json api. It's main function is to get and hold authentication cookie.
    """

    timeout = 3

    def __init__(self, host, username='root', password=''):
        self.host = host
        self.username = username
        self.password = password
        self.auth()

    def check_config(self, data):
        """Check if retrieved config is in known format"""
        try:
            if data['format']['model'] != 'Antminer S9':
                raise UnsupportedDevice(data['format']['model'])
            if data['format']['version'] not in ('1.0', '1.0+'):
                raise UnsupportedVersion(data['format']['version'])

        except KeyError as ex:
            raise ConfigStructError(str(ex))

    def get_url(self, path):
        """Construct api url from known hostname and given path"""
        url = urllib.parse.urlunsplit(
            ('http', self.host, path, '', '')  # query  # fragment
        )
        return url

    def auth(self):
        response = requests.post(
            self.get_url('/cgi-bin/luci/'),
            data={'luci_username': self.username, 'luci_password': self.password},
            allow_redirects=False,
            timeout=self.timeout,
        )
        response.raise_for_status()
        self.authcookie = response.cookies.copy()

    def get_config(self):
        response = requests.get(
            self.get_url('/cgi-bin/luci/admin/miner/cfg_data'),
            cookies=self.authcookie,
            timeout=self.timeout,
        )
        response.raise_for_status()
        document = response.json()
        if document.get('status', {}).get('code') != 0:
            raise ConfigFetchFailed(document)
        self.check_config(document.get('data'))
        return document['data']
        print(response.content)

    def set_config(self, data):
        data['format']['generator'] = 'multiconfiger 0.1'  #
        response = requests.post(
            self.get_url('/cgi-bin/luci/admin/miner/cfg_save'),
            cookies=self.authcookie,
            data=json.dumps({'data': data}),
            timeout=self.timeout,
        )
        response.raise_for_status()
        document = response.json()
        if document.get('status', {}).get('code') != 0:
            raise ConfigStoreFailed(document)
        # print(response.content)

    def apply_config(self):
        response = requests.post(
            self.get_url('/cgi-bin/luci/admin/miner/cfg_apply'),
            cookies=self.authcookie,
            allow_redirects=False,
            timeout=self.timeout,
        )
        response.raise_for_status()
        document = response.json()
        if document.get('status', {}).get('code') != 0:
            raise ConfigApplyFailed(document)


class BosApiError(RuntimeError):
    pass


class ErrorResponse(BosApiError):
    def __init__(self, document):
        super().__init__(
            '%s (%s)'
            % (
                document.get('status', {}).get('code'),
                document.get('status', {}).get('message'),
            )
        )


class UnsupportedDevice(BosApiError):
    pass


class UnsupportedVersion(BosApiError):
    pass


class ConfigStructError(BosApiError):
    pass


class ConfigFetchFailed(ErrorResponse):
    hint = 'configuration load failed'


class ConfigStoreFailed(ErrorResponse):
    hint = 'configuration save failed'


class ConfigApplyFailed(ErrorResponse):
    hint = 'miner state change failed'


# --- helper functions --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
def str2int(s, exception=InvalidNumber, message=None, allow_empty=False):
    """
    Helper function to raise an error if conversion from string to int fails
    """
    if allow_empty and s.strip() == '':
        return None
    try:
        return int(s)
    except ValueError:
        raise exception(message or s)


def str2float(s, exception=InvalidNumber, message=None, allow_empty=False):
    """
    Helper function to raise an error if conversion from string to float fails
    """
    if allow_empty and s.strip() == '':
        return None
    try:
        return float(s)
    except ValueError:
        raise exception(message or s)


def str2toggle(b):
    """
    Turn 'enabled' or 'disabled' strings into bool, or empty string into None
    Exception is thrown for other values.
    """
    b = b.strip().lower()
    if b == '':
        return None
    elif b == 'disabled':
        return False
    elif b == 'enabled':
        return True
    raise InvalidToggle(b)


def toggle2str(b):
    """
    Turn bool config value into enabled/disabled string.
    None is returned as empty string, which should represent value not present.
    (which is why this is not called bool2str)
    """
    return {None: '', False: 'disabled', True: 'enabled'}[b]


def str2url(u):
    """
    Turns string unto url, which is string again so ti does not do anything really.
    But it checks validity, so we can throw more reasonable error then what server does.
    """
    # TODO: this can be dropped once server error messages get better then rust panics
    if u == '':
        return None

    if re.match(
        r'(?:drain|(?:stratum2?\+tcp(?:\+insecure)?)):\/\/[\w\.-]+(?::\d+)?(?:\/[\dA-HJ-NP-Za-km-z]+)?',
        u,
    ):
        return u

    raise InvalidUrl(u)

    if u.strip() == '':
        return None
    parsed = urllib.parse.urlparse(u)
    if parsed.scheme not in ('stratum+tcp', 'stratum2+tcp'):
        raise InvalidUrl(u)
    if parsed.netloc == '':
        raise InvalidUrl(u)


def log_error(data=None):
    import traceback
    import time

    with open('error.log', 'a') as fd:
        print(
            time.strftime('%y-%m-%d %H:%M:%S')
            + (' '.join(sys.argv) if log_error.count == 0 else ''),
            file=fd,
        )
        if data:
            print(data, file=fd)
        traceback.print_exc(file=fd)


log_error.count = 0


def build_arg_parser(parser):
    parser.description = 'Configure mining machines running Braiins OS or Braiins OS+'
    parser.add_argument(
        'action',
        type=lambda x: x.strip().lower(),
        help='Load, save, apply or save_apply',
    )
    parser.add_argument('table', help='Path to table file in csv format')
    parser.add_argument('-u', '--user', default='root', help='Administration username')
    parser.add_argument(
        '-p', '--password', default='', help='Administration password or "prompt"'
    )
    parser.add_argument(
        '-c', '--check', action='store_true', help='Dry run sans writes'
    )
    parser.add_argument('-i', '--ignore', action='store_true', help='No halt on errors')


if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser()
        build_arg_parser(parser)
        args = parser.parse_args()
        main(args)
    except ErrorResponse as ex:
        # error messages inside responses can be very ugly with rust panic strings
        # handle them with special care until they get better
        log_error()
        sys.exit('error: %s' % ex.hint)
    except Exception as ex:
        log_error()
        sys.exit('error: %s' % ex)
