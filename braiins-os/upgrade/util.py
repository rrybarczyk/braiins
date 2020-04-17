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

import sys

def get_data_root_path():
    '''
    Provides the true root path for all files referenced in the code. The
    Tools bundled into a standalone executable by pyinstaller have the necessary local
    files built into the binary. These will be extracted upon startup of the binary.
    See: https://pyinstaller.readthedocs.io/en/stable/spec-files.html#adding-files-to-the-bundle
    :return: empty string if we are not running from a bundle
    '''
    if getattr(sys, 'frozen', False):
        return sys._MEIPASS
    else:
        return ''
