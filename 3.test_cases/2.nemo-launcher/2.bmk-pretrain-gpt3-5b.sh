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
## Pre-train gpt3-5b on 2 nodes for 5 steps
export MODEL=gpt3
export MODEL_SIZE=5b
export NUM_NODES=2
export RUNTIME=4h
export MAX_STEPS=30
export MBS=2 # setting for A100 80GB (p4de, p5), reduce to 1 for A100 40GB (p4d)
declare -a MODEL_ARGS=(
    training.model.micro_batch_size=${MBS}

    # When node_count < 8, needs full activations checkpointing. These're settings found on
    # Nemo repo's Jenkin script.
    #
    # Below settings is similar to 22.09, except that 22.09 funnily didn't OOM with
    # activations_checkpoint_num_layers=0.
    training.model.activations_checkpoint_granularity='full'
    training.model.activations_checkpoint_method='block'
    training.model.activations_checkpoint_num_layers=1
)


################################################################################
# 010: Advance users can modify this stanza to customize benchmarking behavior.
################################################################################
declare -a BMK_ARGS=(
    # Disable validation, as we're only interested to measure the training time.
    training.trainer.limit_val_batches=0.0

    # Ignore checkpoints
    training.exp_manager.create_checkpoint_callback=False
    training.exp_manager.resume_if_exists=False

    # https://github.com/NVIDIA/NeMo/pull/6181/files
    training.model.data.data_impl=mock
    training.model.data.data_prefix=[]
)


################################################################################
# 020: Internal settings.
################################################################################
WORKSPACE_CONT=$TARGET_PATH
CONT_RESULT_DIR=${WORKSPACE_CONT}/results
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
    training.trainer.num_nodes=$NUM_NODES \
    training.trainer.max_steps=$MAX_STEPS \
    training.trainer.val_check_interval=$MAX_STEPS \
    "${BMK_ARGS[@]}" "${MODEL_ARGS[@]}" "$@"
