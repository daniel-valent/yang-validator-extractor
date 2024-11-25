# Copyright The IETF Trust 2021, All Rights Reserved
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

__author__ = 'Miroslav Kovac'
__copyright__ = 'Copyright The IETF Trust 2021, All Rights Reserved'
__license__ = 'Apache License, Version 2.0'
__email__ = 'miroslav.kovac@pantheon.tech'

import logging
import os
from pathlib import Path
import typing as t
from datetime import datetime, timezone
from subprocess import CalledProcessError, run, check_output
from time import perf_counter


class LyvParser:
    """
    Cover the parsing of the module with lighty-yang-validator parser and validator
    """

    LYV_CMD = '/home/lyv/lyv'
    try:
        VERSION = (
            check_output(f'{LYV_CMD} -v', shell=True).decode('utf-8').replace("Version: ", "").split("\n")[0].rstrip()
        )
    except CalledProcessError:
        VERSION = 'undefined'
    LOG = logging.getLogger(__name__)

    def __init__(self, context_directories, file_name: str, working_directory: str):
        self._working_directory = working_directory

        # Build the command
        cmds = [self.LYV_CMD, os.path.join(working_directory, file_name)]
        if context_directories:
            cmds.extend(['-p', ":".join(context_directories)])
        self._lyv_cmd = cmds

    def parse_module(self):
        lyv_res: t.Dict[str, t.Union[str, int]] = {'time': datetime.now(timezone.utc).isoformat()}

        self.LOG.info(f'Starting lyv parse using command {" ".join(self._lyv_cmd)}')
        t0 = perf_counter()
        result = run(self._lyv_cmd, capture_output=True, text=True)
        td = perf_counter()-t0

        # LYV returns everything in stdout, even errors. The only thing other than an error it can
        # return is a single line with the html output name, which we don't care about (for now).
        _HTML_GEN_STRING = "html generated to "
        stdout = result.stdout
        for line in stdout.splitlines():
            if line.startswith(_HTML_GEN_STRING):
                htmlpath = Path(line.replace(_HTML_GEN_STRING, ""))
                if htmlpath.is_file():
                    # Remove unnecessary HTML report, but maybe we could display it somehow instead?
                    htmlpath.unlink()
                stdout = stdout.replace(line, "", 1)
                break

        # Post-process results
        dirname = os.path.dirname(self._working_directory)
        lyv_res['stdout'] = stdout.replace(f'{dirname}/', '').strip()
        lyv_res['stderr'] = result.stderr.replace(f'{dirname}/', '').strip()
        lyv_res['name'] = 'lighty-yang-validator'
        lyv_res['version'] = self.VERSION
        lyv_res['code'] = result.returncode
        lyv_res['command'] = ' '.join(self._lyv_cmd)
        lyv_res['validation_time'] = td

        return lyv_res
