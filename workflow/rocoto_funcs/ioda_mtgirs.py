#!/usr/bin/env python
import os
from rocoto_funcs.base import xml_task, get_cascade_env

# begin of ioda_mtgirs --------------------------------------------------------


def ioda_mtgirs(xmlFile, expdir):
    task_id = 'ioda_mtgirs'
    cycledefs = 'prod'
    if os.getenv("DO_SPINUP", "FALSE").upper() == "TRUE":
        cycledefs = 'prod,spinup'
    OBSPATH_MTGIRS = os.getenv("OBSPATH_MTGIRS", f'{expdir}/data/mtg_irs')
    # Task-specific EnVars beyond the task_common_vars
    dcTaskEnv = {
        'REFERENCE_TIME': '@Y-@m-@dT@H:00:00Z',
        'YAML_GEN_METHOD': os.getenv('YAML_GEN_METHOD', '1'),
        'OBSPATH_MTGIRS': f'{OBSPATH_MTGIRS}',
        'MTG_IRS_QUADRANTS': os.getenv('MTG_IRS_QUADRANTS', 'Q3 Q4'),
        'MTG_IRS_WINDOW': os.getenv('MTG_IRS_WINDOW', '15'),
        'MTG_IRS_RESOLUTION': os.getenv('MTG_IRS_RESOLUTION', '16'),
    }

    dcTaskEnv['KEEPDATA'] = get_cascade_env(f"KEEPDATA_{task_id}".upper()).upper()

    timedep = ""
    realtime = os.getenv("REALTIME", "false")
    if realtime.upper() == "TRUE":
        starttime = get_cascade_env(f"STARTTIME_{task_id}".upper())
        timedep = f'\n    <timedep><cyclestr offset="{starttime}">@Y@m@d@H@M00</cyclestr></timedep>'

    dependencies = f'''
  <dependency>
  <and>{timedep}
  </and>
  </dependency>'''

    xml_task(xmlFile, expdir, task_id, cycledefs, dcTaskEnv, dependencies)
# end of ioda_mtgirs ----------------------------------------------------------
