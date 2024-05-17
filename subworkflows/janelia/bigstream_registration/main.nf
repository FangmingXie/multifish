include { BIGSTREAM_DEFORM      } from '../../../modules/janelia/bigstream/deform/main'
include { BIGSTREAM_GLOBALALIGN } from '../../../modules/janelia/bigstream/globalalign/main'
include { BIGSTREAM_LOCALALIGN  } from '../../../modules/janelia/bigstream/localalign/main'
include { DASK_START            } from '../dask_start/main'
include { DASK_STOP             } from '../dask_stop/main'

process PREPARE_BIGSTREAM_DIRS {
    label 'process_low'
    container { task.ext.container ?: 'janeliascicomp/bigstream:1.3.0-dask2024.4.1-py11' }

    input:
    tuple val(meta),
          path(global_output, stageAs: 'global/*'),
          path(local_output, stageAs: 'local/*'),
          path(data_paths, stageAs: '?/*')

    output:
    tuple val(meta), env(global_outputpath), env(local_outputpath)

    script:
    def global_output_param = global_output ?: ''
    def local_output_param = local_output ?: ''

    """
    if [[ "${global_output_param}" != "" ]]; then
        global_outputpath=\$(readlink -m ${global_output})

        echo "Create global outputdir: ${global_output} -> \${global_outputpath}"
        mkdir -p \${global_outputpath}
    else
        echo "No global output dir provided"
    fi

    if [[ "${local_output_param}" != "" ]]; then
        local_outputpath=\$(readlink -m ${local_output})

        echo "Create local outputdir: ${local_output} -> \${local_outputpath}"
        mkdir -p \${local_outputpath}
    else
        echo "No local output dir provided"
    fi
    """

}

