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
fast_path=true
skip_kws=false
skip_stt=false
max_states=150000
wip=0.5
stage=-10

. utils/parse_options.sh
. ./path.sh
. ./cmd.sh

eval my_nj=\$${type}_nj  #for shadow, this will be re-set when appropriate
if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

if [[ "$type" != "dev10h" && "$type" != "dev2h" && "$type" != "eval" && "$type" != "shadow" ]] ; then
  echo "Warning: invalid variable type=${type}, valid values are dev10h|dev2h|eval"
  echo "Hope you know what your ar doing!"
fi

datadir=data_reseg/${type}
dirid=${type}

####################################################################
##
## FMLLR decoding 
##
####################################################################
tri5=tri5_augmented
decode=exp/${tri5}/decode_${dirid}_reseg

if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data_augmented/lang exp/$tri5 exp/$tri5/graph |tee exp/$tri5/mkgraph.log

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
    ${datadir} data_augmented/lang ${decode}

  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data_augmented/lang ${decode}.si
fi

####################################################################
## SGMM2 decoding 
####################################################################
sgmm5=sgmm5_augmented
decode=exp/${sgmm5}/decode_fmllr_${dirid}_reseg

if [ ! -f $decode/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning $decode on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data_augmented/lang exp/$sgmm5 exp/$sgmm5/graph |tee exp/$sgmm5/mkgraph.log

  mkdir -p $decode
  steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
    --cmd "$decode_cmd" --transform-dir exp/${tri5}/decode_${dirid}_reseg "${decode_extra_opts[@]}"\
    exp/$sgmm5/graph ${datadir} $decode |tee $decode/decode.log
  touch $decode/.done

  if ! $fast_path ; then
    local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
      "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
      ${datadir} data_augmented/lang ${decode}
  fi
fi

####################################################################
##
## SGMM_MMI rescoring
##
####################################################################

for iter in 1 2 3 4; do
  # Decode SGMM+MMI (via rescoring).
  sgmm5_mmi_b0_1=sgmm5_augmented_mmi_b0.1
  decode=exp/${sgmm5_mmi_b0_1}/decode_fmllr_${dirid}_it${iter}_reseg
  if [ ! -f $decode/.done ]; then

    mkdir -p $decode
    steps/decode_sgmm2_rescore.sh  --skip-scoring true \
      --cmd "$decode_cmd" --iter $iter --transform-dir exp/$tri5/decode_${dirid}_reseg \
      data_augmented/lang ${datadir} exp/$sgmm5/decode_fmllr_${dirid}_reseg $decode | tee ${decode}/decode.log
    touch $decode/.done
  fi

  #We are done -- all lattices has been generated. We have to
  #a)Run MBR decoding
  #b)Run KW search
  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data_augmented/lang $decode
done

exit 0

####################################################################
##
## DNN decoding
##
####################################################################
tri6_nnet=tri6_augmented_nnet
decode=exp/$tri6_nnet/decode_${dirid}_reseg

if [ -f $decode/.done ]; then
  steps/decode_nnet_cpu.sh --cmd "$decode_cmd" --nj $my_nj \
    --skip-scoring true "${decode_extra_opts[@]}" \
    --transform-dir exp/$tri6_nnet/decode_${dirid}_reseg \
    exp/$tri6_nnet/graph ${datadir} $decode |tee $decode/decode.log
  touch $decode/.done
fi

local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
  --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
  "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
  ${datadir} data_augmented/lang $decode

echo "Everything looking good...." 

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

