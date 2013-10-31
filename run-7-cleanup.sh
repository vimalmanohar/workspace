#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.

[ ! -f ./lang.conf ] && echo "Language configuration does not exist! Use the configurations in conf/lang/* as a startup" && exit 1
[ ! -f ./conf/common_vars.sh ] && echo "the file conf/common_vars.sh does not exist!" && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf
threshold=15

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

if [[ ! -f data/train_filtered/utt2spk ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing filtered acoustic training lists in data/train_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/discriminative_data_cleanup.sh --cmd "$decode_cmd" --threshold $threshold exp/sgmm5_denlats data/train || exit 1
fi

if [[ ! -f data/train_filtered/glm || data/train_filtered/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing train_filtered stm files in data/train_filtered on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_stm.pl --fragmentMarkers \-\*\~ data/train_filtered || exit 1
fi

if [ ! -f data/train_filtered_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/train_filtered_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/train_filtered/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/train_filtered  5000 data/train_filtered_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data/train_filtered 10000 data/train_filtered_sub2
  else
    if [ -L data/train_filtered_sub2 ]; then
      rm data/train_filtered_sub2
    fi
    (cd data; ln -s train_filtered train_filtered_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data/train_filtered 20000 data/train_filtered_sub3
  else
    if [ -L data/train_filtered_sub3 ]; then
      rm data/train_filtered_sub3
    fi
    (cd data; ln -s train_filtered train_filtered_sub3 )
  fi

  touch data/train_filtered_sub3/.done
fi

if [ ! -f exp/mono_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/mono_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data/train_filtered_sub1 data/lang exp/mono_filtered
  touch exp/mono_filtered/.done
fi

if [ ! -f exp/tri1_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/tri1_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data/train_filtered_sub2 data/lang exp/mono_filtered exp/mono_ali_sub2_filtered
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data/train_filtered_sub2 data/lang exp/mono_ali_sub2_filtered exp/tri1_filtered
  touch exp/tri1_filtered/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/tri2_filtered on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri2_filtered/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data/train_filtered_sub3 data/lang exp/tri1_filtered exp/tri1_ali_sub3_filtered
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data/train_filtered_sub3 data/lang exp/tri1_ali_sub3_filtered exp/tri2_filtered
  touch exp/tri2_filtered/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/tri3_filtered on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri3_filtered/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri2_filtered exp/tri2_ali_filtered
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data/train data/lang exp/tri2_ali_filtered exp/tri3_filtered
  touch exp/tri3_filtered/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4_filtered on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4_filtered/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri3_filtered exp/tri3_ali_filtered
  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data/train data/lang exp/tri3_ali_filtered exp/tri4_filtered
  touch exp/tri4_filtered/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5_filtered on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5_filtered/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri4_filtered exp/tri4_ali_filtered
  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/train data/lang exp/tri4_ali_filtered exp/tri5_filtered
  touch exp/tri5_filtered/.done
fi

################################################################################
# Ready to start SGMM training
################################################################################

if [ ! -f exp/tri5_ali_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_ali_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri5_filtered exp/tri5_ali_filtered
  touch exp/tri5_ali_filtered/.done
fi

if [ ! -f exp/ubm5_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/ubm5_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/train_ubm.sh \
    --cmd "$train_cmd" $numGaussUBM \
    data/train data/lang exp/tri5_ali_filtered exp/ubm5_filtered
  touch exp/ubm5_filtered/.done
fi

if [ ! -f exp/sgmm5_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sgmm2.sh \
    --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
    data/train data/lang exp/tri5_ali_filtered exp/ubm5_filtered/final.ubm exp/sgmm5_filtered
  #steps/train_sgmm2_group.sh \
  #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
  #  data/train data/lang exp/tri5_ali_filtered exp/ubm5_filtered/final.ubm exp/sgmm5_filtered
  touch exp/sgmm5_filtered/.done
fi

################################################################################
# Ready to start discriminative SGMM training
################################################################################

if [ ! -f exp/sgmm5_ali_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_ali_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/align_sgmm2.sh \
    --nj $train_nj --cmd "$train_cmd" --transform-dir exp/tri5_ali_filtered \
    --use-graphs true --use-gselect true \
    data/train data/lang exp/sgmm5_filtered exp/sgmm5_ali_filtered
  touch exp/sgmm5_ali_filtered/.done
fi

if [ ! -f exp/sgmm5_denlats_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_denlats_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/make_denlats_sgmm2.sh \
    --nj $train_nj --sub-split $train_nj "${sgmm_denlats_extra_opts[@]}" \
    --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/tri5_ali_filtered \
    data/train data/lang exp/sgmm5_ali_filtered exp/sgmm5_denlats_filtered
  touch exp/sgmm5_denlats_filtered/.done
fi

if [ ! -f exp/sgmm5_mmi_b0.1_filtered/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_mmi_b0.1_filtered on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mmi_sgmm2.sh \
    --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
    --zero-if-disjoint true --transform-dir exp/tri5_ali_filtered --boost 0.1 \
    data/train data/lang exp/sgmm5_ali_filtered exp/sgmm5_denlats_filtered \
    exp/sgmm5_mmi_b0.1_filtered
  touch exp/sgmm5_mmi_b0.1_filtered/.done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