workflow BIGSTREAM_REGISTRATION {
    take:
    registration_input // [
                       //  meta,
                       //  global_fix, global_fix_subpath, 
                       //  global_mov, global_mov_subpath,
                       //  global_fix_mask, global_fix_mask_subpath
                       //  global_mov_mask, global_mov_mask_subpath
                       //  global_steps
                       //  global_output
                       //  global_transform_name
                       //  global_align_name, global_align_subpath
                       //  local_fix, local_fix_subpath
                       //  local_mov, local_mov_subpath
                       //  local_fix_mask, local_fix_mask_subpath
                       //  local_mov_mask, local_mov_mask_subpath
                       //  local_steps
                       //  local_output
                       //  local_transform_name, local_transform_subpath
                       //  local_inv_transform_name, local_inv_transform_subpath
                       //  local_align_name, local_align_subpath
                       //  additional_deformations - list of tuples where each tuple has: [fix_image_path, fix_image_subpath, fix_image_scale,
                       //                                                                  image_path, image_subpath, image_scale,
                       //                                                                  deformed_image_output_path, deformed_image_output_subpath]
                       //  with_dask
                       //  dask_work_dir
                       //  dask_config
                       //  dask_total_workers
                       //  dask_min_workers
                       //  dask_worker_cpus
                       //  dask_worker_mem_gb
                       //  ]
    registration_config
    global_align_cpus
    global_align_mem_gb
    local_align_cpus
    local_align_mem_gb

    main:
    def bigstream_output_dirs = registration_input
    | map {
        def (meta,
             global_fix, global_fix_subpath, 
             global_mov, global_mov_subpath,
             global_fix_mask, global_fix_mask_subpath,
             global_mov_mask, global_mov_mask_subpath,
             global_steps,
             global_output,
             global_transform_name,
             global_align_name, global_align_subpath,
             local_fix, local_fix_subpath,
             local_mov, local_mov_subpath,
             local_fix_mask, local_fix_mask_subpath,
             local_mov_mask, local_mov_mask_subpath,
             local_steps,
             local_output
            ) = it // there's a lot more in the input but we only look at what we are interested here
        def common_outputs = []
        if (global_output) {
            common_outputs << (global_output as String)
        }
        if (local_output) {
            common_outputs << (local_output as String)
        }
        def r = [
            meta,
            global_output ?: [],
            local_output ?: [],
            common_path(common_outputs, 2),
        ]
        log.debug "Output bigstream dirs: $it -> $r"
        r
    }
    | PREPARE_BIGSTREAM_DIRS

    def global_align_input = bigstream_output_dirs
    | join(registration_input, by:0)
    | map {
        def (meta,
             materialized_global_output, materialized_local_output,
             global_fix, global_fix_subpath, 
             global_mov, global_mov_subpath,
             global_fix_mask, global_fix_mask_subpath,
             global_mov_mask, global_mov_mask_subpath,
             global_steps,
             global_output,
             global_transform_name,
             global_align_name, global_align_subpath
            ) = it // there's a lot more in the input but we only look at what we are interested here
        log.debug "Registration input: $it"
        def r = [
            meta,
            global_fix ?: [], global_fix_subpath,
            global_mov ?: [], global_mov_subpath,
            global_fix_mask ?: [], global_fix_mask_subpath,
            global_mov_mask ?: [], global_mov_mask_subpath,
            global_steps,
            global_output ?: [],
            global_transform_name,
            global_align_name, global_align_subpath,
        ]
        log.debug "Prepare global alignment: $it -> $r"
        return r
    }

    def bigstream_config = as_value_channel(registration_config).map { it ?: [] }

    def global_align_results = BIGSTREAM_GLOBALALIGN(
        global_align_input,
        bigstream_config,
        global_align_cpus,
        global_align_mem_gb,
    )

    global_align_results.subscribe {
        log.debug "Completed global alignment -> $it"
    }

    def cluster_input = global_align_results
    | join(registration_input, by:0) // only start the cluster after global align is done
    | multiMap {
        def (meta,
             global_results_fix, global_results_fix_subpath,
             global_results_mov, global_results_mov_subpath,
             global_results_output,
             global_results_transform,
             global_results_align_name, global_results_align_subpath,
             global_fix, global_fix_subpath, 
             global_mov, global_mov_subpath,
             global_fix_mask, global_fix_mask_subpath,
             global_mov_mask, global_mov_mask_subpath,
             global_steps,
             global_output,
             global_transform_name,
             global_align_name, global_align_subpath,
             local_fix, local_fix_subpath,
             local_mov, local_mov_subpath,
             local_fix_mask, local_fix_mask_subpath,
             local_mov_mask, local_mov_mask_subpath,
             local_steps,
             local_output,
             local_transform_name,
             local_transform_subpath,
             local_inv_transform_name,
             local_inv_transform_subpath,
             local_align_name, local_align_subpath,
             additional_deformations,
             with_dask,
             dask_work_dir,
             dask_config,
             dask_total_workers,
             dask_min_workers,
             dask_worker_cpus,
             dask_worker_mem_gb
             ) = it

        def additional_deformation_data
        if (additional_deformations) {
            additional_deformation_data = additional_deformations
                .collect {
                    def (ref_image_path, ref_image_subpath, ref_image_scale,
                         image_path, image_subpath, image_scale,
                         deformed_image_output_path, deformed_image_output_subpath) = it
                    log.debug "Deform input: ${ref_image_path}, ${ref_image_subpath}, ${ref_image_scale}, ${image_path}, ${image_subpath}, ${image_scale} -> ${deformed_image_output_path}"
                    return (ref_image_path ? [ref_image_path] : []) +
                           (image_path ? [image_path] : []) +
                           (deformed_image_output_path ? [file(deformed_image_output_path).parent] : [])
                }
                .flatten()
        } else {
            additional_deformation_data = []
        }

        def cluster_files =
            (local_fix ? [local_fix] :[]) +
            (local_mov ? [local_mov] :[]) +
            (global_results_output ? [global_results_output] :[]) +
            // local_output may not exist yet so we use the parent
            (local_output ? [file(local_output).parent] : []) +
            (local_fix_mask ? [local_fix_mask] :[]) +
            (local_mov_mask ? [local_mov_mask] :[]) +
            additional_deformation_data

        def cluster_files_set = cluster_files as Set
        log.debug "Cluster files: ${cluster_files_set}"

        def cluster_resources = [
            with_dask ? true : false,
            with_dask ? dask_work_dir : [],
            with_dask ? dask_total_workers : 0,
            with_dask ? dask_min_workers : 0,
            with_dask ? dask_worker_cpus : 0,
            with_dask ? dask_worker_mem_gb : 0
        ]

        log.debug "Cluster resources: $cluster_resources"

        cluster_files: [ meta, cluster_files_set ]
        cluster_resources: cluster_resources
    }

    def cluster_info = DASK_START(
        cluster_input.cluster_files,
        // all the other args will be converted to a value channel
        // by getting the first element only
        cluster_input.cluster_resources.map { it[0] /* with dask */ }.first(),
        cluster_input.cluster_resources.map { it[1] /* work_dir */ }.first(),
        cluster_input.cluster_resources.map { it[2] /* total_workers */ }.first(),
        cluster_input.cluster_resources.map { it[3] /* min_workers */ }.first(),
        cluster_input.cluster_resources.map { it[4] /* worker_cpus */ }.first(),
        cluster_input.cluster_resources.map { it[5] /* worker_mem_gb */ }.first(),
    )

    cluster_info.subscribe {
        log.debug "Dask cluster -> $it"
    }

    def local_align_input = cluster_info
    | join(global_align_results, by: 0)
    | join (registration_input, by: 0)
    | multiMap {
        def (meta,
             cluster_context,
             global_results_fix, global_results_fix_subpath,
             global_results_mov, global_results_mov_subpath,
             global_results_output,
             global_results_transform,
             global_results_align_name, global_results_align_subpath,
             global_fix, global_fix_subpath, 
             global_mov, global_mov_subpath,
             global_fix_mask, global_fix_mask_subpath,
             global_mov_mask, global_mov_mask_subpath,
             global_steps,
             global_output,
             global_transform_name,
             global_align_name, global_align_subpath,
             local_fix, local_fix_subpath,
             local_mov, local_mov_subpath,
             local_fix_mask, local_fix_mask_subpath,
             local_mov_mask, local_mov_mask_subpath,
             local_steps,
             local_output,
             local_transform_name,
             local_transform_subpath,
             local_inv_transform_name,
             local_inv_transform_subpath,
             local_align_name, local_align_subpath,
             additional_deformations,
             with_dask,
             dask_work_dir,
             dask_config
            ) = it
        def data = [
            meta,
            local_fix ?: [], local_fix_subpath,
            local_mov ?: [], local_mov_subpath,
            local_fix_mask ?: [], local_fix_mask_subpath,
            local_mov_mask ?: [], local_mov_mask_subpath,
            global_results_output ?: [],
            global_results_transform,
            local_steps,
            local_output ?: [],
            local_transform_name,
            local_transform_subpath,
            local_inv_transform_name,
            local_inv_transform_subpath,
            local_align_name, local_align_subpath,
        ]
        def cluster = [
            cluster_context.scheduler_address,
            dask_config ?: [],
        ]
        log.debug "Prepare local alignment: $it -> $data, $cluster"
        log.debug "Local alignment data input: $data"
        data: data
        cluster: cluster
    }

    def local_align_results = BIGSTREAM_LOCALALIGN(
        local_align_input.data,
        bigstream_config,
        local_align_input.cluster,
        local_align_cpus,
        local_align_mem_gb,
    )

    local_align_results.subscribe {
        // [
        //    meta, fix, fix_subpath, mov, mov_subpath,
        //    global_output, global_affine
        //    local_output, 
        //    local_deform, local_deform_subpath,
        //    local_inv_deform, local_inv_deform_subpath
        //    warped_name_only, warped_subpath
        //  ]
        log.debug "Completed local alignment -> $it"
    }

    def additional_deformations_input = cluster_info
    | join(local_align_results, by: 0)
    | join(registration_input, by: 0)
    | flatMap {
        def (meta,
             cluster_context,
             local_results_fix, local_results_fix_subpath,
             local_results_mov, local_results_mov_subpath,
             local_results_affine_dir,
             local_results_affine_transform,
             local_results_output,
             local_results_deform_name,
             local_results_deform_subpath,
             local_results_inv_deform_name,
             local_results_inv_deform_subpath,
             local_results_align_name, local_results_align_subpath,
             global_fix, global_fix_subpath, 
             global_mov, global_mov_subpath,
             global_fix_mask, global_fix_mask_subpath,
             global_mov_mask, global_mov_mask_subpath,
             global_steps,
             global_output,
             global_transform_name,
             global_align_name, global_align_subpath,
             local_fix, local_fix_subpath,
             local_mov, local_mov_subpath,
             local_fix_mask, local_fix_mask_subpath,
             local_mov_mask, local_mov_mask_subpath,
             local_steps,
             local_output,
             local_transform_name,
             local_transform_subpath,
             local_inv_transform_name,
             local_inv_transform_subpath,
             local_align_name, local_align_subpath,
             additional_deformations,
             with_dask,
             dask_work_dir,
             dask_config
            ) = it

        if (additional_deformations) {
            additional_deformations.collect {
                def (ref_image_path, ref_image_subpath, ref_image_scale,
                     image_path, image_subpath, image_scale,
                     warped_image_path, warped_image_subpath) = it
                def affine_transform_path
                if (local_results_affine_dir && local_results_affine_transform) {
                    affine_transform_path = file("${local_results_affine_dir}/${local_results_affine_transform}")
                } else {
                    affine_transform_path = []
                }
                def d = [
                    meta,
                    ref_image_path, ref_image_subpath, ref_image_scale,
                    image_path, image_subpath, image_scale,
                    affine_transform_path,
                    file("${local_results_output}/${local_results_deform_name}"), local_results_deform_subpath,
                    warped_image_path, warped_image_subpath,
                    // cluster inputs
                    cluster_context.scheduler_address, dask_config ?: [],
                ]
                log.debug "Additional deformation: $it -> $d"
                d
            }
        } else {
            []
        }
    }

    def additional_deformations_results = BIGSTREAM_DEFORM(
        additional_deformations_input.map { it[0..11]},
        additional_deformations_input.map { it[12..13]},
        local_align_cpus,
        local_align_mem_gb,
    )

    additional_deformations_results.subscribe {
        log.debug "Completed additional deformation -> $it"
    }

    // destroy the cluster
    cluster = cluster_info
    | join(additional_deformations_results.concat(local_align_results), by: 0)
    | groupTuple(by: 0)
    | map {
        def (meta, cluster_context) = it
        [ meta, cluster_context ]
    }
    | DASK_STOP
    | map {
        def (meta, cluster_work_dir) = it
        [
            meta, [:],
        ]
    }

    emit:
    global = global_align_results 
    local = local_align_results
    cluster
}

def as_value_channel(v) {
    if (!v.toString().contains("Dataflow")) {
        Channel.value(v)
    } else if (!v.toString().contains("value")) {
        // if not a value channel return the first value
        v.first()
    } else {
        // this is a value channel
        v
    }
}

def common_path(paths, uplevels) {
    def path_parts = paths.collect { it.split('/') }
    def common_parent = path_parts.transpose().inject([match:true, common_parts:[]]) { aggregator, part ->
        aggregator.match = aggregator.match && part.every { it == part [0] }
        if (aggregator.match) {
            aggregator.common_parts << part[0]
        }
        aggregator
    }.common_parts.join('/')
    def common_parent_dir = common_parent ? file(common_parent) : ''
    while (common_parent_dir && uplevels-- > 0) {
        if (common_parent_dir.parent) {
            common_parent_dir = common_parent_dir.parent
        }
    }
    common_parent_dir ? [common_parent_dir] : []
}
