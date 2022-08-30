"""
1-D column test with reinjection
"""

import argparse
import os
import sys

import matplotlib
matplotlib.use('Agg')

from credo.systest import SciBenchmarkTest

from credo.jobrunner import SimpleJobRunner
from credo.t2model import T2ModelRun, T2ModelResult
from credo.waiwera import WaiweraModelRun

import credo.reporting.standardReports as sReps
from credo.reporting import getGenerators

from credo.systest import FieldWithinTolTC
from credo.systest import HistoryWithinTolTC

from mulgrids import mulgrid
from t2listing import t2listing

import matplotlib.pyplot as plt
from matplotlib import rcParams
rcParams['mathtext.default'] = 'regular'

import numpy as np
import json
from docutils.core import publish_file

parser = argparse.ArgumentParser()
parser.add_argument("-np", type = int, default = 1, help = "number of processes")
parser.add_argument("-d", "--docker", action = "store_true",
                    help = "run via Docker (waiwera-dkr)")
args = parser.parse_args()
mpi = args.np > 1 and not args.docker
simulator = 'waiwera-dkr -np %d' % args.np if args.docker else 'waiwera'

model_name = 'reinjection'

AUTOUGH2_FIELDMAP = {
    'Vapour saturation': 'Vapour saturation',
    'Temperature': 'Temperature',
    'Rate': 'Generation rate'}
WAIWERA_FIELDMAP = {
    'Pressure': 'fluid_pressure',
    'Temperature': 'fluid_temperature',
    'Vapour saturation': 'fluid_vapour_saturation',
    'Rate': 'source_rate'}

model_dir = './run'
t2geo_filename = os.path.join(model_dir, 'g' + model_name + '.dat')
geo = mulgrid(t2geo_filename)

run_name = 'run'
run_index = 0

test_fields = ['Pressure', 'Temperature', 'Vapour saturation']
plot_fields = test_fields
test_source_fields = ['Rate']
field_scale = {'Pressure': 1.e5, 'Temperature': 1., 'Vapour saturation': 1.,
               'Rate': 1.0, 'Enthalpy': 1.e3}
field_unit = {'Pressure': 'bar', 'Temperature': '$^{\circ}$C', 'Vapour saturation': '',
              'Rate': 'kg/s', 'Enthalpy': 'kJ/kg'}

reinjection_test = SciBenchmarkTest(model_name + "_test", nproc = args.np)
reinjection_test.description = """1-D column problem, production run with reinjection, starting from steady-state solution.
"""

base_path = os.path.realpath(model_dir)
run_base_name = model_name
run_filename = run_base_name + '.json'
model_run = WaiweraModelRun(run_name, run_filename,
                            fieldname_map = WAIWERA_FIELDMAP,
                            simulator = simulator,
                            basePath = base_path)
model_run.jobParams['nproc'] = args.np
reinjection_test.mSuite.addRun(model_run, run_name)

obs_cell_elev = -350.
obs_position = np.array([50., 50., obs_cell_elev])
obs_blk = geo.block_name_containing_point(obs_position)
obs_cell_index = geo.block_name_index[obs_blk] - geo.num_atmosphere_blocks
source_indices = [1, 2, 3, 4, 5, 6, 7]
map_out_atm = list(range(geo.num_atmosphere_blocks, geo.num_blocks))

reinjection_test.setupEmptyTestCompsList()
AUTOUGH2_result = {}
results_filename = os.path.join(model_dir, run_base_name + ".listing")

AUTOUGH2_result[run_name] = T2ModelResult("AUTOUGH2", results_filename,
                                geo_filename = t2geo_filename,
                                fieldname_map = AUTOUGH2_FIELDMAP,
                                ordering_map = map_out_atm)
reinjection_test.addTestComp(run_index, "AUTOUGH2",
                        FieldWithinTolTC(fieldsToTest = test_fields,
                                         defFieldTol = 0.02,
                                         expected = AUTOUGH2_result[run_name],
                                         testOutputIndex = -1))
reinjection_test.addTestComp(run_index, "AUTOUGH2 history",
                        HistoryWithinTolTC(fieldsToTest = test_fields,
                                           defFieldTol = 0.015,
                                           expected = AUTOUGH2_result[run_name],
                                           testCellIndex = obs_cell_index))
for source_index in source_indices:
    reinjection_test.addTestComp(run_index, "AUTOUGH2 source %d" % source_index,
                            HistoryWithinTolTC(fieldsToTest = test_source_fields,
                                               defFieldTol = 0.06,
                                               expected = AUTOUGH2_result[run_name],
                                               testSourceIndex = source_index))

jrunner = SimpleJobRunner(mpi = mpi)
testResult, mResults = reinjection_test.runTest(jrunner, createReports = True)

day = 24. * 60. * 60.

for field_name in test_source_fields:
    for source_index in source_indices:
        scale = field_scale[field_name]
        unit = field_unit[field_name]
        t, var = reinjection_test.mSuite.resultsList[run_index].\
                 getFieldHistoryAtSource(field_name, source_index)
        plt.plot(t / day, var / scale, '-', label = 'Waiwera', zorder = 3)

        t, var = AUTOUGH2_result[run_name].getFieldHistoryAtSource(field_name, source_index)
        plt.plot(t[::2] / day, var[::2] / scale, 's', label = 'AUTOUGH2', zorder = 2)

        plt.xlabel('time (days)')
        plt.ylabel(field_name + ' (' + unit + ')')
        plt.legend(loc = 'best')
        plt.title(' '.join((field_name, 'history at well ' + str(source_index))))
        img_filename_base = '_'.join((model_name, run_name, 'history',
                                      field_name, str(source_index)))
        img_filename_base = img_filename_base.replace(' ', '_')
        img_filename = os.path.join(reinjection_test.mSuite.runs[run_index].basePath, reinjection_test.mSuite.outputPathBase,
                                    img_filename_base)
        plt.tight_layout(pad = 3.)
        plt.savefig(img_filename + '.png', dpi = 300)
        plt.savefig(img_filename + '.pdf')
        plt.clf()
        reinjection_test.mSuite.analysisImages.append(img_filename + '.png')

# generate report:

for rGen in getGenerators(["RST"], reinjection_test.outputPathBase):
    report_filename = os.path.join(reinjection_test.outputPathBase,
                     "%s-report.%s" % (reinjection_test.testName, rGen.stdExt))
    sReps.makeSciBenchReport(reinjection_test, mResults, rGen, report_filename)
    html_filename = os.path.join(reinjection_test.outputPathBase,
                     "%s-report.%s" % (reinjection_test.testName, 'html'))
    html = publish_file(source_path = report_filename,
                        destination_path = html_filename,
                        writer_name = "html")
