#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.

[ ! -f ./lang.conf ] && echo "Language configuration does not exist! Use the configurations in conf/lang/* as a startup" && exit 1
[ ! -f ./conf/common_vars.sh ] && echo "the file conf/common_vars.sh does not exist!" && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

type=dev10h
dev2shadow=dev10h
eval2shadow=eval
data_only=false
fast_path=true
skip_kws=false
skip_stt=false
max_states=150000
wip=0.5
stage=-10
train_after_reseg=false
segmentation_opts="--remove-noise-only-segments false --split-on-noise-transitions true" 

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

[ -e exp ] || ln -s "$exp_dir" exp

if [[ "$type" != "dev10h" && "$type" != "dev2h" && "$type" != "eval" && "$type" != "shadow" ]] ; then
  echo "Warning: invalid variable type=${type}, valid values are dev10h|dev2h|eval"
  echo "Hope you know what your ar doing!"
fi

if [ $type == shadow ] ; then
  shadow_set_extra_opts=(--dev2shadow data/${dev2shadow} --eval2shadow data/${eval2shadow} )
else
  shadow_set_extra_opts=()
fi

function make_plp {
  t=$1
  use_pitch=false
  use_ffv=false

  if [ "$use_pitch" = "false" ] && [ "$use_ffv" = "false" ]; then
   steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t} exp/make_plp/${t} plp
  elif [ "$use_pitch" = "true" ] && [ "$use_ffv" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_pitch; cp -rT data/${t} data/${t}_ffv
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_pitch.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_pitch exp/make_pitch/${t} pitch_tmp_${t}
    local/make_ffv.sh --cmd "$decode_cmd"  --nj $my_nj data/${t}_ffv exp/make_ffv/${t} ffv_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_pitch,_plp_pitch} exp/make_pitch/append_${t}_pitch plp_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp_pitch,_ffv,} exp/make_ffv/append_${t}_pitch_ffv plp
    rm -rf {plp,pitch,ffv}_tmp_${t} data/${t}_{plp,pitch,plp_pitch}
  elif [ "$use_pitch" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_pitch
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_pitch.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_pitch exp/make_pitch/${t} pitch_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_pitch,} exp/make_pitch/append_${t} plp
    rm -rf {plp,pitch}_tmp_${t} data/${t}_{plp,pitch}
  elif [ "$use_ffv" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_ffv
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_ffv.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_ffv exp/make_ffv/${t} ffv_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_ffv,} exp/make_ffv/append_${t} plp
    rm -rf {plp,ffv}_tmp_${t} data/${t}_{plp,ffv}
  fi

  steps/compute_cmvn_stats.sh data/${t} exp/make_plp/${t} plp
  utils/fix_data_dir.sh data/${t}
}

if [ ${type} == shadow ] ; then
  mandatory_variables=""
  optional_variables=""
else
  mandatory_variables="${type}_data_dir ${type}_data_list ${type}_stm_file \
    ${type}_ecf_file ${type}_kwlist_file ${type}_rttm_file ${type}_nj"
  optional_variables="${type}_subset_ecf "
fi

eval my_data_dir=\$${type}_data_dir
eval my_data_list=\$${type}_data_list
eval my_stm_file=\$${type}_stm_file


eval my_ecf_file=\$${type}_ecf_file 
eval my_subset_ecf=\$${type}_subset_ecf 
eval my_kwlist_file=\$${type}_kwlist_file 
eval my_rttm_file=\$${type}_rttm_file
eval my_nj=\$${type}_nj  #for shadow, this will be re-set when appropriate

for variable in $mandatory_variables ; do
  eval my_variable=\$${variable}
  if [ -z $my_variable ] ; then
    echo "Mandatory variable $variable is not set! " \
         "You should probably set the variable in the config file "
    exit 1
  else
    echo "$variable=$my_variable"
  fi
done

for variable in $option_variables ; do
  eval my_variable=\$${variable}
  echo "$variable=$my_variable"
done

datadir=data/${type}
dirid=${type}

