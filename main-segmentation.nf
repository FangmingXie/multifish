#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.input_dir = '../multifish-testdata/LHA3_R3_small/stitching/export.n5'
params.acqs = 'LHA3_R3_small'
params.output_dir = '../multifish-testdata/LHA3_R3_small/segmentation'
params.dapi_channel = 'c1'
params.segmentation_scale = 's5'
params.model_dir = ''
params.use_cellpose = true

include {
    get_list_or_default;
} from './param_utils'

include {
    segmentation;
} from './workflows/segmentation'

workflow {

    def input_dirs = get_list_or_default(params, 'input_dir', [])
    def acqs = get_list_or_default(params, 'acqs', [])
    def output_dirs = get_list_or_default(params, 'output_dir', [])

    def segmentation_res = segmentation(
        Channel.fromList(input_dirs).map { file(it) } ,
        Channel.fromList(acqs),
        Channel.fromList(output_dirs).map { file(it) },
        params.dapi_channel,
        params.segmentation_scale,
        Channel.of(params.model_dir),
    )

    segmentation_res | view

}
