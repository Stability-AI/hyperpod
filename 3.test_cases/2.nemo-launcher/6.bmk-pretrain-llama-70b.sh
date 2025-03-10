#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -exo pipefail
[[ -z "${TARGET_PATH}" ]] \
    && { echo Please set environment variable TARGET_PATH ; exit 1 ; } \
    || echo TARGET_PATH=$TARGET_PATH

################################################################################
# 000: Modify this section to define pre-training configuration: model size,
# number of nodes, max. pre-training steps, job's max. runtime.
################################################################################
## Pre-train llama2-7b on 2 nodes for 5 steps
export MODEL=llama
export MODEL_SIZE=llama2_70b
export NUM_NODES=16
export TIME_LIMIT="7-00:00:00"
export MAX_STEPS=100
export MBS=1

declare -a MODEL_ARGS=(
    training.model.micro_batch_size=${MBS}
    training.model.tensor_model_parallel_size=4
    training.model.pipeline_model_parallel_size=4
    training.model.virtual_pipeline_model_parallel_size=20
    training.model.overlap_p2p_comm=True
    training.model.batch_p2p_comm=False
    training.model.gc_interval=0

    training.model.tokenizer.model=${TARGET_PATH}/data/llama2/tokenizer.model

    ## Activation checkpointing
    #training.model.activations_checkpoint_granularity='full'
    #training.model.activations_checkpoint_method='block'
    #training.model.activations_checkpoint_num_layers=1
    #
    ## Not applicable for A100
    #training.model.transformer_engine=False
    #training.model.ub_tp_comm_overlap=False
)


################################################################################
# 010: Advance users can modify this stanza to customize benchmarking behavior.
################################################################################
declare -a BMK_ARGS=(
    # Disable validation, as we're only interested to measure the training time.
    training.trainer.limit_val_batches=0.0

    # Disable wandb_logger
    training.exp_manager.create_wandb_logger=False

    # Ignore checkpoints
    training.exp_manager.create_checkpoint_callback=False
    training.exp_manager.resume_if_exists=False

    ################################

    # https://github.com/NVIDIA/NeMo/pull/6181/files
    training.model.data.data_impl=mock
    training.model.data.data_prefix=[]
)


################################################################################
# 020: Internal settings.
################################################################################
WORKSPACE_CONT=$TARGET_PATH
CONT_RESULT_DIR=${WORKSPACE_CONT}/results-v2
CONT_TOKENIZER_DIR=${WORKSPACE_CONT}/data/bpe

# Dev/test feature (off by default) to force each pre-training run outputs to a separate directory.
: "${UNIQUE_OUTPUT_DIR:=0}"
if [[ ${UNIQUE_OUTPUT_DIR} -eq 1 ]]; then
    # For debugging: each run has its own output dir.
    TIMESTAMP=$(date +'%Y%m%d-%H%M%Sutc-%N')-$((RANDOM))
    CONT_RESULT_DIR=${CONT_RESULT_DIR}-${TIMESTAMP}

    BMK_ARGS+=(base_results_dir=${CONT_RESULT_DIR})

    echo "
    ####################
    This run will write to directory ${CONT_RESULT_DIR}
    ####################
    "
fi


################################################################################
# 030: Here we go...
################################################################################
HYDRA_FULL_ERROR=1 python3 $TARGET_PATH/launcher_scripts/main.py \
    stages=[training] \
    training=${MODEL}/${MODEL_SIZE} \
    training.run.time_limit=$TIME_LIMIT \
    training.trainer.num_nodes=$NUM_NODES \
    training.trainer.max_steps=$MAX_STEPS \
    training.trainer.val_check_interval=$MAX_STEPS \
    "${BMK_ARGS[@]}" "${MODEL_ARGS[@]}" "$@"