if [[ $type == shadow ]] ; then
  if [ ! -f ${datadir}/shadow.done ]; then
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data/${dev2shadow}/.done ]; then
      echo "Error: data/${dev2shadow}/.done does not exist."
      echo "Create the directory data/${dev2shadow} first, by calling $0 --type $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data/${eval2shadow}/.done ]; then
      echo "Error: data/${eval2shadow}/.done does not exist."
      echo "Create the directory data/${eval2shadow} first, by calling $0 --type $eval2shadow --dataonly"
      exit 1
    fi

    local/create_shadow_dataset.sh ${datadir} data/${dev2shadow} data/${eval2shadow}
    utils/fix_data_dir.sh ${datadir}
    touch ${datadir}/shadow.done
  fi
  my_nj=$eval_nj
else
  if [ ! -d data/raw_${type}_data ]; then
    echo ---------------------------------------------------------------------
    echo "Subsetting the ${type} set"
    echo ---------------------------------------------------------------------
    
    local/make_corpus_subset.sh "$my_data_dir" "$my_data_list" ./data/raw_${type}_data
  fi
  my_data_dir=`readlink -f ./data/raw_${type}_data`

  nj_max=`cat $my_data_list | wc -l`
  if [[ "$nj_max" -lt "$my_nj" ]] ; then
    echo "The maximum reasonable number of jobs is $nj_max -- you have $my_nj! (The training and decoding process has file-granularity)"
    exit 1
    my_nj=$nj_max
  fi

  if [ ! -f ${datadir}/.done ]; then
    if [[ ! -f ${datadir}/wav.scp || ${datadir}/wav.scp -ot "$my_data_dir" ]]; then
      echo ---------------------------------------------------------------------
      echo "Preparing ${type} data lists in ${datadir} on" `date`
      echo ---------------------------------------------------------------------
      mkdir -p ${datadir}
      local/prepare_acoustic_training_data.pl --fragmentMarkers \-\*\~  \
        $my_data_dir ${datadir} > ${datadir}/skipped_utts.log || exit 1
    fi

    echo ---------------------------------------------------------------------
    echo "Preparing ${type} stm files in ${datadir} on" `date`
    echo ---------------------------------------------------------------------
    if [ ! -z $my_stm_file ] ; then
      local/augment_original_stm.pl $my_stm_file ${datadir}
    elif [[ $type == shadow || $type == eval ]]; then
      echo "Not doing anything for the STM file!"
    else
      local/prepare_stm.pl --fragmentMarkers \-\*\~ ${datadir}
    fi

    if [ ! -f ${datadir}/.plp.done ]; then
      echo ---------------------------------------------------------------------
      echo "Preparing ${type} parametrization files in ${datadir} on" `date`
      echo ---------------------------------------------------------------------
      make_plp ${dirid}
      touch ${datadir}/.plp.done
    fi

    touch ${datadir}/.done
  fi
fi

#####################################################################
#
# data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${type} kws data files in ${datadir} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws  && [ ! -f ${datadir}/kws/.done ] ; then
  if [[ $type == shadow ]]; then
    
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data/${dev2shadow}/kws/.done ]; then
      echo "Error: data/${dev2shadow}/kws/.done does not exist."
      echo "Create the directory data/${dev2shadow} first, by calling $0 --type $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data/${eval2shadow}/kws/.done ]; then
      echo "Error: data/${eval2shadow}/kws/.done does not exist."
      echo "Create the directory data/${eval2shadow} first, by calling $0 --type $eval2shadow --dataonly"
      exit 1
    fi


    local/kws_data_prep.sh --case_insensitive $case_insensitive \
      "${icu_opt[@]}" \
      data/lang ${datadir} ${datadir}/kws
    utils/fix_data_dir.sh ${datadir}

    touch ${datadir}/kws/.done
  else
    kws_flags=()
    if [ ! -z $my_rttm_file ] ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if [ $my_subset_ecf ] ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    
    local/kws_setup.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file data/lang ${datadir}

    touch ${datadir}/kws/.done
  fi
fi

echo ---------------------------------------------------------------------
echo "Resegment data in data_filtered_reseg on " `date`
echo ---------------------------------------------------------------------

sh -x local/run_filter_resegment.sh --nj $my_nj --segmentation-opts "$segmentation_opts" || exit 1

