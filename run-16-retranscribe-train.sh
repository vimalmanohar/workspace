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

share_silence_phones=true
data_only=false
train_decode_dir=exp/tri5/decode_train_reseg/score_10
train_ali_dir=exp/tri5_ali
add_fillers_opts="--num-fillers 5 --count-threshold 30"
extract_insertions_opts=          # Give "--segments data/train/segments" if you want to add insertions only outside the human segments

. ./path.sh
. utils/parse_options.sh

mkdir -p data_augmented

[ -z "$add_fillers_opts" ] && exit 1

sh -x local/run_retranscribe.sh --extract-insertions-opts "$extract_insertions_opts" --add-fillers-opts "$add_fillers_opts" --get-whole-transcripts false $train_decode_dir $train_ali_dir data_augmented/train || exit 1

mkdir -p data_augmented/local
cat data_augmented/train/text | tr ' ' '\n' | \
  sed -n '/<.*>/p' | sed '/'$oovSymbol'/d' | \
  sort -u > data_augmented/local/fillers.list

if [[ ! -f data_augmented/local/lexicon.txt || data_augmented/local/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data_augmented/local on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_lexicon_separate_fillers.pl --add data_augmented/local/fillers.list --phonemap "$phoneme_mapping" \
    $lexiconFlags $lexicon_file data_augmented/local
fi

mkdir -p data_augmented/lang
if [[ ! -f data_augmented/lang/L.fst || data_augmented/lang/L.fst -ot data_augmented/local/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating L.fst etc in data_augmented/lang on" `date`
  echo ---------------------------------------------------------------------
  utils/prepare_lang.sh \
    --share-silence-phones $share_silence_phones \
    data_augmented/local $oovSymbol data_augmented/local/tmp.lang data_augmented/lang
fi

# We will simply override the default G.fst by the G.fst generated using SRILM
if [[ ! -f data_augmented/srilm/lm.gz || data_augmented/srilm/lm.gz -ot data_augmented/train/text ]]; then
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  local/train_lms_srilm.sh --dev-text data/dev2h/text \
    --train-text data_augmented/train/text data_augmented data_augmented/srilm 
fi

if [[ ! -f data_augmented/lang/G.fst || data_augmented/lang/G.fst -ot data_augmented/srilm/lm.gz ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.fst on " `date`
  echo ---------------------------------------------------------------------
  local/arpa2G.sh data_augmented/srilm/lm.gz data_augmented/lang data_augmented/lang
fi
  
if [ ! -f data_augmented/train_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data_augmented in data_augmented/train_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data_augmented/train/feats.scp | wc -l`;
  utils/subset_data_dir.sh data_augmented/train  5000 data_augmented/train_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data_augmented/train 10000 data_augmented/train_sub2
  else
    (cd data_augmented; ln -s train train_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data_augmented/train 20000 data_augmented/train_sub3
  else
    (cd data_augmented; ln -s train train_sub3 )
  fi

  touch data_augmented/train_sub3/.done
fi

if $data_only; then
  echo "Data preparation done !"
  exit 0
fi

if [ ! -f exp/mono_augmented/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/mono_augmented on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data_augmented/train_sub1 data_augmented/lang exp/mono_augmented
  touch exp/mono_augmented/.done
fi

if [ ! -f exp/tri1_augmented/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/tri1_augmented on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data_augmented/train_sub2 data_augmented/lang exp/mono_augmented exp/mono_augmented_ali_sub2
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data_augmented/train_sub2 data_augmented/lang exp/mono_augmented_ali_sub2 exp/tri1_augmented
  touch exp/tri1_augmented/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/tri2_augmented on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri2_augmented/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data_augmented/train_sub3 data_augmented/lang exp/tri1_augmented exp/tri1_augmented_ali_sub3
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data_augmented/train_sub3 data_augmented/lang exp/tri1_augmented_ali_sub3 exp/tri2_augmented
  touch exp/tri2_augmented/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/tri3_augmented on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri3_augmented/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data_augmented/train data_augmented/lang exp/tri2_augmented exp/tri2_augmented_ali
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data_augmented/train data_augmented/lang exp/tri2_augmented_ali exp/tri3_augmented
  touch exp/tri3_augmented/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4_augmented on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4_augmented/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data_augmented/train data_augmented/lang exp/tri3_augmented exp/tri3_augmented_ali
  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data_augmented/train data_augmented/lang exp/tri3_augmented_ali exp/tri4_augmented
  touch exp/tri4_augmented/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5_augmented on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5_augmented/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data_augmented/train data_augmented/lang exp/tri4_augmented exp/tri4_augmented_ali
  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data_augmented/train data_augmented/lang exp/tri4_augmented_ali exp/tri5_augmented
  touch exp/tri5_augmented/.done
fi

################################################################################
# Ready to start SGMM training
################################################################################

if [ ! -f exp/tri5_augmented_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_augmented_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data_augmented/train data_augmented/lang exp/tri5_augmented exp/tri5_augmented_ali
  touch exp/tri5_augmented_ali/.done
fi

if [ ! -f exp/ubm5_augmented/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/ubm5_augmented on" `date`
  echo ---------------------------------------------------------------------
  steps/train_ubm.sh \
    --cmd "$train_cmd" $numGaussUBM \
    data_augmented/train data_augmented/lang exp/tri5_augmented_ali exp/ubm5_augmented
  touch exp/ubm5_augmented/.done
fi

if [ ! -f exp/sgmm5_augmented/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_augmented on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sgmm2.sh \
    --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
    data_augmented/train data_augmented/lang exp/tri5_augmented_ali exp/ubm5_augmented/final.ubm exp/sgmm5_augmented
  #steps/train_sgmm2_group.sh \
  #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
  #  data_augmented/train data_augmented/lang exp/tri5_augmented_ali exp/ubm5_augmented/final.ubm exp/sgmm5_augmented
  touch exp/sgmm5_augmented/.done
fi

################################################################################
# Ready to start discriminative SGMM training
################################################################################

if [ ! -f exp/sgmm5_augmented_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_augmented_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_sgmm2.sh \
    --nj $train_nj --cmd "$train_cmd" --transform-dir exp/tri5_augmented_ali \
    --use-graphs true --use-gselect true \
    data_augmented/train data_augmented/lang exp/sgmm5_augmented exp/sgmm5_augmented_ali
  touch exp/sgmm5_augmented_ali/.done
fi

if [ ! -f exp/sgmm5_augmented_denlats/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_augmented_denlats on" `date`
  echo ---------------------------------------------------------------------
  steps/make_denlats_sgmm2.sh \
    --nj $train_nj --sub-split $train_nj "${sgmm_denlats_extra_opts[@]}" \
    --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/tri5_augmented_ali \
    data_augmented/train data_augmented/lang exp/sgmm5_augmented_ali exp/sgmm5_augmented_denlats
  touch exp/sgmm5_augmented_denlats/.done
fi

if [ ! -f exp/sgmm5_augmented_mmi_b0.1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_augmented_mmi_b0.1 on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mmi_sgmm2.sh \
    --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
    --zero-if-disjoint true --transform-dir exp/tri5_augmented_ali --boost 0.1 \
    data_augmented/train data_augmented/lang exp/sgmm5_augmented_ali exp/sgmm5_augmented_denlats \
    exp/sgmm5_augmented_mmi_b0.1
  touch exp/sgmm5_augmented_mmi_b0.1/.done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
