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

data_only=false
share_silence_phones=true
keep_silence_segments=false
silence_segment_fraction=0.0
. ./path.sh
. utils/parse_options.sh

((silence_segment_fraction > 1.0)) && exit 1
((silence_segment_fraction < 0.0)) && exit 1

mkdir -p data
[ -e exp ] || ln -s "$exp_dir" exp || exit 1

#Preparing dev2h and train directories
if [ ! -d data/raw_train_data ]; then
    echo ---------------------------------------------------------------------
    echo "Subsetting the TRAIN set"
    echo ---------------------------------------------------------------------

    local/make_corpus_subset.sh "$train_data_dir" "$train_data_list" ./data/raw_train_data
    train_data_dir=`readlink -f ./data/raw_train_data`

    nj_max=`cat $train_data_list | wc -l`
    if [[ "$nj_max" -lt "$train_nj" ]] ; then
        echo "The maximum reasonable number of jobs is $nj_max (you have $train_nj)! (The training and decoding process has file-granularity)"
        exit 1;
        train_nj=$nj_max
    fi
fi
train_data_dir=`readlink -f ./data/raw_train_data`

if [ ! -d data/raw_dev2h_data ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the DEV2H set"
  echo ---------------------------------------------------------------------  
  local/make_corpus_subset.sh "$dev2h_data_dir" "$dev2h_data_list" ./data/raw_dev2h_data || exit 1
fi

if [ ! -d data/raw_dev10h_data ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the DEV10H set"
  echo ---------------------------------------------------------------------  
  local/make_corpus_subset.sh "$dev10h_data_dir" "$dev10h_data_list" ./data/raw_dev10h_data || exit 1
fi

decode_nj=$dev2h_nj
nj_max=`cat $dev2h_data_list | wc -l`
if [[ "$nj_max" -lt "$decode_nj" ]] ; then
  echo "The maximum reasonable number of jobs is $nj_max -- you have $decode_nj! (The training and decoding process has file-granularity)"
  exit 1
  decode_nj=$nj_max
fi

mkdir -p data/local
if [[ ! -f data/local/lexicon.txt || data/local/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data/local on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_lexicon.pl  --phonemap "$phoneme_mapping" \
    $lexiconFlags $lexicon_file data/local
fi

mkdir -p data/lang
if [[ ! -f data/lang/L.fst || data/lang/L.fst -ot data/local/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating L.fst etc in data/lang on" `date`
  echo ---------------------------------------------------------------------
  utils/prepare_lang.sh \
    --share-silence-phones $share_silence_phones \
    data/local $oovSymbol data/local/tmp.lang data/lang
fi

if [[ ! -f data/dev2h/wav.scp || data/dev2h/wav.scp -ot ./data/raw_dev2h_data/audio ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing dev2h data lists in data/dev2h on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/dev2h
  local/prepare_acoustic_training_data.pl \
    --fragmentMarkers \-\*\~ \
    `pwd`/data/raw_dev2h_data data/dev2h > data/dev2h/skipped_utts.log || exit 1
fi

if [[ ! -f data/dev2h/glm || data/dev2h/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing dev2h stm files in data/dev2h on" `date`
  echo ---------------------------------------------------------------------
  if [ -z $stm_file ]; then 
    echo "WARNING: You should define the variable stm_file pointing to the IndusDB stm"
    echo "WARNING: Doing that, it will give you scoring close to the NIST scoring.    "
    local/prepare_stm.pl --fragmentMarkers \-\*\~ data/dev2h || exit 1
  else
    local/augment_original_stm.pl $stm_file data/dev2h || exit 1
  fi
  [ ! -z $glmFile ] && cp $glmFile data/dev2h/glm

fi

# We will simply override the default G.fst by the G.fst generated using SRILM
if [[ ! -f data/srilm/lm.gz || data/srilm/lm.gz -ot data/train/text ]]; then
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  local/train_lms_srilm.sh --dev-text data/dev2h/text \
    --train-text data/train/text data data/srilm 
fi
if [[ ! -f data/lang/G.fst || data/lang/G.fst -ot data/srilm/lm.gz ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.fst on " `date`
  echo ---------------------------------------------------------------------
  local/arpa2G.sh data/srilm/lm.gz data/lang data/lang
fi

if [[ ! -f data/train_whole/wav.scp || ! -f data/train_whole/text || data/train_whole/wav.scp -ot "$train_data_dir" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train_whole
  local/prepare_acoustic_training_data_whole.pl \
    --vocab data/local/lexicon.txt --fragmentMarkers \-\*\~ \
    $train_data_dir data/train_whole > data/train_whole/skipped_utts.log
  mv data/train_whole/text data/train_whole/text_orig
  if $keep_silence_segments; then
    cat data/train_whole/text_orig | awk '{if (NF == 2 && $2 == "<silence>") {print $1} else {print $0}}' > data/train_whole/text
  else
    num_silence_segments=$(cat data/train_whole/text_orig | awk '{if (NF == 2 && $2 == "<silence>") {print $0}}' | wc -l)
    num_keep_silence_segments=`echo $num_silence_segments | python -c "import sys; sys.stdout.write(\"%d\" % (float(sys.stdin.readline().strip()) * "$silence_segment_fraction"))"` 
    cat data/train_whole/text_orig \
      | awk 'BEGIN{i=0} \
      { \
        if (NF == 2 && $2 == "<silence>") { \
          if (i<'$num_keep_silence_segments') { \
            print $1; \
            i++; \
          } \
        } else {print $0}\
      }' > data/train_whole/text
  fi
  utils/fix_data_dir.sh data/train_whole
fi

if [[ ! -f data/train_whole/glm || data/train_whole/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing train stm files in data/train_whole on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_stm.pl --fragmentMarkers \-\*\~ data/train_whole || exit 1
fi

echo ---------------------------------------------------------------------
echo "Starting plp feature extraction for data/train in plp on" `date`
echo ---------------------------------------------------------------------

use_pitch=false
use_ffv=false

if [ ! -f data/train_whole/.plp.done ]; then
  steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train_whole exp/make_plp/train_whole plp_whole

  steps/compute_cmvn_stats.sh \
    data/train_whole exp/make_plp/train_whole plp_whole
  # In case plp or pitch extraction failed on some utterances, delist them
  utils/fix_data_dir.sh data/train_whole
  touch data/train_whole/.plp.done
fi

if [ ! -f data/train_whole_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/train_whole_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/train_whole/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/train_whole  5000 data/train_whole_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data/train_whole 10000 data/train_whole_sub2
  else
    (cd data; ln -s train_whole train_whole_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data/train_whole 20000 data/train_whole_sub3
  else
    (cd data; ln -s train_whole train_whole_sub3 )
  fi

  touch data/train_whole_sub3/.done
fi

if $data_only; then
  echo "Data preparation done !"
  exit 0
fi

if [ ! -f exp/tri4_whole_ali_sub3/.done ]; then
  steps/align_fmllr.sh --nj $train_nj --cmd "$train_cmd" \
    data/train_whole_sub3 data/lang exp/tri4 exp/tri4_whole_ali_sub3 || exit 1;
  touch exp/tri4_whole_ali_sub3/.done
fi

if [ ! -f exp/tri4b_whole_seg/.done ]; then
  steps/train_lda_mllt.sh --cmd "$train_cmd" --realign-iters "" \
    1000 10000 data/train_whole_sub3 data/lang exp/tri4_whole_ali_sub3 exp/tri4b_whole_seg || exit 1;
  touch exp/tri4b_whole_seg/.done
fi

if [ ! -f exp/tri4_whole_ali_all/.done ]; then
  steps/align_fmllr.sh --nj $train_nj --cmd "$train_cmd" \
    data/train_whole data/lang exp/tri4 exp/tri4_whole_ali_all || exit 1;
  touch exp/tri4_whole_ali_all/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4_whole on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4_whole/.done ]; then
  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data/train_whole data/lang exp/tri4_whole_ali_all exp/tri4_whole
  touch exp/tri4_whole/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5_whole on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5_whole/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train_whole data/lang exp/tri4 exp/tri4_ali
  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/train_whole data/lang exp/tri4_ali exp/tri5_whole
  touch exp/tri5_whole/.done
fi

################################################################################
# Ready to start SGMM training
################################################################################

if [ ! -f exp/tri5_whole_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_whole_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train_whole data/lang exp/tri5_whole exp/tri5_whole_ali
  touch exp/tri5_whole_ali/.done
fi

if [ ! -f exp/ubm5_whole/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/ubm5_whole on" `date`
  echo ---------------------------------------------------------------------
  steps/train_ubm.sh \
    --cmd "$train_cmd" $numGaussUBM \
    data/train_whole data/lang exp/tri5_whole_ali exp/ubm5_whole
  touch exp/ubm5_whole/.done
fi

if [ ! -f exp/sgmm5_whole/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_whole on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sgmm2.sh \
    --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
    data/train_whole data/lang exp/tri5_whole_ali exp/ubm5_whole/final.ubm exp/sgmm5_whole
  #steps/train_sgmm2_group.sh \
  #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
  #  data/train_whole data/lang exp/tri5_whole_ali exp/ubm5_whole/final.ubm exp/sgmm5_whole
  touch exp/sgmm5_whole/.done
fi

################################################################################
# Ready to start discriminative SGMM training
################################################################################

if [ ! -f exp/sgmm5_whole_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_whole_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_sgmm2.sh \
    --nj $train_nj --cmd "$train_cmd" --transform-dir exp/tri5_whole_ali \
    --use-graphs true --use-gselect true \
    data/train_whole data/lang exp/sgmm5_whole exp/sgmm5_whole_ali
  touch exp/sgmm5_whole_ali/.done
fi

if [ ! -f exp/sgmm5_whole_denlats/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_whole_denlats on" `date`
  echo ---------------------------------------------------------------------
  steps/make_denlats_sgmm2.sh \
    --nj $train_nj --sub-split $train_nj "${sgmm_denlats_extra_opts[@]}" \
    --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/tri5_whole_ali \
    data/train_whole data/lang exp/sgmm5_whole_ali exp/sgmm5_whole_denlats
  touch exp/sgmm5_whole_denlats/.done
fi

if [ ! -f exp/sgmm5_whole_mmi_b0.1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/sgmm5_whole_mmi_b0.1 on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mmi_sgmm2.sh \
    --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
    --zero-if-disjoint true --transform-dir exp/tri5_whole_ali --boost 0.1 \
    data/train_whole data/lang exp/sgmm5_whole_ali exp/sgmm5_whole_denlats \
    exp/sgmm5_whole_mmi_b0.1
  touch exp/sgmm5_whole_mmi_b0.1/.done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