datadir=data_filtered_reseg/${type}
#####################################################################
#
# data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${type} kws data files in ${datadir} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws  && [ ! -f ${datadir}/kws/.done ] ; then
  if [[ $type == shadow ]]; then
    
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data_filtered_reseg/${dev2shadow}/kws/.done ]; then
      echo "Error: data_filtered_reseg/${dev2shadow}/kws/.done does not exist."
      echo "Create the directory data_filtered_reseg/${dev2shadow} first, by calling $0 --type $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data_filtered_reseg/${eval2shadow}/kws/.done ]; then
      echo "Error: data_filtered_reseg/${eval2shadow}/kws/.done does not exist."
      echo "Create the directory data_filtered_reseg/${eval2shadow} first, by calling $0 --type $eval2shadow --dataonly"
      exit 1
    fi


    local/kws_data_prep.sh --case_insensitive $case_insensitive \
      "${icu_opt[@]}" \
      data/lang ${datadir} ${datadir}/kws
    utils/fix_data_dir.sh ${datadir}

    touch ${datadir}/kws/.done
  else
    kws_flags=()
    if [ ! -z $my_rttm_file ] ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if [ $my_subset_ecf ] ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    
    local/kws_setup.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file data/lang ${datadir}

    touch ${datadir}/kws/.done
  fi
fi

if $data_only ; then
  echo "Exiting, as data-only was requested..."
  exit 0;
fi

if $train_after_reseg; then
  echo ---------------------------------------------------------------------
  echo "Starting (SAT) triphone training after resegmentation in exp/tri5_filtered_reseg on" `date`
  echo ---------------------------------------------------------------------

  if [ ! -f exp/tri5_filtered_reseg/.done ]; then
    steps/align_si.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data_filtered_reseg/train data/lang exp/tri4_filtered exp/tri4_ali_filtered_reseg
    steps/train_sat.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" \
      $numLeavesSAT $numGaussSAT data_filtered_reseg/train data/lang exp/tri4_ali_filtered_reseg exp/tri5_filtered_reseg
    touch exp/tri5_filtered_reseg/.done
  fi

  ################################################################################
  # Ready to start SGMM training
  ################################################################################

  if [ ! -f exp/tri5_ali_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/tri5_ali_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/align_fmllr.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data_filtered_reseg/train data/lang exp/tri5_filtered_reseg exp/tri5_ali_filtered_reseg
    touch exp/tri5_ali_filtered_reseg/.done
  fi

  if [ ! -f exp/ubm5_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/ubm5_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/train_ubm.sh \
      --cmd "$train_cmd" $numGaussUBM \
      data_filtered_reseg/train data/lang exp/tri5_ali_filtered_reseg exp/ubm5_filtered_reseg
    touch exp/ubm5_filtered_reseg/.done
  fi

  if [ ! -f exp/sgmm5_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/sgmm5_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/train_sgmm2.sh \
      --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
      data_filtered_reseg/train data/lang exp/tri5_ali_filtered_reseg exp/ubm5_filtered_reseg/final.ubm exp/sgmm5_filtered_reseg
    #steps/train_sgmm2_group.sh \
      #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
      #  data_filtered_reseg/train data/lang exp/tri5_ali_filtered_reseg exp/ubm5_filtered_reseg/final.ubm exp/sgmm5_filtered_reseg
    touch exp/sgmm5_filtered_reseg/.done
  fi

  ################################################################################
  # Ready to start discriminative SGMM training
  ################################################################################

  if [ ! -f exp/sgmm5_ali_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/sgmm5_ali_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/align_sgmm2.sh \
      --nj $train_nj --cmd "$train_cmd" --transform-dir exp/tri5_ali_filtered_reseg \
      --use-graphs true --use-gselect true \
      data_filtered_reseg/train data/lang exp/sgmm5_filtered_reseg exp/sgmm5_ali_filtered_reseg
    touch exp/sgmm5_ali_filtered_reseg/.done
  fi

  if [ ! -f exp/sgmm5_denlats_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/sgmm5_denlats_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/make_denlats_sgmm2.sh \
      --nj $train_nj --sub-split $train_nj "${sgmm_denlats_extra_opts[@]}" \
      --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/tri5_ali_filtered_reseg \
      data_filtered_reseg/train data/lang exp/sgmm5_ali_filtered_reseg exp/sgmm5_denlats_filtered_reseg
    touch exp/sgmm5_denlats_filtered_reseg/.done
  fi

  if [ ! -f exp/sgmm5_mmi_b0.1_filtered_reseg/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/sgmm5_mmi_b0.1_filtered_reseg on" `date`
    echo ---------------------------------------------------------------------
    steps/train_mmi_sgmm2.sh \
      --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
      --zero-if-disjoint true --transform-dir exp/tri5_ali_filtered_reseg --boost 0.1 \
      data_filtered_reseg/train data/lang exp/sgmm5_ali_filtered_reseg exp/sgmm5_denlats_filtered_reseg \
      exp/sgmm5_mmi_b0.1_filtered_reseg
    touch exp/sgmm5_mmi_b0.1_filtered_reseg/.done
  fi
fi


####################################################################
##
## FMLLR decoding 
##
####################################################################
tri5=tri5_filtered
$train_after_reseg && tri5=tri5_filtered_reseg
decode=exp/${tri5}/decode_${dirid}_reseg

if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/$tri5 exp/$tri5/graph |tee exp/$tri5/mkgraph.log

  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --skip-scoring true --beam 10 --lattice-beam 4\
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/$tri5/graph ${datadir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
fi

if ! $fast_path ; then
  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data/lang ${decode}

  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data/lang ${decode}.si
fi

####################################################################
## SGMM2 decoding 
####################################################################
sgmm5=sgmm5_filtered
$train_after_reseg && sgmm5=sgmm5_filtered_reseg
decode=exp/${sgmm5}/decode_fmllr_${dirid}_reseg

if [ ! -f $decode/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning $decode on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/$sgmm5 exp/$sgmm5/graph |tee exp/$sgmm5/mkgraph.log

  mkdir -p $decode
  steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
    --cmd "$decode_cmd" --transform-dir exp/${tri5}/decode_${dirid}_reseg "${decode_extra_opts[@]}"\
    exp/$sgmm5/graph ${datadir} $decode |tee $decode/decode.log
  touch $decode/.done

  if ! $fast_path ; then
    local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
      "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
      ${datadir} data/lang ${decode}
  fi
fi

####################################################################
##
## SGMM_MMI rescoring
##
####################################################################

for iter in 1 2 3 4; do
  # Decode SGMM+MMI (via rescoring).
  sgmm5_mmi_b0_1=sgmm5_mmi_b0.1_filtered
  $train_after_reseg && sgmm5_mmi_b0_1=sgmm5_mmi_b0.1_filtered_reseg
  decode=exp/${sgmm5_mmi_b0_1}/decode_fmllr_${dirid}_it${iter}_reseg
  if [ ! -f $decode/.done ]; then

    mkdir -p $decode
    steps/decode_sgmm2_rescore.sh  --skip-scoring true \
      --cmd "$decode_cmd" --iter $iter --transform-dir exp/$tri5/decode_${dirid}_reseg \
      data/lang ${datadir} exp/$sgmm5/decode_fmllr_${dirid}_reseg $decode | tee ${decode}/decode.log

    touch $decode/.done
  fi
    
  #We are done -- all lattices has been generated. We have to
  #a)Run MBR decoding
  #b)Run KW search
  sh -x local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data/lang $decode || exit 1
done

####################################################################
##
## DNN decoding
##
####################################################################
tri6_nnet=tri6_nnet_filtered
$train_after_reseg && tri6_nnet=tri6_nnet_filtered_reseg
decode=exp/$tri6_nnet/decode_${dirid}_reseg

if [ -f $decode/.done ]; then
  steps/decode_nnet_cpu.sh --cmd "$decode_cmd" --nj $my_nj \
    --skip-scoring true "${decode_extra_opts[@]}" \
    --transform-dir exp/$tri6_nnet/decode_${dirid}_reseg \
    exp/$tri6_nnet/graph ${datadir} $decode |tee $decode/decode.log

  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data/lang $decode || exit 1
  touch $decode/.done
fi

echo "Everything looking good...." 

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
